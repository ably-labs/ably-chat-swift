import Ably

public protocol RoomStatus: AnyObject, Sendable {
    var current: RoomLifecycle { get async }
    func onChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange>
}

public enum RoomLifecycle: Sendable, Equatable {
    case initialized
    case attaching(error: ARTErrorInfo?)
    case attached
    case detaching
    case detached
    case suspended(error: ARTErrorInfo)
    case failed(error: ARTErrorInfo)
    case releasing
    case released

    // Helpers to allow us to test whether a `RoomLifecycle` value has a certain case, without caring about the associated value. These are useful for in contexts where we want to use a `Bool` to communicate a case. For example:
    //
    // 1. testing (e.g.  `#expect(status.isFailed)`)
    // 2. testing that a status does _not_ have a particular case (e.g. if !status.isFailed), which a `case` statement cannot succinctly express

    public var isAttaching: Bool {
        if case .attaching = self {
            true
        } else {
            false
        }
    }

    public var isSuspended: Bool {
        if case .suspended = self {
            true
        } else {
            false
        }
    }

    public var isFailed: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}

public struct RoomStatusChange: Sendable {
    public var current: RoomLifecycle
    public var previous: RoomLifecycle

    public init(current: RoomLifecycle, previous: RoomLifecycle) {
        self.current = current
        self.previous = previous
    }
}

internal actor DefaultRoomStatus: RoomStatus {
    internal private(set) var current: RoomLifecycle = .initialized
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

    /// Sets ``current`` to the given state, and emits a status change to all subscribers added via ``onChange(bufferingPolicy:)``.
    internal func transition(to newState: RoomLifecycle) {
        logger.log(message: "Transitioning to \(newState)", level: .debug)
        let statusChange = RoomStatusChange(current: newState, previous: current)
        current = newState
        for subscription in subscriptions {
            subscription.emit(statusChange)
        }
    }
}
