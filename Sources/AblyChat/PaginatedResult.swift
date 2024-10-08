import Ably

public protocol PaginatedResult<T>: AnyObject, Sendable {
    associatedtype T

    var items: [T] { get }
    var hasNext: Bool { get }
    var isLast: Bool { get }
    // TODO: (https://github.com/ably-labs/ably-chat-swift/issues/11): consider how to avoid the need for an unwrap
    var next: (any PaginatedResult<T>)? { get async throws }
    var first: any PaginatedResult<T> { get async throws }
    var current: any PaginatedResult<T> { get async throws }
}

/// Used internally to reduce the amount of duplicate code when interacting with `ARTHTTPPaginatedCallback`'s. The wrapper takes in the callback result from the caller e.g. `realtime.request` and either throws the appropriate error, or decodes and returns the response.
internal struct ARTHTTPPaginatedCallbackWrapper<Response: Codable & Sendable> {
    internal let callbackResult: (ARTHTTPPaginatedResponse?, ARTErrorInfo?)

    internal func handleResponse(continuation: CheckedContinuation<PaginatedResultWrapper<Response>, any Error>) {
        let (paginatedResponse, error) = callbackResult

        // (CHA-M5i) If the REST API returns an error, then the method must throw its ErrorInfo representation.
        // (CHA-M6b) If the REST API returns an error, then the method must throw its ErrorInfo representation.
        if let error {
            continuation.resume(throwing: ARTErrorInfo.create(from: error))
            return
        }

        guard let paginatedResponse, paginatedResponse.statusCode == 200 else {
            continuation.resume(throwing: PaginatedResultError.noErrorWithInvalidResponse)
            return
        }

        do {
            let decodedResponse = try DictionaryDecoder().decode([Response].self, from: paginatedResponse.items)
            let result = paginatedResponse.toPaginatedResult(items: decodedResponse)
            continuation.resume(returning: result)
        } catch {
            continuation.resume(throwing: error)
        }
    }

    internal enum PaginatedResultError: Error {
        case noErrorWithInvalidResponse
    }
}

/// `PaginatedResult` protocol implementation allowing access to the underlying items from a lower level paginated response object e.g. `ARTHTTPPaginatedResponse`, whilst succinctly handling errors through the use of `ARTHTTPPaginatedCallbackWrapper`.
internal final class PaginatedResultWrapper<T: Codable & Sendable>: PaginatedResult {
    internal let items: [T]
    internal let hasNext: Bool
    internal let isLast: Bool
    internal let paginatedResponse: ARTHTTPPaginatedResponse

    internal init(paginatedResponse: ARTHTTPPaginatedResponse, items: [T]) {
        self.items = items
        hasNext = paginatedResponse.hasNext
        isLast = paginatedResponse.isLast
        self.paginatedResponse = paginatedResponse
    }

    /// Asynchronously fetch the next page if available
    internal var next: (any PaginatedResult<T>)? {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                paginatedResponse.next { paginatedResponse, error in
                    ARTHTTPPaginatedCallbackWrapper(callbackResult: (paginatedResponse, error)).handleResponse(continuation: continuation)
                }
            }
        }
    }

    /// Asynchronously fetch the first page
    internal var first: any PaginatedResult<T> {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                paginatedResponse.first { paginatedResponse, error in
                    ARTHTTPPaginatedCallbackWrapper(callbackResult: (paginatedResponse, error)).handleResponse(continuation: continuation)
                }
            }
        }
    }

    /// Asynchronously fetch the current page
    internal var current: any PaginatedResult<T> {
        self
    }
}

private extension ARTHTTPPaginatedResponse {
    /// Converts an `ARTHTTPPaginatedResponse` to a `PaginatedResultWrapper` allowing for access to operations as per conformance to `PaginatedResult`.
    func toPaginatedResult<T: Codable & Sendable>(items: [T]) -> PaginatedResultWrapper<T> {
        PaginatedResultWrapper(paginatedResponse: self, items: items)
    }
}
