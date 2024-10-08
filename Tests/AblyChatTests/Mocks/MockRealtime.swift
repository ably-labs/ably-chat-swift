import Ably
import AblyChat
import Foundation

/// A mock implementation of `ARTRealtimeProtocol`. We’ll figure out how to do mocking in tests properly in https://github.com/ably-labs/ably-chat-swift/issues/5.
final class MockRealtime: NSObject, RealtimeClientProtocol, Sendable {
    var device: ARTLocalDevice {
        fatalError("Not implemented")
    }

    var clientId: String? {
        "mockClientId"
    }

    required init(options _: ARTClientOptions) {
        channels = .init(channels: [])
    }

    required init(key _: String) {
        channels = .init(channels: [])
    }

    required init(token _: String) {
        channels = .init(channels: [])
    }

    init(channels: MockChannels = .init(channels: [])) {
        self.channels = channels
    }

    let channels: MockChannels

    /**
     Creates an instance of MockRealtime.

     This exists to give a convenient way to create an instance, because `init` is marked as unavailable in `ARTRealtimeProtocol`.
     */
    static func create(channels: MockChannels = MockChannels(channels: [])) -> MockRealtime {
        MockRealtime(channels: channels)
    }

    func time(_: @escaping ARTDateTimeCallback) {
        fatalError("Not implemented")
    }

    func ping(_: @escaping ARTCallback) {
        fatalError("Not implemented")
    }

    func stats(_: @escaping ARTPaginatedStatsCallback) -> Bool {
        fatalError("Not implemented")
    }

    func stats(_: ARTStatsQuery?, callback _: @escaping ARTPaginatedStatsCallback) throws {
        fatalError("Not implemented")
    }

    func connect() {
        fatalError("Not implemented")
    }

    func close() {
        fatalError("Not implemented")
    }

    func request(_: String, path _: String, params _: [String: String]?, body _: Any?, headers _: [String: String]?, callback _: @escaping ARTHTTPPaginatedCallback) throws {
        fatalError("Not implemented")
    }
}
