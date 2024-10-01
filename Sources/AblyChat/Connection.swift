import Ably

public protocol Connection: AnyObject, Sendable {
    var lifecycle: any ConnectionLifecycle { get }
}

public protocol ConnectionLifecycle: AnyObject, Sendable {
    var status: ConnectionStatus { get }
    // TODO: (https://github.com/ably-labs/ably-chat-swift/issues/12): consider how to avoid the need for an unwrap
    var error: ARTErrorInfo? { get }
    func onChange(bufferingPolicy: BufferingPolicy) -> Subscription<ConnectionStatusChange>
}

public enum ConnectionStatus: Sendable {
    case initialized
    case connecting
    case connected
    case disconnected
    case suspended
    case failed
}

public struct ConnectionStatusChange: Sendable {
    public var current: ConnectionStatus
    public var previous: ConnectionStatus
    // TODO: (https://github.com/ably-labs/ably-chat-swift/issues/12): consider how to avoid the need for an unwrap
    public var error: ARTErrorInfo?
    public var retryIn: TimeInterval

    public init(current: ConnectionStatus, previous: ConnectionStatus, error: ARTErrorInfo? = nil, retryIn: TimeInterval) {
        self.current = current
        self.previous = previous
        self.error = error
        self.retryIn = retryIn
    }
}
