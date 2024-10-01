import Ably

public protocol RoomLifecycle: AnyObject, Sendable {
    var status: RoomStatus { get async }
    // TODO: (https://github.com/ably-labs/ably-chat-swift/issues/12): consider how to avoid the need for an unwrap
    var error: ARTErrorInfo? { get async }
    func onChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange>
}

public enum RoomStatus: Sendable {
    case initialized
    case attaching
    case attached
    case detaching
    case detached
    case suspended
    case failed
    case releasing
    case released
}

public struct RoomStatusChange: Sendable {
    public var current: RoomStatus
    public var previous: RoomStatus
    // TODO: (https://github.com/ably-labs/ably-chat-swift/issues/12): consider how to avoid the need for an unwrap
    public var error: ARTErrorInfo?

    public init(current: RoomStatus, previous: RoomStatus, error: ARTErrorInfo? = nil) {
        self.current = current
        self.previous = previous
        self.error = error
    }
}

internal actor DefaultRoomLifecycle: RoomLifecycle {
    internal private(set) var status: RoomStatus = .initialized
    // TODO: populate this (https://github.com/ably-labs/ably-chat-swift/issues/28)
    internal private(set) var error: ARTErrorInfo?

    private let logger: InternalLogger

    internal init(logger: InternalLogger) {
        self.logger = logger
    }

    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var subscriptions: [Subscription<RoomStatusChange>] = []

    internal func onChange(bufferingPolicy: BufferingPolicy) -> Subscription<RoomStatusChange> {
        let subscription: Subscription<RoomStatusChange> = .init(bufferingPolicy: bufferingPolicy)
        subscriptions.append(subscription)
        return subscription
    }

    /// Sets ``status`` to the given status, and emits a status change to all subscribers added via ``onChange(bufferingPolicy:)``.
    internal func transition(to newStatus: RoomStatus) {
        logger.log(message: "Transitioning to \(newStatus)", level: .debug)
        let statusChange = RoomStatusChange(current: newStatus, previous: status)
        status = newStatus
        for subscription in subscriptions {
            subscription.emit(statusChange)
        }
    }
}
