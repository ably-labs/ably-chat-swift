import Ably

internal final class DefaultTyping: Typing {
    private let featureChannel: FeatureChannel
    private let roomID: String
    private let clientID: String
    private let logger: InternalLogger
    private let timeout: TimeInterval
    private let timerManager = TimerManager()

    internal init(featureChannel: FeatureChannel, roomID: String, clientID: String, logger: InternalLogger, timeout: TimeInterval) {
        self.roomID = roomID
        self.featureChannel = featureChannel
        self.clientID = clientID
        self.logger = logger
        self.timeout = timeout
    }

    internal nonisolated var channel: any RealtimeChannelProtocol {
        featureChannel.channel
    }

    // (CHA-T6) Users may subscribe to typing events – updates to a set of clientIDs that are typing. This operation, like all subscription operations, has no side-effects in relation to room lifecycle.
    internal func subscribe(bufferingPolicy: BufferingPolicy) async -> Subscription<TypingEvent> {
        let subscription = Subscription<TypingEvent>(bufferingPolicy: bufferingPolicy)
        let eventTracker = EventTracker()

        channel.presence.subscribe { [weak self] message in
            guard let self else {
                return
            }
            logger.log(message: "Received presence message: \(message)", level: .debug)
            Task {
                let currentEventID = await eventTracker.updateEventID()
                let maxRetryDuration: TimeInterval = 30.0 // Max duration as specified in CHA-T6c1
                let baseDelay: TimeInterval = 1.0 // Initial retry delay
                let maxDelay: TimeInterval = 5.0 // Maximum delay between retries

                var totalElapsedTime: TimeInterval = 0
                var delay: TimeInterval = baseDelay

                while totalElapsedTime < maxRetryDuration {
                    do {
                        // (CHA-T6c) When a presence event is received from the realtime client, the Chat client will perform a presence.get() operation to get the current presence set. This guarantees that we get a fully synced presence set. This is then used to emit the typing clients to the subscriber.
                        let latestTypingMembers = try await get()

                        // (CHA-T6c2) If multiple presence events are received resulting in concurrent presence.get() calls, then we guarantee that only the “latest” event is emitted. That is to say, if presence event A and B occur in that order, then only the typing event generated by B’s call to presence.get() will be emitted to typing subscribers.
                        let isLatestEvent = await eventTracker.isLatestEvent(currentEventID)
                        guard isLatestEvent else {
                            logger.log(message: "Discarding outdated presence.get() result.", level: .debug)
                            return
                        }

                        let typingEvent = TypingEvent(currentlyTyping: latestTypingMembers)
                        subscription.emit(typingEvent)
                        logger.log(message: "Successfully emitted typing event: \(typingEvent)", level: .debug)
                        return
                    } catch {
                        // (CHA-T6c1) [Testable] If the presence.get() operation fails, then it shall be retried using a backoff with jitter, up to a timeout of 30 seconds.
                        logger.log(message: "Failed to fetch presence set: \(error). Retrying...", level: .error)
                        // Apply jitter to the delay
                        let jitter = Double.random(in: 0 ... (delay / 2))
                        let backoffDelay = min(delay + jitter, maxDelay)

                        try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                        totalElapsedTime += backoffDelay

                        // Exponential backoff (double the delay)
                        delay = min(delay * 2, maxDelay)
                    }
                }
                logger.log(message: "Failed to fetch presence set after \(maxRetryDuration) seconds. Giving up.", level: .error)
            }
        }
        return subscription
    }

    // (CHA-T2) Users may retrieve a list of the currently typing client IDs. The behaviour depends on the current room status, as presence operations in a Realtime Client cause implicit attaches.
    internal func get() async throws -> Set<String> {
        logger.log(message: "Getting presence", level: .debug)

        // CHA-T2c to CHA-T2f
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence get operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.get { [processPresenceGet] members, error in
                do {
                    let presenceMembers = try processPresenceGet(members, error)
                    continuation.resume(returning: presenceMembers)
                } catch {
                    continuation.resume(throwing: error)
                    // processPresenceGet will log any errors
                }
            }
        }
    }

    // (CHA-T4) Users may indicate that they have started typing.
    internal func start() async throws {
        logger.log(message: "Starting typing indicator for client: \(clientID)", level: .debug)

        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence enter operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let isUserTyping = await timerManager.hasRunningTask()

                // (CHA-T4b) If typing is already in progress, the CHA-T3 timeout is extended to be timeoutMs from now.
                if isUserTyping {
                    logger.log(message: "User is already typing. Extending timeout.", level: .debug)
                    await timerManager.setTimer(interval: timeout) { [stop] in
                        Task {
                            try await stop()
                        }
                    }
                    continuation.resume()
                } else {
                    // (CHA-T4a) If typing is not already in progress, per explicit cancellation or the timeout interval in (CHA-T3), then a new typing session is started.
                    logger.log(message: "User is not typing. Starting typing.", level: .debug)
                    do {
                        try startTyping()
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    // (CHA-T5) Users may indicate that they have stopped typing.
    internal func stop() async throws {
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence leave operation: \(error)", level: .error)
            throw error
        }

        let isUserTyping = await timerManager.hasRunningTask()
        if isUserTyping {
            logger.log(message: "Stopping typing indicator for client: \(clientID)", level: .debug)
            // (CHA-T5b) If typing is in progress, he CHA-T3 timeout is cancelled. The client then leaves presence.
            await timerManager.cancelTimer()
            channel.presence.leaveClient(clientID, data: nil)
        } else {
            // (CHA-T5a) If typing is not in progress, this operation is no-op.
            logger.log(message: "User is not typing. No need to leave presence.", level: .debug)
        }
    }

    // (CHA-T7) Users may subscribe to discontinuity events to know when there’s been a break in typing indicators. Their listener will be called when a discontinuity event is triggered from the room lifecycle. For typing, there shouldn’t need to be user action as the underlying core SDK will heal the presence set.
    internal func subscribeToDiscontinuities(bufferingPolicy: BufferingPolicy) async -> Subscription<DiscontinuityEvent> {
        await featureChannel.subscribeToDiscontinuities(bufferingPolicy: bufferingPolicy)
    }

    private func processPresenceGet(members: [ARTPresenceMessage]?, error: ARTErrorInfo?) throws -> Set<String> {
        guard let members else {
            let error = error ?? ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without data")
            logger.log(message: error.message, level: .error)
            throw error
        }

        let clientIDs = try Set<String>(members.map { member in
            guard let clientID = member.clientId else {
                let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without clientId")
                logger.log(message: error.message, level: .error)
                throw error
            }

            return clientID
        })

        return clientIDs
    }

    private func startTyping() throws {
        // (CHA-T4a1) When a typing session is started, the client is entered into presence on the typing channel.
        channel.presence.enterClient(clientID, data: nil) { [weak self] error in
            guard let self else {
                return
            }
            Task {
                if let error {
                    logger.log(message: "Error entering presence: \(error)", level: .error)
                    throw error
                } else {
                    logger.log(message: "Entered presence - starting timer", level: .debug)
                    // (CHA-T4a2)  When a typing session is started, a timeout is set according to the CHA-T3 timeout interval. When this timeout expires, the typing session is automatically ended by leaving presence.
                    await timerManager.setTimer(interval: timeout) { [stop] in
                        Task {
                            try await stop()
                        }
                    }
                }
            }
        }
    }
}

private final actor EventTracker {
    private var latestEventID: UUID = .init()

    func updateEventID() -> UUID {
        let newID = UUID()
        latestEventID = newID
        return newID
    }

    func isLatestEvent(_ eventID: UUID) -> Bool {
        latestEventID == eventID
    }
}
