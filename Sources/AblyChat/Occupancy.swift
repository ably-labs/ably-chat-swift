import Ably

public protocol Occupancy: AnyObject, Sendable, EmitsDiscontinuities {
    func subscribe(bufferingPolicy: BufferingPolicy) async -> Subscription<OccupancyEvent>
    func get() async throws -> OccupancyEvent
    var channel: RealtimeChannelProtocol { get }
}

public struct OccupancyEvent: Sendable, Encodable, Decodable {
    public var connections: Int
    public var presenceMembers: Int

    public init(connections: Int, presenceMembers: Int) {
        self.connections = connections
        self.presenceMembers = presenceMembers
    }
}
