import Ably

public final class ChatAPI: Sendable {
    private let realtime: RealtimeClient
    private let apiVersion = "/chat/v1"

    public init(realtime: RealtimeClient) {
        self.realtime = realtime
    }

    internal func getChannel(_ messagesChannelName: String) -> any RealtimeChannelProtocol {
        realtime.getChannel(messagesChannelName)
    }

    // (CHA-M6) Messages should be queryable from a paginated REST API.
    public func getMessages(roomId: String, params: QueryOptions) async throws -> any PaginatedResult<Message> {
        let endpoint = "\(apiVersion)/rooms/\(roomId)/messages"
        return try await makeAuthorizedPaginatedRequest(endpoint, params: params.toDictionary())
    }

    internal struct SendMessageResponse: Codable {
        internal let timeserial: String
        internal let createdAt: Int64
    }

    // (CHA-M3) Messages are sent to Ably via the Chat REST API, using the send method.
    // (CHA-M3a) When a message is sent successfully, the caller shall receive a struct representing the Message in response (as if it were received via Realtime event).
    public func sendMessage(roomId: String, params: SendMessageParams) async throws -> Message {
        let endpoint = "\(apiVersion)/rooms/\(roomId)/messages"
        var body: [String: Any] = ["text": params.text]

        // (CHA-M3b) A message may be sent without metadata or headers. When these are not specified by the user, they must be omitted from the REST payload.
        if let metadata = params.metadata {
            body["metadata"] = metadata

            // (CHA-M3c) metadata must not contain the key ably-chat. This is reserved for future internal use. If this key is present, the send call shall terminate by throwing an ErrorInfo with code 40001.
            if metadata.contains(where: { $0.key == "ably-chat" }) {
                throw ARTErrorInfo.create(withCode: 40001, message: "metadata must not contain the key `ably-chat`")
            }
        }

        if let headers = params.headers {
            body["headers"] = headers

            // (CHA-M3d) headers must not contain a key prefixed with ably-chat. This is reserved for future internal use. If this key is present, the send call shall terminate by throwing an ErrorInfo with code 40001.
            if headers.keys.contains(where: { keyString in
                keyString.hasPrefix("ably-chat")
            }) {
                throw ARTErrorInfo.create(withCode: 40001, message: "headers must not contain any key with a prefix of `ably-chat`")
            }
        }

        let response: SendMessageResponse = try await makeAuthorizedRequest(endpoint, method: "POST", body: body)

        // response.createdAt is in milliseconds, convert it to seconds
        let createdAtInSeconds = TimeInterval(integerLiteral: response.createdAt / 1000)

        let message = Message(
            timeserial: response.timeserial,
            clientID: realtime.clientId ?? "",
            roomID: roomId,
            text: params.text,
            createdAt: Date(timeIntervalSince1970: createdAtInSeconds),
            metadata: params.metadata ?? [:],
            headers: params.headers ?? [:]
        )
        return message
    }

    public func getOccupancy(roomId: String) async throws -> OccupancyEvent {
        let endpoint = "\(apiVersion)/rooms/\(roomId)/occupancy"
        return try await makeAuthorizedRequest(endpoint, method: "GET")
    }

    // TODO: Improve as part of occupancy/presence
    private func makeAuthorizedRequest<Response: Codable>(_ url: String, method: String, body: [String: Any]? = nil) async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try realtime.request(method, path: url, params: [:], body: body, headers: [:]) { paginatedResponse, error in
                    if let error {
                        // (CHA-M3e) If an error is returned from the REST API, its ErrorInfo representation shall be thrown as the result of the send call.
                        continuation.resume(throwing: ARTErrorInfo.create(from: error))
                        return
                    }

                    guard let firstItem = paginatedResponse?.items.first else {
                        continuation.resume(throwing: ChatError.noItemInResponse)
                        return
                    }

                    do {
                        let decodedResponse = try DictionaryDecoder().decode(Response.self, from: firstItem)
                        continuation.resume(returning: decodedResponse)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func makeAuthorizedPaginatedRequest<Response: Codable & Sendable>(
        _ url: String,
        params: [String: String]? = nil,
        body: [String: Any]? = nil
    ) async throws -> any PaginatedResult<Response> {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PaginatedResultWrapper<Response>, _>) in
            do {
                try realtime.request("GET", path: url, params: params, body: nil, headers: [:]) { paginatedResponse, error in
                    ARTHTTPPaginatedCallbackWrapper<Response>(callbackResult: (paginatedResponse, error)).handleResponse(continuation: continuation)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    internal enum ChatError: Error {
        case noItemInResponse
    }
}

internal struct DictionaryDecoder {
    private let decoder = JSONDecoder()

    // Function to decode from a dictionary
    internal func decode<T: Decodable>(_: T.Type, from dictionary: NSDictionary) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try decoder.decode(T.self, from: data)
    }

    // Function to decode from a dictionary array
    internal func decode<T: Decodable>(_: T.Type, from dictionary: [NSDictionary]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: dictionary)
        return try decoder.decode(T.self, from: data)
    }
}
