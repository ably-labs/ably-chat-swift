import Ably
@testable import AblyChat

final actor MockRoomLifecycleContributorChannel: RoomLifecycleContributorChannel {
    private let attachBehavior: AttachOrDetachBehavior?
    private let detachBehavior: AttachOrDetachBehavior?
    private let subscribeToStateBehavior: SubscribeToStateBehavior

    var state: ARTRealtimeChannelState
    var errorReason: ARTErrorInfo?
    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var subscriptions = SubscriptionStorage<ARTChannelStateChange>()

    private(set) var attachCallCount = 0
    private(set) var detachCallCount = 0

    init(
        initialState: ARTRealtimeChannelState,
        initialErrorReason: ARTErrorInfo?,
        attachBehavior: AttachOrDetachBehavior?,
        detachBehavior: AttachOrDetachBehavior?,
        subscribeToStateBehavior: SubscribeToStateBehavior?
    ) {
        state = initialState
        errorReason = initialErrorReason
        self.attachBehavior = attachBehavior
        self.detachBehavior = detachBehavior
        self.subscribeToStateBehavior = subscribeToStateBehavior ?? .justAddSubscription
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

    enum AttachOrDetachBehavior {
        /// Receives an argument indicating how many times (including the current call) the method for which this is providing a mock implementation has been called.
        case fromFunction(@Sendable (Int) async -> AttachOrDetachBehavior)
        case complete(AttachOrDetachResult)
        case completeAndChangeState(AttachOrDetachResult, newState: ARTRealtimeChannelState)

        static var success: Self {
            .complete(.success)
        }

        static func failure(_ error: ARTErrorInfo) -> Self {
            .complete(.failure(error))
        }
    }

    enum SubscribeToStateBehavior {
        case justAddSubscription
        case addSubscriptionAndEmitStateChange(ARTChannelStateChange)
    }

    func attach() async throws(ARTErrorInfo) {
        attachCallCount += 1

        guard let attachBehavior else {
            fatalError("attachBehavior must be set before attach is called")
        }

        try await performBehavior(attachBehavior, callCount: attachCallCount)
    }

    func detach() async throws(ARTErrorInfo) {
        detachCallCount += 1

        guard let detachBehavior else {
            fatalError("detachBehavior must be set before detach is called")
        }

        try await performBehavior(detachBehavior, callCount: detachCallCount)
    }

    private func performBehavior(_ behavior: AttachOrDetachBehavior, callCount: Int) async throws(ARTErrorInfo) {
        let result: AttachOrDetachResult
        switch behavior {
        case let .fromFunction(function):
            let behavior = await function(callCount)
            try await performBehavior(behavior, callCount: callCount)
            return
        case let .complete(completeResult):
            result = completeResult
        case let .completeAndChangeState(completeResult, newState):
            state = newState
            if case let .failure(error) = completeResult {
                errorReason = error
            }
            result = completeResult
        }

        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    func subscribeToState() -> Subscription<ARTChannelStateChange> {
        let subscription = subscriptions.create(bufferingPolicy: .unbounded)

        switch subscribeToStateBehavior {
        case .justAddSubscription:
            break
        case let .addSubscriptionAndEmitStateChange(stateChange):
            emitStateChange(stateChange)
        }

        return subscription
    }

    func emitStateChange(_ stateChange: ARTChannelStateChange) {
        subscriptions.emit(stateChange)
    }
}
