@preconcurrency import Ably
import AsyncAlgorithms

/// The interface that the lifecycle manager expects its contributing realtime channels to conform to.
///
/// We use this instead of the ``RealtimeChannelProtocol`` interface as:
///
/// - its ``attach`` and ``detach`` methods are `async` instead of using callbacks
/// - it uses `AsyncSequence` to emit state changes instead of using callbacks
///
/// This makes it easier to write mocks for (since ``RealtimeChannelProtocol`` doesn’t express to the type system that the callbacks it receives need to be `Sendable`, it’s hard to, for example, create a mock that creates a `Task` and then calls the callback from inside this task).
///
/// We choose to also mark the channel’s mutable state as `async`. This is a way of highlighting at the call site of accessing this state that, since `ARTRealtimeChannel` mutates this state on a separate thread, it’s possible for this state to have changed since the last time you checked it, or since the last time you performed an operation that might have mutated it, or since the last time you recieved an event informing you that it changed. To be clear, marking these as `async` doesn’t _solve_ these issues; it just makes them a bit more visible. We’ll decide how to address them in https://github.com/ably-labs/ably-chat-swift/issues/49.
internal protocol RoomLifecycleContributorChannel: Sendable {
    func attach() async throws(ARTErrorInfo)
    func detach() async throws(ARTErrorInfo)

    var state: ARTRealtimeChannelState { get async }
    var errorReason: ARTErrorInfo? { get async }

    /// Equivalent to subscribing to a `RealtimeChannelProtocol` object’s state changes via its `on(_:)` method. The subscription should use the ``BufferingPolicy.unbounded`` buffering policy.
    ///
    /// It is marked as `async` purely to make it easier to write mocks for this method (i.e. to use an actor as a mock).
    func subscribeToState() async -> Subscription<ARTChannelStateChange>
}

/// A realtime channel that contributes to the room lifecycle.
///
/// The identity implied by the `Identifiable` conformance must distinguish each of the contributors passed to a given ``RoomLifecycleManager`` instance.
internal protocol RoomLifecycleContributor: Identifiable, Sendable {
    associatedtype Channel: RoomLifecycleContributorChannel

    /// The room feature that this contributor corresponds to. Used only for choosing which error to throw when a contributor operation fails.
    var feature: RoomFeature { get }
    var channel: Channel { get }

    /// Informs the contributor that there has been a break in channel continuity, which it should inform library users about.
    ///
    /// It is marked as `async` purely to make it easier to write mocks for this method (i.e. to use an actor as a mock).
    func emitDiscontinuity(_ error: ARTErrorInfo) async
}

internal actor RoomLifecycleManager<Contributor: RoomLifecycleContributor> {
    // MARK: - Constant properties

    private let logger: InternalLogger
    private let clock: SimpleClock
    private let contributors: [Contributor]

    // MARK: - Variable properties

    private var status: Status
    /// Manager state that relates to individual contributors, keyed by contributors’ ``Contributor.id``. Stored separately from ``contributors`` so that the latter can be a `let`, to make it clear that the contributors remain fixed for the lifetime of the manager.
    private var contributorAnnotations: ContributorAnnotations
    private var listenForStateChangesTask: Task<Void, Never>!
    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var subscriptions: [Subscription<RoomStatusChange>] = []
    private var operationResultContinuations = OperationResultContinuations()

    // MARK: - Initializers and `deinit`

    internal init(
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) async {
        await self.init(
            status: nil,
            pendingDiscontinuityEvents: [:],
            contributors: contributors,
            logger: logger,
            clock: clock
        )
    }

    #if DEBUG
        internal init(
            testsOnly_status status: Status? = nil,
            testsOnly_pendingDiscontinuityEvents pendingDiscontinuityEvents: [Contributor.ID: [ARTErrorInfo]]? = nil,
            contributors: [Contributor],
            logger: InternalLogger,
            clock: SimpleClock
        ) async {
            await self.init(
                status: status,
                pendingDiscontinuityEvents: pendingDiscontinuityEvents,
                contributors: contributors,
                logger: logger,
                clock: clock
            )
        }
    #endif

    private init(
        status: Status?,
        pendingDiscontinuityEvents: [Contributor.ID: [ARTErrorInfo]]?,
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) async {
        self.status = status ?? .initialized
        self.contributors = contributors
        contributorAnnotations = .init(contributors: contributors, pendingDiscontinuityEvents: pendingDiscontinuityEvents ?? [:])
        self.logger = logger
        self.clock = clock

        // The idea here is to make sure that, before the initializer completes, we are already listening for state changes, so that e.g. tests don’t miss a state change.
        let subscriptions = await withTaskGroup(of: (contributor: Contributor, subscription: Subscription<ARTChannelStateChange>).self) { group in
            for contributor in contributors {
                group.addTask {
                    await (contributor: contributor, subscription: contributor.channel.subscribeToState())
                }
            }

            return await Array(group)
        }

        // CHA-RL4: listen for state changes from our contributors
        // TODO: Understand what happens when this task gets cancelled by `deinit`; I’m not convinced that the for-await loops will exit (https://github.com/ably-labs/ably-chat-swift/issues/29)
        listenForStateChangesTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for (contributor, subscription) in subscriptions {
                    // This `@Sendable` is to make the compiler error "'self'-isolated value of type '() async -> Void' passed as a strongly transferred parameter; later accesses could race" go away. I don’t hugely understand what it means, but given the "'self'-isolated value" I guessed it was something vaguely to do with the fact that `async` actor initializers are actor-isolated and thought that marking it as `@Sendable` would sever this isolation and make the error go away, which it did 🤷. But there are almost certainly consequences that I am incapable of reasoning about with my current level of Swift concurrency knowledge.
                    group.addTask { @Sendable [weak self] in
                        for await stateChange in subscription {
                            await self?.didReceiveStateChange(stateChange, forContributor: contributor)
                        }
                    }
                }
            }
        }
    }

    deinit {
        listenForStateChangesTask.cancel()
    }

    // MARK: - Type for room status

    internal enum Status: Equatable {
        case initialized
        case attaching(attachOperationID: UUID)
        case attached
        case detaching(detachOperationID: UUID)
        case detached
        case suspended(error: ARTErrorInfo)
        case failed(error: ARTErrorInfo)
        case releasing(releaseOperationID: UUID)
        case released

        internal var toRoomLifecycle: RoomLifecycle {
            switch self {
            case .initialized:
                .initialized
            case .attaching:
                .attaching
            case .attached:
                .attached
            case .detaching:
                .detaching
            case .detached:
                .detached
            case let .suspended(error):
                .suspended(error: error)
            case let .failed(error):
                .failed(error: error)
            case .releasing:
                .releasing
            case .released:
                .released
            }
        }

        fileprivate var operationID: UUID? {
            switch self {
            case let .attaching(attachOperationID):
                attachOperationID
            case let .detaching(detachOperationID):
                detachOperationID
            case let .releasing(releaseOperationID):
                releaseOperationID
            case .suspended,
                 .initialized,
                 .attached,
                 .detached,
                 .failed,
                 .released:
                nil
            }
        }
    }

    // MARK: - Types for contributor annotations

    /// Stores manager state relating to a given contributor.
    private struct ContributorAnnotation {
        // TODO: Not clear whether there can be multiple or just one (asked in https://github.com/ably/specification/pull/200/files#r1781927850)
        var pendingDiscontinuityEvents: [ARTErrorInfo] = []
    }

    /// Provides a `Dictionary`-like interface for storing manager state about individual contributors.
    private struct ContributorAnnotations {
        private var storage: [Contributor.ID: ContributorAnnotation]

        init(contributors: [Contributor], pendingDiscontinuityEvents: [Contributor.ID: [ARTErrorInfo]]) {
            storage = contributors.reduce(into: [:]) { result, contributor in
                result[contributor.id] = .init(pendingDiscontinuityEvents: pendingDiscontinuityEvents[contributor.id] ?? [])
            }
        }

        /// It is a programmer error to call this subscript getter with a contributor that was not one of those passed to ``init(contributors:pendingDiscontinuityEvents)``.
        subscript(_ contributor: Contributor) -> ContributorAnnotation {
            get {
                guard let annotation = storage[contributor.id] else {
                    preconditionFailure("Expected annotation for \(contributor)")
                }
                return annotation
            }

            set {
                storage[contributor.id] = newValue
            }
        }

        mutating func clearPendingDiscontinuityEvents() {
            storage = storage.mapValues { annotation in
                var newAnnotation = annotation
                newAnnotation.pendingDiscontinuityEvents = []
                return newAnnotation
            }
        }
    }

    // MARK: - Room status and its changes

    internal var current: RoomLifecycle {
        status.toRoomLifecycle
    }

    internal func onChange(bufferingPolicy: BufferingPolicy) -> Subscription<RoomStatusChange> {
        let subscription: Subscription<RoomStatusChange> = .init(bufferingPolicy: bufferingPolicy)
        subscriptions.append(subscription)
        return subscription
    }

    /// Updates ``status`` and emits a status change event.
    private func changeStatus(to new: Status) {
        logger.log(message: "Transitioning from \(status) to \(new)", level: .info)
        let previous = status
        status = new
        let statusChange = RoomStatusChange(current: status.toRoomLifecycle, previous: previous.toRoomLifecycle)
        emitStatusChange(statusChange)
    }

    private func emitStatusChange(_ change: RoomStatusChange) {
        for subscription in subscriptions {
            subscription.emit(change)
        }
    }

    // MARK: - Handling contributor state changes

    #if DEBUG
        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToHandledContributorStateChanges()`` method.
        private var stateChangeHandledSubscriptions: [Subscription<ARTChannelStateChange>] = []

        /// Returns a subscription which emits the contributor state changes that have been handled by the manager.
        ///
        /// A contributor state change is considered handled once the manager has performed all of the side effects that it will perform as a result of receiving this state change. Specifically, once:
        ///
        /// - the manager has recorded all pending discontinuity events provoked by the state change (you can retrieve these using ``testsOnly_pendingDiscontinuityEventsForContributor(at:)``)
        /// - the manager has performed all status changes provoked by the state change
        /// - the manager has performed all contributor actions provoked by the state change, namely calls to ``RoomLifecycleContributorChannel.detach()`` or ``RoomLifecycleContributor.emitDiscontinuity(_:)``
        internal func testsOnly_subscribeToHandledContributorStateChanges() -> Subscription<ARTChannelStateChange> {
            let subscription = Subscription<ARTChannelStateChange>(bufferingPolicy: .unbounded)
            stateChangeHandledSubscriptions.append(subscription)
            return subscription
        }

        internal func testsOnly_pendingDiscontinuityEvents(for contributor: Contributor) -> [ARTErrorInfo] {
            contributorAnnotations[contributor].pendingDiscontinuityEvents
        }
    #endif

    /// Implements CHA-RL4b’s contributor state change handling.
    private func didReceiveStateChange(_ stateChange: ARTChannelStateChange, forContributor contributor: Contributor) async {
        logger.log(message: "Got state change \(stateChange) for contributor \(contributor)", level: .info)

        // TODO: The spec, which is written for a single-threaded environment, is presumably operating on the assumption that the channel is currently in the state given by `stateChange.current` (https://github.com/ably-labs/ably-chat-swift/issues/49)
        switch stateChange.event {
        case .update:
            // CHA-RL4a1 — if RESUMED then no-op
            guard !stateChange.resumed else {
                break
            }

            guard let reason = stateChange.reason else {
                // TODO: Decide the right thing to do here (https://github.com/ably-labs/ably-chat-swift/issues/74)
                preconditionFailure("State change event with resumed == false should have a reason")
            }

            if hasOperationInProgress {
                // CHA-RL4a3
                logger.log(message: "Recording pending discontinuity event for contributor \(contributor)", level: .info)

                contributorAnnotations[contributor].pendingDiscontinuityEvents.append(reason)
            } else {
                // CHA-RL4a4
                logger.log(message: "Emitting discontinuity event for contributor \(contributor)", level: .info)

                await contributor.emitDiscontinuity(reason)
            }
        case .attached:
            if hasOperationInProgress {
                if !stateChange.resumed {
                    // CHA-RL4b1
                    logger.log(message: "Recording pending discontinuity event for contributor \(contributor)", level: .info)

                    guard let reason = stateChange.reason else {
                        // TODO: Decide the right thing to do here (https://github.com/ably-labs/ably-chat-swift/issues/74)
                        preconditionFailure("State change event with resumed == false should have a reason")
                    }

                    contributorAnnotations[contributor].pendingDiscontinuityEvents.append(reason)
                }
            } else if status != .attached {
                if await (contributors.async.map { await $0.channel.state }.allSatisfy { $0 == .attached }) {
                    // CHA-RL4b8
                    logger.log(message: "Now that all contributors are ATTACHED, transitioning room to ATTACHED", level: .info)
                    changeStatus(to: .attached)
                }
            }
        case .failed:
            if !hasOperationInProgress {
                // CHA-RL4b5
                guard let reason = stateChange.reason else {
                    // TODO: Decide the right thing to do here (https://github.com/ably-labs/ably-chat-swift/issues/74)
                    preconditionFailure("FAILED state change event should have a reason")
                }

                changeStatus(to: .failed(error: reason))

                // TODO: CHA-RL4b5 is a bit unclear about how to handle failure, and whether they can be detached concurrently (asked in https://github.com/ably/specification/pull/200/files#r1777471810)
                for contributor in contributors {
                    do {
                        try await contributor.channel.detach()
                    } catch {
                        logger.log(message: "Failed to detach contributor \(contributor), error \(error)", level: .info)
                    }
                }
            }
        case .suspended:
            if !hasOperationInProgress {
                // CHA-RL4b9
                guard let reason = stateChange.reason else {
                    // TODO: Decide the right thing to do here (https://github.com/ably-labs/ably-chat-swift/issues/74)
                    preconditionFailure("SUSPENDED state change event should have a reason")
                }

                changeStatus(to: .suspended(error: reason))
            }
        default:
            break
        }

        #if DEBUG
            for subscription in stateChangeHandledSubscriptions {
                subscription.emit(stateChange)
            }
        #endif
    }

    // MARK: - Operation handling

    /// Whether the room lifecycle manager currently has a room lifecycle operation in progress.
    ///
    /// - Warning: I haven’t yet figured out the exact meaning of “has an operation in progress” — at what point is an operation considered to be no longer in progress? Is it the point at which the operation has updated the manager’s status to one that no longer indicates an in-progress operation (this is the meaning currently used by `hasOperationInProgress`)? Or is it the point at which the `bodyOf*Operation` method for that operation exits (i.e. the point at which ``performAnOperation(_:)`` considers the operation to have completed)? Does it matter? I’ve chosen to not think about this very much right now, but might need to revisit. See TODO against `emitPendingDiscontinuityEvents` in `bodyOfDetachOperation` for an example of something where these two notions of “has an operation in progress” are not equivalent.
    private var hasOperationInProgress: Bool {
        status.operationID != nil
    }

    /// Stores bookkeeping information needed for allowing one operation to await the result of another.
    private struct OperationResultContinuations {
        typealias Continuation = CheckedContinuation<Void, Error>

        private var operationResultContinuationsByOperationID: [UUID: [Continuation]] = [:]

        mutating func addContinuation(_ continuation: Continuation, forResultOfOperationWithID operationID: UUID) {
            operationResultContinuationsByOperationID[operationID, default: []].append(continuation)
        }

        mutating func removeContinuationsForResultOfOperationWithID(_ waitedOperationID: UUID) -> [Continuation] {
            operationResultContinuationsByOperationID.removeValue(forKey: waitedOperationID) ?? []
        }
    }

    #if DEBUG
        /// The manager emits an `OperationWaitEvent` each time one room lifecycle operation is going to wait for another to complete. These events are emitted to support testing of the manager; see ``testsOnly_subscribeToOperationWaitEvents``.
        internal struct OperationWaitEvent: Equatable {
            /// The ID of the operation which initiated the wait. It is waiting for the operation with ID ``waitedOperationID`` to complete.
            internal var waitingOperationID: UUID
            /// The ID of the operation whose completion will be awaited.
            internal var waitedOperationID: UUID
        }

        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToOperationWaitEvents()`` method.
        private var operationWaitEventSubscriptions: [Subscription<OperationWaitEvent>] = []

        /// Returns a subscription which emits an event each time one room lifecycle operation is going to wait for another to complete.
        internal func testsOnly_subscribeToOperationWaitEvents() -> Subscription<OperationWaitEvent> {
            let subscription = Subscription<OperationWaitEvent>(bufferingPolicy: .unbounded)
            operationWaitEventSubscriptions.append(subscription)
            return subscription
        }
    #endif

    /// Waits for the operation with ID `waitedOperationID` to complete, re-throwing any error thrown by that operation.
    ///
    /// Note that this method currently treats all waited operations as throwing. If you wish to wait for an operation that you _know_ to be non-throwing (which the RELEASE operation currently is) then you’ll need to call this method with `try!` or equivalent. (It might be possible to improve this in the future, but I didn’t want to put much time into figuring it out.)
    ///
    /// It is guaranteed that if you call this method from a manager-isolated method, and subsequently call ``operationWithID(_:,didCompleteWithResult:)`` from another manager-isolated method, then the call to this method will return.
    ///
    /// - Parameters:
    ///   - waitedOperationID: The ID of the operation whose completion will be awaited.
    ///   - waitingOperationID: The ID of the operation which is awaiting this result. Only used for logging.
    private func waitForCompletionOfOperationWithID(
        _ waitedOperationID: UUID,
        waitingOperationID: UUID
    ) async throws {
        logger.log(message: "Operation \(waitingOperationID) started waiting for result of operation \(waitedOperationID)", level: .debug)

        do {
            try await withCheckedThrowingContinuation { (continuation: OperationResultContinuations.Continuation) in
                // My “it is guaranteed” in the documentation for this method is really more of an “I hope that”, because it’s based on my pretty vague understanding of Swift concurrency concepts; namely, I believe that if you call this manager-isolated `async` method from another manager-isolated method, the initial synchronous part of this method — in particular the call to `addContinuation` below — will occur _before_ the call to this method suspends. (I think this can be roughly summarised as “calls to async methods on self don’t do actor hopping” but I could be completely misusing a load of Swift concurrency vocabulary there.)
                operationResultContinuations.addContinuation(continuation, forResultOfOperationWithID: waitedOperationID)

                #if DEBUG
                    let operationWaitEvent = OperationWaitEvent(waitingOperationID: waitingOperationID, waitedOperationID: waitedOperationID)
                    for subscription in operationWaitEventSubscriptions {
                        subscription.emit(operationWaitEvent)
                    }
                #endif
            }

            logger.log(message: "Operation \(waitingOperationID) completed waiting for result of operation \(waitedOperationID), which completed successfully", level: .debug)
        } catch {
            logger.log(message: "Operation \(waitingOperationID) completed waiting for result of operation \(waitedOperationID), which threw error \(error)", level: .debug)
        }
    }

    /// Operations should call this when they have completed, in order to complete any waits initiated by ``waitForCompletionOfOperationWithID(_:waitingOperationID:)``.
    private func operationWithID(_ operationID: UUID, didCompleteWithResult result: Result<Void, Error>) {
        logger.log(message: "Operation \(operationID) completed with result \(result)", level: .debug)
        let continuationsToResume = operationResultContinuations.removeContinuationsForResultOfOperationWithID(operationID)

        for continuation in continuationsToResume {
            continuation.resume(with: result)
        }
    }

    /// Executes a function that represents a room lifecycle operation.
    ///
    /// - Note: Note that `RoomLifecycleManager` does not implement any sort of mutual exclusion mechanism that _enforces_ that one room lifecycle operation must wait for another (e.g. it is _not_ a queue); each operation needs to implement its own logic for whether it should proceed in the presence of other in-progress operations.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Forces the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    ///   - body: The implementation of the operation to be performed. Once this function returns or throws an error, the operation is considered to have completed, and any waits for this operation’s completion initiated via ``waitForCompletionOfOperationWithID(_:waitingOperationID:)`` will complete.
    private func performAnOperation<Failure: Error>(
        forcingOperationID forcedOperationID: UUID?,
        _ body: (UUID) async throws(Failure) -> Void
    ) async throws(Failure) {
        let operationID = forcedOperationID ?? UUID()
        logger.log(message: "Performing operation \(operationID)", level: .debug)
        let result: Result<Void, Failure>
        do {
            // My understanding (based on what the compiler allows me to do, and a vague understanding of how actors work) is that inside this closure you can write code as if it were a method on the manager itself — i.e. with synchronous access to the manager’s state. But I currently lack the Swift concurrency vocabulary to explain exactly why this is the case.
            try await body(operationID)
            result = .success(())
        } catch {
            result = .failure(error)
        }

        operationWithID(operationID, didCompleteWithResult: result.mapError { $0 })

        try result.get()
    }

    // MARK: - ATTACH operation

    /// Implements CHA-RL1’s `ATTACH` operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    internal func performAttachOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async throws {
        try await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            try await bodyOfAttachOperation(operationID: operationID)
        }
    }

    private func bodyOfAttachOperation(operationID: UUID) async throws {
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

        // CHA-RL1d
        if let currentOperationID = status.operationID {
            try? await waitForCompletionOfOperationWithID(currentOperationID, waitingOperationID: operationID)
        }

        // CHA-RL1e
        changeStatus(to: .attaching(attachOperationID: operationID))

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
                    changeStatus(to: .suspended(error: error))

                    // CHA-RL1h3
                    throw error
                case .failed:
                    // CHA-RL1h4
                    let error = ARTErrorInfo(chatError: .attachmentFailed(feature: contributor.feature, underlyingError: contributorAttachError))
                    changeStatus(to: .failed(error: error))

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

        // CHA-RL1g2
        // TODO: It’s not clear to me whether this is considered to be part of the ATTACH operation or not; see the note on the ``hasOperationInProgress`` property
        await emitPendingDiscontinuityEvents()
    }

    /// Implements CHA-RL1g2’s emitting of pending discontinuity events.
    private func emitPendingDiscontinuityEvents() async {
        // Emit all pending discontinuity events
        logger.log(message: "Emitting pending discontinuity events", level: .info)
        for contributor in contributors {
            for pendingDiscontinuityEvent in contributorAnnotations[contributor].pendingDiscontinuityEvents {
                logger.log(message: "Emitting pending discontinuity event \(pendingDiscontinuityEvent) to contributor \(contributor)", level: .info)
                await contributor.emitDiscontinuity(pendingDiscontinuityEvent)
            }
        }

        contributorAnnotations.clearPendingDiscontinuityEvents()
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

    // MARK: - DETACH operation

    /// Implements CHA-RL2’s DETACH operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    internal func performDetachOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async throws {
        try await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            try await bodyOfDetachOperation(operationID: operationID)
        }
    }

    private func bodyOfDetachOperation(operationID: UUID) async throws {
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
        changeStatus(to: .detaching(detachOperationID: operationID))

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
                    if !status.toRoomLifecycle.isFailed {
                        changeStatus(to: .failed(error: error))
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

    // MARK: - RELEASE operation

    /// Implements CHA-RL3’s RELEASE operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    internal func performReleaseOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async {
        await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            await bodyOfReleaseOperation(operationID: operationID)
        }
    }

    private func bodyOfReleaseOperation(operationID: UUID) async {
        switch status {
        case .released:
            // CHA-RL3a
            return
        case .detached:
            // CHA-RL3b
            changeStatus(to: .released)
            return
        case let .releasing(releaseOperationID):
            // CHA-RL3c
            // See note on waitForCompletionOfOperationWithID for the current need for this force try
            // swiftlint:disable:next force_try
            return try! await waitForCompletionOfOperationWithID(releaseOperationID, waitingOperationID: operationID)
        case .initialized, .attached, .attaching, .detaching, .suspended, .failed:
            break
        }

        // CHA-RL3c
        changeStatus(to: .releasing(releaseOperationID: operationID))

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
