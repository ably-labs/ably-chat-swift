import Ably
import AblyChat

final class MockChannels: RealtimeChannelsProtocol, Sendable {
    private let channels: [MockRealtimeChannel]

    init(channels: [MockRealtimeChannel]) {
        self.channels = channels
    }

    func get(_ name: String) -> MockRealtimeChannel {
        guard let channel = (channels.first { $0.name == name }) else {
            fatalError("There is no mock channel with name \(name)")
        }

        return channel
    }

    func get(_ name: String, options _: ARTRealtimeChannelOptions) -> MockRealtimeChannel {
        get(name)
    }

    func exists(_: String) -> Bool {
        fatalError("Not implemented")
    }

    func release(_: String, callback _: ARTCallback? = nil) {
        fatalError("Not implemented")
    }

    func release(_: String) {
        fatalError("Not implemented")
    }
}
