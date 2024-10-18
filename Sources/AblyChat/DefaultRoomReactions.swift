import Ably

// TODO: This class errors with "Task-isolated value of type '() async throws -> ()' passed as a strongly transferred parameter; later accesses could race". Adding @MainActor fixes this, revisit as part of https://github.com/ably-labs/ably-chat-swift/issues/83
@MainActor
internal final class DefaultRoomReactions: RoomReactions, EmitsDiscontinuities {
    private let roomID: String
    public let channel: RealtimeChannelProtocol
    private let realtime: any RealtimeClientProtocol
    private let logger: InternalLogger

    internal init(realtime: any RealtimeClientProtocol, roomID: String, logger: InternalLogger) {
        self.roomID = roomID
        self.realtime = realtime
        self.logger = logger

        // (CHA-ER1) Reactions for a Room are sent on a corresponding realtime channel <roomId>::$chat::$reactions. For example, if your room id is my-room then the reactions channel will be my-room::$chat::$reactions.
        let reactionsChannelName = "\(roomID)::$chat::$reactions"
        channel = realtime.getChannel(reactionsChannelName)
    }

    // (CHA-ER3) Ephemeral room reactions are sent to Ably via the Realtime connection via a send method.
    // (CHA-ER3a) Reactions are sent on the channel using a message in a particular format - see spec for format.
    internal func send(params: SendReactionParams) async throws {
        let extras: NSDictionary = ["headers": params.headers ?? [:]]
        channel.publish(RoomReactionEvents.reaction.rawValue, data: params.asQueryItems(), extras: extras)
    }

    // (CHA-ER4) A user may subscribe to reaction events in Realtime.
    // (CHA-ER4a) A user may provide a listener to subscribe to reaction events. This operation must have no side-effects in relation to room or underlying status. When a realtime message with name roomReaction is received, this message is converted into a reaction object and emitted to subscribers.
    internal func subscribe(bufferingPolicy: BufferingPolicy) async -> Subscription<Reaction> {
        let subscription = Subscription<Reaction>(bufferingPolicy: bufferingPolicy)

        // (CHA-ER4c) Realtime events with an unknown name shall be silently discarded.
        channel.subscribe(RoomReactionEvents.reaction.rawValue) { [realtime, logger] message in
            Task {
                do {
                    guard let data = message.data as? [String: Any],
                          let reactionType = data["type"] as? String
                    else {
                        throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without data or text")
                    }

                    guard let clientID = message.clientId else {
                        throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without clientId")
                    }

                    guard let timestamp = message.timestamp else {
                        throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without timestamp")
                    }

                    guard let extras = try message.extras?.toJSON() else {
                        throw ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without extras")
                    }

                    let metadata = data["metadata"] as? Metadata
                    let headers = extras["headers"] as? Headers

                    // (CHA-ER4d) Realtime events that are malformed (unknown fields should be ignored) shall not be emitted to listeners.
                    let reaction = Reaction(
                        type: reactionType,
                        metadata: metadata ?? .init(),
                        headers: headers ?? .init(),
                        createdAt: timestamp,
                        clientID: clientID,
                        isSelf: message.clientId == realtime.clientId
                    )

                    subscription.emit(reaction)
                } catch {
                    logger.log(message: "Error processing incoming reaction message: \(error)", level: .error)
                }
            }
        }

        return subscription
    }

    // TODO: (CHA-ER5) Users may subscribe to discontinuity events to know when there’s been a break in reactions that they need to resolve. Their listener will be called when a discontinuity event is triggered from the room lifecycle. https://github.com/ably-labs/ably-chat-swift/issues/47
    internal func subscribeToDiscontinuities() async -> Subscription<ARTErrorInfo> {
        fatalError("Not implemented")
    }

    private enum RoomReactionsError: Error {
        case noReferenceToSelf
    }
}
