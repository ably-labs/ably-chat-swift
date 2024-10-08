import Ably
import AblyChat

// swiftlint:disable:next line_length
/// A mock implementation of `RealtimeClientProtocol`. It only exists so that we can construct an instance of `DefaultChatClient` without needing to create a proper `ARTRealtime` instance (which we can’t yet do because we don’t have a method for inserting an API key into the example app). TODO remove this once we start building the example app
final class MockRealtime: NSObject, RealtimeClientProtocol, Sendable {
    func request(_: String, path _: String, params _: [String: String]?, body _: Any?, headers _: [String: String]?, callback _: @escaping ARTHTTPPaginatedCallback) throws {
        fatalError("not implemented")
    }

    var device: ARTLocalDevice {
        fatalError("Not implemented")
    }

    var clientId: String? {
        fatalError("Not implemented")
    }

    let channels = Channels()

    final class Channels: RealtimeChannelsProtocol {
        func get(_: String, options _: ARTRealtimeChannelOptions) -> MockRealtime.Channel {
            fatalError("Not implemented")
        }

        func get(_: String) -> Channel {
            fatalError("Not implemented")
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

    final class Channel: RealtimeChannelProtocol {
        var properties: ARTChannelProperties { .init() }

        init() {}

        var state: ARTRealtimeChannelState {
            fatalError("Not implemented")
        }

        var errorReason: ARTErrorInfo? {
            fatalError("Not implemented")
        }

        var options: ARTRealtimeChannelOptions? {
            fatalError("Not implemented")
        }

        func attach() {
            fatalError("Not implemented")
        }

        func attach(_: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func detach() {
            fatalError("Not implemented")
        }

        func detach(_: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func subscribe(_: @escaping ARTMessageCallback) -> ARTEventListener? {
            fatalError("Not implemented")
        }

        func subscribe(attachCallback _: ARTCallback?, callback _: @escaping ARTMessageCallback) -> ARTEventListener? {
            fatalError("Not implemented")
        }

        func subscribe(_: String, callback _: @escaping ARTMessageCallback) -> ARTEventListener? {
            fatalError("Not implemented")
        }

        func subscribe(_: String, onAttach _: ARTCallback?, callback _: @escaping ARTMessageCallback) -> ARTEventListener? {
            fatalError("Not implemented")
        }

        func unsubscribe() {
            fatalError("Not implemented")
        }

        func unsubscribe(_: ARTEventListener?) {
            fatalError("Not implemented")
        }

        func unsubscribe(_: String, listener _: ARTEventListener?) {
            fatalError("Not implemented")
        }

        func history(_: ARTRealtimeHistoryQuery?, callback _: @escaping ARTPaginatedMessagesCallback) throws {
            fatalError("Not implemented")
        }

        func setOptions(_: ARTRealtimeChannelOptions?, callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func on(_: ARTChannelEvent, callback _: @escaping (ARTChannelStateChange) -> Void) -> ARTEventListener {
            fatalError("Not implemented")
        }

        func on(_: @escaping (ARTChannelStateChange) -> Void) -> ARTEventListener {
            fatalError("Not implemented")
        }

        func once(_: ARTChannelEvent, callback _: @escaping (ARTChannelStateChange) -> Void) -> ARTEventListener {
            fatalError("Not implemented")
        }

        func once(_: @escaping (ARTChannelStateChange) -> Void) -> ARTEventListener {
            fatalError("Not implemented")
        }

        func off(_: ARTChannelEvent, listener _: ARTEventListener) {
            fatalError("Not implemented")
        }

        func off(_: ARTEventListener) {
            fatalError("Not implemented")
        }

        func off() {
            fatalError("Not implemented")
        }

        var name: String {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, clientId _: String) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, clientId _: String, callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, extras _: (any ARTJsonCompatible)?) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, extras _: (any ARTJsonCompatible)?, callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, clientId _: String, extras _: (any ARTJsonCompatible)?) {
            fatalError("Not implemented")
        }

        func publish(_: String?, data _: Any?, clientId _: String, extras _: (any ARTJsonCompatible)?, callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func publish(_: [ARTMessage]) {
            fatalError("Not implemented")
        }

        func publish(_: [ARTMessage], callback _: ARTCallback? = nil) {
            fatalError("Not implemented")
        }

        func history(_: @escaping ARTPaginatedMessagesCallback) {
            fatalError("Not implemented")
        }
    }

    required init(options _: ARTClientOptions) {}

    required init(key _: String) {}

    required init(token _: String) {}

    /**
     Creates an instance of MockRealtime.

     This exists to give a convenient way to create an instance, because `init` is marked as unavailable in `ARTRealtimeProtocol`.
     */
    static func create() -> MockRealtime {
        MockRealtime(key: "")
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
}
