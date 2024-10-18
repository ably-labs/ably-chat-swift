import Ably

public protocol RoomReactions: AnyObject, Sendable, EmitsDiscontinuities {
    func send(params: SendReactionParams) async throws
    var channel: RealtimeChannelProtocol { get }
    func subscribe(bufferingPolicy: BufferingPolicy) async -> Subscription<Reaction>
}

public struct SendReactionParams: Sendable {
    public var type: String
    public var metadata: ReactionMetadata?
    public var headers: ReactionHeaders?

    public init(type: String, metadata: ReactionMetadata? = nil, headers: ReactionHeaders? = nil) {
        self.type = type
        self.metadata = metadata
        self.headers = headers
    }
}

internal extension SendReactionParams {
    // Same as `ARTDataQuery.asQueryItems` from ably-cocoa.
    func asQueryItems() -> [String: String] {
        var dict: [String: String] = [:]
        dict["type"] = "\(type)"
        dict["metadata"] = "\(metadata ?? [:])"
        return dict
    }
}
