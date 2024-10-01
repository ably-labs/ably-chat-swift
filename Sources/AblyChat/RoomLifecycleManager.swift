import Ably

/// The interface that the lifecycle manager expects its contributing realtime channels to conform to.
///
/// We use this instead of the ``RealtimeChannel`` interface as its ``attach`` and ``detach`` methods are `async` instead of using callbacks. This makes it easier to write mocks for (since ``RealtimeChannel`` doesn’t express to the type system that the callbacks it receives need to be `Sendable`, it’s hard to, for example, create a mock that creates a `Task` and then calls the callback from inside this task).
///
/// We choose to also mark the channel’s mutable state as `async`. This is a way of highlighting at the call site of accessing this state that, since `ARTRealtimeChannel` mutates this state on a separate thread, it’s possible for this state to have changed since the last time you checked it, or since the last time you performed an operation that might have mutated it, or since the last time you recieved an event informing you that it changed. To be clear, marking these as `async` doesn’t _solve_ these issues; it just makes them a bit more visible. We’ll decide how to address them in https://github.com/ably-labs/ably-chat-swift/issues/49.
internal protocol RoomLifecycleContributorChannel: Sendable {
    func attach() async throws(ARTErrorInfo)
    func detach() async throws(ARTErrorInfo)

    var state: ARTRealtimeChannelState { get async }
    var errorReason: ARTErrorInfo? { get async }
}

internal actor RoomLifecycleManager<Channel: RoomLifecycleContributorChannel> {
    /// A realtime channel that contributes to the room lifecycle.
    internal struct Contributor {
        /// The room feature that this contributor corresponds to. Used only for choosing which error to throw when a contributor operation fails.
        internal var feature: RoomFeature

        internal var channel: Channel
    }

    internal private(set) var status: RoomStatus
    internal private(set) var error: ARTErrorInfo?

    private let logger: InternalLogger
    private let clock: SimpleClock
    private let contributors: [Contributor]

    internal init(
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) {
        self.init(
            status: nil,
            contributors: contributors,
            logger: logger,
            clock: clock
        )
    }

    #if DEBUG
        internal init(
            testsOnly_status status: RoomStatus? = nil,
            contributors: [Contributor],
            logger: InternalLogger,
            clock: SimpleClock
        ) {
            self.init(
                status: status,
                contributors: contributors,
                logger: logger,
                clock: clock
            )
        }
    #endif

    private init(
        status: RoomStatus?,
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) {
        self.status = status ?? .initialized
        self.contributors = contributors
        self.logger = logger
        self.clock = clock
    }

    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var subscriptions: [Subscription<RoomStatusChange>] = []

    internal func onChange(bufferingPolicy: BufferingPolicy) -> Subscription<RoomStatusChange> {
        let subscription: Subscription<RoomStatusChange> = .init(bufferingPolicy: bufferingPolicy)
        subscriptions.append(subscription)
        return subscription
    }

    /// Updates ``status`` and ``error`` and emits a status change event.
    private func changeStatus(to new: RoomStatus, error: ARTErrorInfo? = nil) {
        logger.log(message: "Transitioning from \(status) to \(new), error \(String(describing: error))", level: .info)
        let previous = status
        status = new
        self.error = error
        let statusChange = RoomStatusChange(current: status, previous: previous, error: error)
        emitStatusChange(statusChange)
    }

    private func emitStatusChange(_ change: RoomStatusChange) {
        for subscription in subscriptions {
            subscription.emit(change)
        }
    }

    /// Implements CHA-RL1’s `ATTACH` operation.
    internal func performAttachOperation() async throws {
        switch status {
        case .attached:
            // CHA-RL1a
            return
        case .releasing:
            // CHA-RL1b
            throw ARTErrorInfo(chatError: .roomIsReleasing)
        case .released:
            // CHA-RL1c
            throw ARTErrorInfo(chatError: .roomIsReleased)
        case .initialized, .suspended, .attaching, .detached, .detaching, .failed:
            break
        }

        // CHA-RL1e
        changeStatus(to: .attaching)

        // CHA-RL1f
        for contributor in contributors {
            do {
                logger.log(message: "Attaching contributor \(contributor)", level: .info)
                try await contributor.channel.attach()
            } catch let contributorAttachError {
                let contributorState = await contributor.channel.state
                logger.log(message: "Failed to attach contributor \(contributor), which is now in state \(contributorState), error \(contributorAttachError)", level: .info)

                switch contributorState {
                case .suspended:
                    // CHA-RL1h2
                    let error = ARTErrorInfo(chatError: .attachmentFailed(feature: contributor.feature, underlyingError: contributorAttachError))
                    changeStatus(to: .suspended, error: error)

                    // CHA-RL1h3
                    throw error
                case .failed:
                    // CHA-RL1h4
                    let error = ARTErrorInfo(chatError: .attachmentFailed(feature: contributor.feature, underlyingError: contributorAttachError))
                    changeStatus(to: .failed, error: error)

                    // CHA-RL1h5
                    // TODO: Implement the "asynchronously with respect to CHA-RL1h4" part of CHA-RL1h5 (https://github.com/ably-labs/ably-chat-swift/issues/50)
                    await detachNonFailedContributors()

                    throw error
                default:
                    // TODO: The spec assumes the channel will be in one of the above states, but working in a multi-threaded environment means it might not be (https://github.com/ably-labs/ably-chat-swift/issues/49)
                    preconditionFailure("Attach failure left contributor in unexpected state \(contributorState)")
                }
            }
        }

        // CHA-RL1g1
        changeStatus(to: .attached)
    }

    /// Implements CHA-RL1h5’s "detach all channels that are not in the FAILED state".
    private func detachNonFailedContributors() async {
        for contributor in contributors where await (contributor.channel.state) != .failed {
            // CHA-RL1h6: Retry until detach succeeds
            while true {
                do {
                    logger.log(message: "Detaching non-failed contributor \(contributor)", level: .info)
                    try await contributor.channel.detach()
                    break
                } catch {
                    logger.log(message: "Failed to detach non-failed contributor \(contributor), error \(error). Retrying.", level: .info)
                    // Loop repeats
                }
            }
        }
    }

    /// Implements CHA-RL2’s DETACH operation.
    internal func performDetachOperation() async throws {
        switch status {
        case .detached:
            // CHA-RL2a
            return
        case .releasing:
            // CHA-RL2b
            throw ARTErrorInfo(chatError: .roomIsReleasing)
        case .released:
            // CHA-RL2c
            throw ARTErrorInfo(chatError: .roomIsReleased)
        case .failed:
            // CHA-RL2d
            throw ARTErrorInfo(chatError: .roomInFailedState)
        case .initialized, .suspended, .attaching, .attached, .detaching:
            break
        }

        // CHA-RL2e
        changeStatus(to: .detaching)

        // CHA-RL2f
        var firstDetachError: Error?
        for contributor in contributors {
            logger.log(message: "Detaching contributor \(contributor)", level: .info)
            do {
                try await contributor.channel.detach()
            } catch {
                let contributorState = await contributor.channel.state
                logger.log(message: "Failed to detach contributor \(contributor), which is now in state \(contributorState), error \(error)", level: .info)

                switch contributorState {
                case .failed:
                    // CHA-RL2h1
                    guard let contributorError = await contributor.channel.errorReason else {
                        // TODO: The spec assumes this will be populated, but working in a multi-threaded environment means it might not be (https://github.com/ably-labs/ably-chat-swift/issues/49)
                        preconditionFailure("Contributor entered FAILED but its errorReason is not set")
                    }

                    let error = ARTErrorInfo(chatError: .detachmentFailed(feature: contributor.feature, underlyingError: contributorError))

                    if firstDetachError == nil {
                        // We’ll throw this after we’ve tried detaching all the channels
                        firstDetachError = error
                    }

                    // This check is CHA-RL2h2
                    if status != .failed {
                        changeStatus(to: .failed, error: error)
                    }
                default:
                    // CHA-RL2h3: Retry until detach succeeds, with a pause before each attempt
                    while true {
                        do {
                            logger.log(message: "Will attempt to detach non-failed contributor \(contributor) in 1s.", level: .info)
                            // TODO: what's the correct wait time? (https://github.com/ably/specification/pull/200#discussion_r1763799223)
                            try await clock.sleep(timeInterval: 1)
                            logger.log(message: "Detaching non-failed contributor \(contributor)", level: .info)
                            try await contributor.channel.detach()
                            break
                        } catch {
                            // Loop repeats
                            logger.log(message: "Failed to detach non-failed contributor \(contributor), error \(error). Will retry.", level: .info)
                        }
                    }
                }
            }
        }

        if let firstDetachError {
            // CHA-RL2f
            throw firstDetachError
        }

        // CHA-RL2g
        changeStatus(to: .detached)
    }

    /// Implementes CHA-RL3’s RELEASE operation.
    internal func performReleaseOperation() async {
        switch status {
        case .released:
            // CHA-RL3a
            return
        case .detached:
            // CHA-RL3b
            changeStatus(to: .released)
            return
        case .releasing, .initialized, .attached, .attaching, .detaching, .suspended, .failed:
            break
        }

        changeStatus(to: .releasing)

        // CHA-RL3d
        for contributor in contributors {
            while true {
                let contributorState = await contributor.channel.state

                // CHA-RL3e
                guard contributorState != .failed else {
                    logger.log(message: "Contributor \(contributor) is FAILED; skipping detach", level: .info)
                    break
                }

                logger.log(message: "Detaching contributor \(contributor)", level: .info)
                do {
                    try await contributor.channel.detach()
                    break
                } catch {
                    // CHA-RL3f: Retry until detach succeeds, with a pause before each attempt
                    logger.log(message: "Failed to detach contributor \(contributor), error \(error). Will retry in 1s.", level: .info)
                    // TODO: Make this not trap in the case where the Task is cancelled (as part of the broader https://github.com/ably-labs/ably-chat-swift/issues/29 for handling task cancellation)
                    // TODO: what's the correct wait time? (https://github.com/ably/specification/pull/200#discussion_r1763822207)
                    // swiftlint:disable:next force_try
                    try! await clock.sleep(timeInterval: 1)
                    // Loop repeats
                }
            }
        }

        // CHA-RL3g
        changeStatus(to: .released)
    }
}
