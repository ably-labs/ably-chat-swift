import Ably

// Typealias for the timeserial used to sync message subscriptions with. This is a string representation of a timestamp.
private typealias TimeserialString = String

// Wraps the MessageSubscription with the timeserial of when the subscription was attached or resumed.
private struct MessageSubscriptionWrapper {
    let subscription: MessageSubscription
    var timeserial: TimeserialString
}

// TODO: Don't have a strong understanding of why @MainActor is needed here. Revisit as part of https://github.com/ably-labs/ably-chat-swift/issues/83
@MainActor
internal final class DefaultMessages: Messages, EmitsDiscontinuities {
    private let roomID: String
    public let channel: RealtimeChannelProtocol
    private let chatAPI: ChatAPI
    private let clientID: String

    // TODO: https://github.com/ably-labs/ably-chat-swift/issues/36 - Handle unsubscribing in line with CHA-M4b
    // UUID acts as a unique identifier for each listener/subscription. MessageSubscriptionWrapper houses the subscription and the timeserial of when it was attached or resumed.
    private var subscriptionPoints: [UUID: MessageSubscriptionWrapper] = [:]

    internal nonisolated init(chatAPI: ChatAPI, roomID: String, clientID: String) async {
        self.chatAPI = chatAPI
        self.roomID = roomID
        self.clientID = clientID

        // (CHA-M1) Chat messages for a Room are sent on a corresponding realtime channel <roomId>::$chat::$chatMessages. For example, if your room id is my-room then the messages channel will be my-room::$chat::$chatMessages.
        let messagesChannelName = "\(roomID)::$chat::$chatMessages"
        channel = chatAPI.getChannel(messagesChannelName)

        // Implicitly handles channel events and therefore listners within this class. Alternative is to explicitly call something like `DefaultMessages.start()` which makes the SDK more cumbersome to interact with. This class is useless without kicking off this flow so I think leaving it here is suitable.
        // "Calls to instance method 'handleChannelEvents(roomId:)' from outside of its actor context are implicitly asynchronous" hence the `await` here.
        await handleChannelEvents(roomId: roomID)
    }

    // (CHA-M4) Messages can be received via a subscription in realtime.
    internal func subscribe(bufferingPolicy: BufferingPolicy) async throws -> MessageSubscription {
        let uuid = UUID()
        let timeserial = try await resolveSubscriptionStart()
        let messageSubscription = MessageSubscription(
            bufferingPolicy: bufferingPolicy
        ) { [weak self] queryOptions in
            guard let self else { throw MessagesError.noReferenceToSelf }
            return try await getBeforeSubscriptionStart(uuid, params: queryOptions)
        }

        // (CHA-M4a) A subscription can be registered to receive incoming messages. Adding a subscription has no side effects on the status of the room or the underlying realtime channel.
        subscriptionPoints[uuid] = .init(subscription: messageSubscription, timeserial: timeserial)

        // (CHA-M4c) When a realtime message with name set to message.created is received, it is translated into a message event, which contains a type field with the event type as well as a message field containing the Message Struct. This event is then broadcast to all subscribers.
        // (CHA-M4d) If a realtime message with an unknown name is received, the SDK shall silently discard the message, though it may log at DEBUG or TRACE level.
        // (CHA-M5d) Incoming realtime events that are malformed (unknown field should be ignored) shall not be emitted to subscribers.
        channel.subscribe(MessageEvent.created.rawValue) { message in
            Task {
                // TODO: Revisit errors thrown as part of https://github.com/ably-labs/ably-chat-swift/issues/32
                guard let data = message.data as? [String: Any],
                      let text = data["text"] as? String
                else {
                    throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without data or text")
                }

                guard let extras = try message.extras?.toJSON() else {
                    throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without extras")
                }

                guard let timeserial = extras["timeserial"] as? String else {
                    throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without timeserial")
                }

                guard let clientID = message.clientId else {
                    throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without clientId")
                }

                let metadata = data["metadata"] as? Metadata
                let headers = extras["headers"] as? Headers

                let message = Message(
                    timeserial: timeserial,
                    clientID: clientID,
                    roomID: self.roomID,
                    text: text,
                    createdAt: message.timestamp,
                    metadata: metadata ?? .init(),
                    headers: headers ?? .init()
                )

                messageSubscription.emit(message)
            }
        }

        return messageSubscription
    }

    // (CHA-M6a) A method must be exposed that accepts the standard Ably REST API query parameters. It shall call the “REST API”#rest-fetching-messages and return a PaginatedResult containing messages, which can then be paginated through.
    internal func get(options: QueryOptions) async throws -> any PaginatedResult<Message> {
        try await chatAPI.getMessages(roomId: roomID, params: options)
    }

    internal func send(params: SendMessageParams) async throws -> Message {
        try await chatAPI.sendMessage(roomId: roomID, params: params)
    }

    // TODO: (CHA-M7) Users may subscribe to discontinuity events to know when there’s been a break in messages that they need to resolve. Their listener will be called when a discontinuity event is triggered from the room lifecycle. - https://github.com/ably-labs/ably-chat-swift/issues/47
    internal nonisolated func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("not implemented")
    }

    private func getBeforeSubscriptionStart(_ uuid: UUID, params: QueryOptions) async throws -> any PaginatedResult<Message> {
        guard let subscriptionPoint = subscriptionPoints[uuid]?.timeserial else {
            throw ARTErrorInfo.create(
                withCode: 40000,
                status: 400,
                message: "cannot query history; listener has not been subscribed yet"
            )
        }

        // (CHA-M5j) If the end parameter is specified and is more recent than the subscription point timeserial, the method must throw an ErrorInfo with code 40000.
        let parseSerial = try? DefaultTimeserial.calculateTimeserial(from: subscriptionPoint)
        if let end = params.end, dateToMilliseconds(end) > parseSerial?.timestamp ?? 0 {
            throw ARTErrorInfo.create(
                withCode: 40000,
                status: 400,
                message: "cannot query history; end time is after the subscription point of the listener"
            )
        }

        // (CHA-M5f) This method must accept any of the standard history query options, except for direction, which must always be backwards.
        var queryOptions = params
        queryOptions.orderBy = .newestFirst // newestFirst is equivalent to backwards

        // (CHA-M5g) The subscribers subscription point must be additionally specified (internally, by us) in the fromSerial query parameter.
        queryOptions.fromSerial = subscriptionPoint

        return try await chatAPI.getMessages(roomId: roomID, params: queryOptions)
    }

    private func handleChannelEvents(roomId _: String) {
        // (CHA-M5c) If a channel leaves the ATTACHED state and then re-enters ATTACHED with resumed=false, then it must be assumed that messages have been missed. The subscription point of any subscribers must be reset to the attachSerial.
        channel.on(.attached) { [weak self] stateChange in
            Task {
                do {
                    try await self?.handleAttach(fromResume: stateChange.resumed)
                } catch {
                    throw ARTErrorInfo.create(from: error)
                }
            }
        }

        // (CHA-M4d) If a channel UPDATE event is received and resumed=false, then it must be assumed that messages have been missed. The subscription point of any subscribers must be reset to the attachSerial.
        channel.on(.update) { [weak self] stateChange in
            Task {
                do {
                    try await self?.handleAttach(fromResume: stateChange.resumed)
                } catch {
                    throw ARTErrorInfo.create(from: error)
                }
            }
        }
    }

    private func handleAttach(fromResume: Bool) async throws {
        // Do nothing if we have resumed as there is no discontinuity in the message stream
        if fromResume {
            return
        }

        do {
            let timeserialOnChannelAttach = try await timeserialOnChannelAttach()

            for uuid in subscriptionPoints.keys {
                subscriptionPoints[uuid]?.timeserial = timeserialOnChannelAttach
            }
        } catch {
            throw ARTErrorInfo.create(from: error)
        }
    }

    private func resolveSubscriptionStart() async throws -> TimeserialString {
        // (CHA-M5a) If a subscription is added when the underlying realtime channel is ATTACHED, then the subscription point is the current channelSerial of the realtime channel.
        if channel.state == .attached {
            if let channelSerial = channel.properties.channelSerial {
                return channelSerial
            } else {
                throw ARTErrorInfo.create(withCode: 40000, status: 400, message: "channel is attached, but channelSerial is not defined")
            }
        }

        // (CHA-M5b) If a subscription is added when the underlying realtime channel is in any other state, then its subscription point becomes the attachSerial at the the point of channel attachment.
        return try await timeserialOnChannelAttach()
    }

    // Always returns the attachSerial and not the channelSerial to also serve (CHA-M5c) - If a channel leaves the ATTACHED state and then re-enters ATTACHED with resumed=false, then it must be assumed that messages have been missed. The subscription point of any subscribers must be reset to the attachSerial.
    private func timeserialOnChannelAttach() async throws -> TimeserialString {
        // If the state is already 'attached', return the attachSerial immediately
        if channel.state == .attached {
            if let attachSerial = channel.properties.attachSerial {
                return attachSerial
            } else {
                throw ARTErrorInfo.create(withCode: 40000, status: 400, message: "Channel is attached, but attachSerial is not defined")
            }
        }

        // (CHA-M5b) If a subscription is added when the underlying realtime channel is in any other state, then its subscription point becomes the attachSerial at the the point of channel attachment.
        return try await withCheckedThrowingContinuation { continuation in
            channel.on { [weak self] stateChange in
                guard let self else {
                    return
                }
                switch stateChange.current {
                case .attached:
                    // Handle successful attachment
                    if let attachSerial = channel.properties.attachSerial {
                        continuation.resume(returning: attachSerial)
                    } else {
                        continuation.resume(throwing: ARTErrorInfo.create(withCode: 40000, status: 400, message: "Channel is attached, but attachSerial is not defined"))
                    }
                case .failed, .suspended:
                    // TODO: Revisit as part of https://github.com/ably-labs/ably-chat-swift/issues/32
                    continuation.resume(
                        throwing: ARTErrorInfo.create(
                            withCode: ErrorCode.messagesAttachmentFailed.rawValue,
                            status: ErrorCode.messagesAttachmentFailed.statusCode,
                            message: "Channel failed to attach"
                        )
                    )
                default:
                    break
                }
            }
        }
    }

    internal enum MessagesError: Error {
        case noReferenceToSelf
    }
}
