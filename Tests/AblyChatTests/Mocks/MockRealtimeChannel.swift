import Ably
import AblyChat

final class MockRealtimeChannel: NSObject, RealtimeChannelProtocol {
    private let attachSerial: String?
    private let channelSerial: String?
    private let _name: String?

    var properties: ARTChannelProperties { .init(attachSerial: attachSerial, channelSerial: channelSerial) }

    // I don't see why the nonisolated(unsafe) keyword would cause a problem when used for tests in this context.
    nonisolated(unsafe) var lastMessagePublishedName: String?
    nonisolated(unsafe) var lastMessagePublishedData: Any?
    nonisolated(unsafe) var lastMessagePublishedExtras: (any ARTJsonCompatible)?

    init(
        name: String? = nil,
        properties: ARTChannelProperties = .init(),
        state _: ARTRealtimeChannelState = .suspended,
        attachResult: AttachOrDetachResult? = nil,
        detachResult: AttachOrDetachResult? = nil
    ) {
        _name = name
        self.attachResult = attachResult
        self.detachResult = detachResult
        attachSerial = properties.attachSerial
        channelSerial = properties.channelSerial
    }

    /// A threadsafe counter that starts at zero.
    class Counter: @unchecked Sendable {
        private var mutex = NSLock()
        private var _value = 0

        var value: Int {
            let value: Int
            mutex.lock()
            value = _value
            mutex.unlock()
            return value
        }

        func increment() {
            mutex.lock()
            _value += 1
            mutex.unlock()
        }

        var isZero: Bool {
            value == 0
        }

        var isNonZero: Bool {
            value > 0
        }
    }

    var state: ARTRealtimeChannelState {
        .attached
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

    enum AttachOrDetachResult {
        case success
        case failure(ARTErrorInfo)

        func performCallback(_ callback: ARTCallback?) {
            switch self {
            case .success:
                callback?(nil)
            case let .failure(error):
                callback?(error)
            }
        }
    }

    private let attachResult: AttachOrDetachResult?

    let attachCallCounter = Counter()

    func attach(_ callback: ARTCallback? = nil) {
        attachCallCounter.increment()

        guard let attachResult else {
            fatalError("attachResult must be set before attach is called")
        }

        attachResult.performCallback(callback)
    }

    private let detachResult: AttachOrDetachResult?

    let detachCallCounter = Counter()

    func detach() {
        fatalError("Not implemented")
    }

    func detach(_ callback: ARTCallback? = nil) {
        detachCallCounter.increment()

        guard let detachResult else {
            fatalError("detachResult must be set before detach is called")
        }

        detachResult.performCallback(callback)
    }

    func subscribe(_: @escaping ARTMessageCallback) -> ARTEventListener? {
        fatalError("Not implemented")
    }

    func subscribe(attachCallback _: ARTCallback?, callback _: @escaping ARTMessageCallback) -> ARTEventListener? {
        fatalError("Not implemented")
    }

    func subscribe(_: String, callback _: @escaping ARTMessageCallback) -> ARTEventListener? {
        ARTEventListener()
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
        ARTEventListener()
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
        guard let name = _name else {
            fatalError("Channel name not set")
        }
        return name
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

    func publish(_ name: String?, data: Any?, extras: (any ARTJsonCompatible)?) {
        lastMessagePublishedName = name
        lastMessagePublishedExtras = extras
        lastMessagePublishedData = data
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
