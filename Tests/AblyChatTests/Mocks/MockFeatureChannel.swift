import Ably
@testable import AblyChat

final actor MockFeatureChannel: FeatureChannel {
    let channel: RealtimeChannelProtocol
    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var discontinuitySubscriptions = SubscriptionStorage<DiscontinuityEvent>()
    private let resultOfWaitToBeAbleToPerformPresenceOperations: Result<Void, ARTErrorInfo>?

    init(
        channel: RealtimeChannelProtocol,
        resultOfWaitToBeAblePerformPresenceOperations: Result<Void, ARTErrorInfo>? = nil
    ) {
        self.channel = channel
        resultOfWaitToBeAbleToPerformPresenceOperations = resultOfWaitToBeAblePerformPresenceOperations
    }

    func onDiscontinuity(bufferingPolicy: BufferingPolicy) async -> Subscription<DiscontinuityEvent> {
        return discontinuitySubscriptions.create(bufferingPolicy: bufferingPolicy)
    }

    func emitDiscontinuity(_ discontinuity: DiscontinuityEvent) {
        discontinuitySubscriptions.emit(discontinuity)
    }

    func waitToBeAbleToPerformPresenceOperations(requestedByFeature _: RoomFeature) async throws(ARTErrorInfo) {
        guard let resultOfWaitToBeAbleToPerformPresenceOperations else {
            fatalError("resultOfWaitToBeAblePerformPresenceOperations must be set before waitToBeAbleToPerformPresenceOperations is called")
        }

        try resultOfWaitToBeAbleToPerformPresenceOperations.get()
    }
}
