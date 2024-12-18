import Ably
@testable import AblyChat

actor MockRoomLifecycleManager: RoomLifecycleManager {
    private let attachResult: Result<Void, ARTErrorInfo>?
    private(set) var attachCallCount = 0
    private let detachResult: Result<Void, ARTErrorInfo>?
    private(set) var detachCallCount = 0
    private(set) var releaseCallCount = 0
    private let _roomStatus: RoomStatus?
    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var subscriptions = SubscriptionStorage<RoomStatusChange>()

    init(attachResult: Result<Void, ARTErrorInfo>? = nil, detachResult: Result<Void, ARTErrorInfo>? = nil, roomStatus: RoomStatus? = nil) {
        self.attachResult = attachResult
        self.detachResult = detachResult
        _roomStatus = roomStatus
    }

    func performAttachOperation() async throws {
        attachCallCount += 1
        guard let attachResult else {
            fatalError("In order to call performAttachOperation, attachResult must be passed to the initializer")
        }
        try attachResult.get()
    }

    func performDetachOperation() async throws {
        detachCallCount += 1
        guard let detachResult else {
            fatalError("In order to call performDetachOperation, detachResult must be passed to the initializer")
        }
        try detachResult.get()
    }

    func performReleaseOperation() async {
        releaseCallCount += 1
    }

    var roomStatus: RoomStatus {
        guard let roomStatus = _roomStatus else {
            fatalError("In order to call roomStatus, roomStatus must be passed to the initializer")
        }
        return roomStatus
    }

    func onRoomStatusChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange> {
        return subscriptions.create(bufferingPolicy: bufferingPolicy)
    }

    func emitStatusChange(_ statusChange: RoomStatusChange) {
        subscriptions.emit(statusChange)
    }

    func waitToBeAbleToPerformPresenceOperations(requestedByFeature _: RoomFeature) async throws(ARTErrorInfo) {
        fatalError("Not implemented")
    }
}
