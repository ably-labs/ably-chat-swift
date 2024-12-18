import Ably
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

    /// Equivalent to subscribing to a `RealtimeChannelProtocol` object’s state changes via its `on(_:)` method. The subscription should use the ``BufferingPolicy/unbounded`` buffering policy.
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
    func emitDiscontinuity(_ discontinuity: DiscontinuityEvent) async
}

internal protocol RoomLifecycleManager: Sendable {
    func performAttachOperation() async throws
    func performDetachOperation() async throws
    func performReleaseOperation() async
    var roomStatus: RoomStatus { get async }
    func onRoomStatusChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange>
    func waitToBeAbleToPerformPresenceOperations(requestedByFeature requester: RoomFeature) async throws(ARTErrorInfo)
}

internal protocol RoomLifecycleManagerFactory: Sendable {
    associatedtype Contributor: RoomLifecycleContributor
    associatedtype Manager: RoomLifecycleManager

    func createManager(
        contributors: [Contributor],
        logger: InternalLogger
    ) async -> Manager
}

internal final class DefaultRoomLifecycleManagerFactory: RoomLifecycleManagerFactory {
    private let clock = DefaultSimpleClock()

    internal func createManager(
        contributors: [DefaultRoomLifecycleContributor],
        logger: InternalLogger
    ) async -> DefaultRoomLifecycleManager<DefaultRoomLifecycleContributor> {
        await .init(
            contributors: contributors,
            logger: logger,
            clock: clock
        )
    }
}

internal actor DefaultRoomLifecycleManager<Contributor: RoomLifecycleContributor>: RoomLifecycleManager {
    // MARK: - Constant properties

    private let logger: InternalLogger
    private let clock: SimpleClock
    private let contributors: [Contributor]

    // MARK: - Variable properties

    private var status: Status
    /// Manager state that relates to individual contributors, keyed by contributors’ ``Contributor/id``. Stored separately from ``contributors`` so that the latter can be a `let`, to make it clear that the contributors remain fixed for the lifetime of the manager.
    private var contributorAnnotations: ContributorAnnotations
    private var listenForStateChangesTask: Task<Void, Never>!
    // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
    private var roomStatusChangeSubscriptions = SubscriptionStorage<RoomStatusChange>()
    private var operationResultContinuations = OperationResultContinuations()

    // MARK: - Initializers and `deinit`

    internal init(
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) async {
        await self.init(
            status: nil,
            pendingDiscontinuityEvents: nil,
            idsOfContributorsWithTransientDisconnectTimeout: nil,
            contributors: contributors,
            logger: logger,
            clock: clock
        )
    }

    #if DEBUG
        internal init(
            testsOnly_status status: Status? = nil,
            testsOnly_pendingDiscontinuityEvents pendingDiscontinuityEvents: [Contributor.ID: DiscontinuityEvent]? = nil,
            testsOnly_idsOfContributorsWithTransientDisconnectTimeout idsOfContributorsWithTransientDisconnectTimeout: Set<Contributor.ID>? = nil,
            contributors: [Contributor],
            logger: InternalLogger,
            clock: SimpleClock
        ) async {
            await self.init(
                status: status,
                pendingDiscontinuityEvents: pendingDiscontinuityEvents,
                idsOfContributorsWithTransientDisconnectTimeout: idsOfContributorsWithTransientDisconnectTimeout,
                contributors: contributors,
                logger: logger,
                clock: clock
            )
        }
    #endif

    private init(
        status: Status?,
        pendingDiscontinuityEvents: [Contributor.ID: DiscontinuityEvent]?,
        idsOfContributorsWithTransientDisconnectTimeout: Set<Contributor.ID>?,
        contributors: [Contributor],
        logger: InternalLogger,
        clock: SimpleClock
    ) async {
        self.status = status ?? .initialized
        self.contributors = contributors
        contributorAnnotations = .init(
            contributors: contributors,
            pendingDiscontinuityEvents: pendingDiscontinuityEvents ?? [:],
            idsOfContributorsWithTransientDisconnectTimeout: idsOfContributorsWithTransientDisconnectTimeout ?? []
        )
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
                        // We intentionally wait to finish processing one state change before moving on to the next; this means that when we process an ATTACHED state change, we can be sure that the current `hasBeenAttached` annotation correctly reflects the contributor’s previous state changes.
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
        case attachingDueToAttachOperation(attachOperationID: UUID)
        case attachingDueToRetryOperation(retryOperationID: UUID)
        case attachingDueToContributorStateChange(error: ARTErrorInfo?)
        case attached
        case detaching(detachOperationID: UUID)
        case detached
        case detachedDueToRetryOperation(retryOperationID: UUID)
        // `retryOperationTask` is exposed so that tests can wait for the triggered RETRY operation to complete.
        case suspendedAwaitingStartOfRetryOperation(retryOperationTask: Task<Void, Never>, error: ARTErrorInfo)
        case suspended(retryOperationID: UUID, error: ARTErrorInfo)
        // `rundownOperationTask` is exposed so that tests can wait for the triggered RUNDOWN operation to complete.
        case failedAwaitingStartOfRundownOperation(rundownOperationTask: Task<Void, Never>, error: ARTErrorInfo)
        case failedAndPerformingRundownOperation(rundownOperationID: UUID, error: ARTErrorInfo)
        case failed(error: ARTErrorInfo)
        case releasing(releaseOperationID: UUID)
        case released

        internal var toRoomStatus: RoomStatus {
            switch self {
            case .initialized:
                .initialized
            case .attachingDueToAttachOperation:
                .attaching(error: nil)
            case .attachingDueToRetryOperation:
                .attaching(error: nil)
            case let .attachingDueToContributorStateChange(error: error):
                .attaching(error: error)
            case .attached:
                .attached
            case .detaching:
                .detaching
            case .detached, .detachedDueToRetryOperation:
                .detached
            case let .suspendedAwaitingStartOfRetryOperation(_, error):
                .suspended(error: error)
            case let .suspended(_, error):
                .suspended(error: error)
            case let .failedAwaitingStartOfRundownOperation(_, error):
                .failed(error: error)
            case let .failedAndPerformingRundownOperation(_, error):
                .failed(error: error)
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
            case let .attachingDueToAttachOperation(attachOperationID):
                attachOperationID
            case let .attachingDueToRetryOperation(retryOperationID):
                retryOperationID
            case let .detaching(detachOperationID):
                detachOperationID
            case let .detachedDueToRetryOperation(retryOperationID):
                retryOperationID
            case let .releasing(releaseOperationID):
                releaseOperationID
            case let .suspended(retryOperationID, _):
                retryOperationID
            case let .failedAndPerformingRundownOperation(rundownOperationID, _):
                rundownOperationID
            case .initialized,
                 .attached,
                 .detached,
                 .failedAwaitingStartOfRundownOperation,
                 .failed,
                 .released,
                 .attachingDueToContributorStateChange,
                 .suspendedAwaitingStartOfRetryOperation:
                nil
            }
        }
    }

    // MARK: - Types for contributor annotations

    /// Stores manager state relating to a given contributor.
    private struct ContributorAnnotation {
        class TransientDisconnectTimeout: Identifiable {
            /// A unique identifier for this timeout. This allows test cases to assert that one timeout has not been replaced by another.
            var id = UUID()
            /// The task that sleeps until the timeout period passes and then performs the timeout’s side effects. This will be `nil` if you have created a transient disconnect timeout using the `testsOnly_idsOfContributorsWithTransientDisconnectTimeout` manager initializer parameter.
            var task: Task<Void, Error>?
        }

        var pendingDiscontinuityEvent: DiscontinuityEvent?
        var transientDisconnectTimeout: TransientDisconnectTimeout?
        /// Whether a state change to `ATTACHED` has already been observed for this contributor.
        var hasBeenAttached: Bool

        var hasTransientDisconnectTimeout: Bool {
            transientDisconnectTimeout != nil
        }
    }

    /// Provides a `Dictionary`-like interface for storing manager state about individual contributors.
    private struct ContributorAnnotations {
        private var storage: [Contributor.ID: ContributorAnnotation]

        init(
            contributors: [Contributor],
            pendingDiscontinuityEvents: [Contributor.ID: DiscontinuityEvent],
            idsOfContributorsWithTransientDisconnectTimeout: Set<Contributor.ID>
        ) {
            storage = contributors.reduce(into: [:]) { result, contributor in
                result[contributor.id] = .init(
                    pendingDiscontinuityEvent: pendingDiscontinuityEvents[contributor.id],
                    transientDisconnectTimeout: idsOfContributorsWithTransientDisconnectTimeout.contains(contributor.id) ? .init() : nil,
                    hasBeenAttached: false
                )
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
                newAnnotation.pendingDiscontinuityEvent = nil
                return newAnnotation
            }
        }
    }

    // MARK: - Room status and its changes

    internal var roomStatus: RoomStatus {
        status.toRoomStatus
    }

    internal func onRoomStatusChange(bufferingPolicy: BufferingPolicy) -> Subscription<RoomStatusChange> {
        return roomStatusChangeSubscriptions.create(bufferingPolicy: bufferingPolicy)
    }

    #if DEBUG
        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_onRoomStatusChange()`` method.
        private var statusChangeSubscriptions = SubscriptionStorage<StatusChange>()

        internal struct StatusChange {
            internal var current: Status
            internal var previous: Status
        }

        /// Allows tests to subscribe to changes to the manager’s internal status (which exposes more cases and additional metadata, compared to the ``RoomStatus`` exposed by ``onRoomStatusChange(bufferingPolicy:)``).
        internal func testsOnly_onStatusChange() -> Subscription<StatusChange> {
            return statusChangeSubscriptions.create(bufferingPolicy: .unbounded)
        }
    #endif

    /// Updates ``status`` and emits a status change event.
    private func changeStatus(to new: Status) {
        logger.log(message: "Transitioning from \(status) to \(new)", level: .info)
        let previous = status
        status = new

        // Avoid a double-emit of room status when changing between `Status` values that map to the same `RoomStatus`; e.g. when changing from `.suspendedAwaitingStartOfRetryOperation` to `.suspended`.
        if new.toRoomStatus != previous.toRoomStatus {
            let statusChange = RoomStatusChange(current: status.toRoomStatus, previous: previous.toRoomStatus)
            roomStatusChangeSubscriptions.emit(statusChange)
        }

        #if DEBUG
            let statusChange = StatusChange(current: status, previous: previous)
            statusChangeSubscriptions.emit(statusChange)
        #endif
    }

    // MARK: - Handling contributor state changes

    #if DEBUG
        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToHandledContributorStateChanges()`` method.
        private var stateChangeHandledSubscriptions = SubscriptionStorage<ARTChannelStateChange>()

        /// Returns a subscription which emits the contributor state changes that have been handled by the manager.
        ///
        /// A contributor state change is considered handled once the manager has performed all of the side effects that it will perform as a result of receiving this state change. Specifically, once:
        ///
        /// - (if the state change is ATTACHED) the manager has recorded that an ATTACHED state change has been observed for the contributor
        /// - the manager has recorded all pending discontinuity events provoked by the state change (you can retrieve these using ``testsOnly_pendingDiscontinuityEvent(for:)``)
        /// - the manager has performed all status changes provoked by the state change (this does _not_ include the case in which the state change provokes the creation of a transient disconnect timeout which subsequently provokes a status change; use ``testsOnly_subscribeToHandledTransientDisconnectTimeouts()`` to find out about those)
        /// - the manager has performed all contributor actions provoked by the state change, namely calls to ``RoomLifecycleContributorChannel/detach()`` or ``RoomLifecycleContributor/emitDiscontinuity(_:)``
        /// - the manager has recorded all transient disconnect timeouts provoked by the state change (you can retrieve this information using ``testsOnly_hasTransientDisconnectTimeout(for:) or ``testsOnly_idOfTransientDisconnectTimeout(for:)``)
        /// - the manager has performed all transient disconnect timeout cancellations provoked by the state change (you can retrieve this information using ``testsOnly_hasTransientDisconnectTimeout(for:) or ``testsOnly_idOfTransientDisconnectTimeout(for:)``)
        internal func testsOnly_subscribeToHandledContributorStateChanges() -> Subscription<ARTChannelStateChange> {
            return stateChangeHandledSubscriptions.create(bufferingPolicy: .unbounded)
        }

        internal func testsOnly_pendingDiscontinuityEvent(for contributor: Contributor) -> DiscontinuityEvent? {
            contributorAnnotations[contributor].pendingDiscontinuityEvent
        }

        internal func testsOnly_hasTransientDisconnectTimeout(for contributor: Contributor) -> Bool {
            contributorAnnotations[contributor].hasTransientDisconnectTimeout
        }

        internal var testsOnly_hasTransientDisconnectTimeoutForAnyContributor: Bool {
            contributors.contains { testsOnly_hasTransientDisconnectTimeout(for: $0) }
        }

        internal func testsOnly_idOfTransientDisconnectTimeout(for contributor: Contributor) -> UUID? {
            contributorAnnotations[contributor].transientDisconnectTimeout?.id
        }

        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToHandledTransientDisconnectTimeouts()`` method.
        private var transientDisconnectTimeoutHandledSubscriptions = SubscriptionStorage<UUID>()

        /// Returns a subscription which emits the IDs of the transient disconnect timeouts that have been handled by the manager.
        ///
        /// A transient disconnect timeout is considered handled once the manager has performed all of the side effects that it will perform as a result of creating this timeout. Specifically, once:
        ///
        /// - the manager has performed all status changes provoked by the completion of this timeout (which may be none, if the timeout gets cancelled)
        internal func testsOnly_subscribeToHandledTransientDisconnectTimeouts() -> Subscription<UUID> {
            return transientDisconnectTimeoutHandledSubscriptions.create(bufferingPolicy: .unbounded)
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

            // CHA-RL4a2 — if contributor has not yet been attached then no-op
            guard contributorAnnotations[contributor].hasBeenAttached else {
                break
            }

            let reason = stateChange.reason

            if hasOperationInProgress {
                // CHA-RL4a3
                recordPendingDiscontinuityEvent(for: contributor, error: reason)
            } else {
                // CHA-RL4a4
                let discontinuity = DiscontinuityEvent(error: reason)
                logger.log(message: "Emitting discontinuity event \(discontinuity) for contributor \(contributor)", level: .info)

                await contributor.emitDiscontinuity(discontinuity)
            }
        case .attached:
            let hadAlreadyAttached = contributorAnnotations[contributor].hasBeenAttached
            contributorAnnotations[contributor].hasBeenAttached = true

            if hasOperationInProgress {
                if !stateChange.resumed, hadAlreadyAttached {
                    // CHA-RL4b1
                    recordPendingDiscontinuityEvent(for: contributor, error: stateChange.reason)
                }
            } else {
                // CHA-RL4b10
                clearTransientDisconnectTimeouts(for: contributor)

                if status != .attached {
                    if await (contributors.async.map { await $0.channel.state }.allSatisfy { $0 == .attached }) {
                        // CHA-RL4b8
                        logger.log(message: "Now that all contributors are ATTACHED, transitioning room to ATTACHED", level: .info)
                        changeStatus(to: .attached)
                    }
                }
            }
        case .failed:
            if !hasOperationInProgress {
                // CHA-RL4b5
                guard let reason = stateChange.reason else {
                    // TODO: Decide the right thing to do here (https://github.com/ably-labs/ably-chat-swift/issues/74)
                    preconditionFailure("FAILED state change event should have a reason")
                }

                clearTransientDisconnectTimeouts()
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

                clearTransientDisconnectTimeouts()

                // My understanding is that, since this task is being created inside an actor’s synchronous code, the two .suspended* statuses will always come in the right order; i.e. first .suspendedAwaitingStartOfRetryOperation and then .suspended.
                let retryOperationTask = scheduleAnOperation(
                    kind: .retry(
                        triggeringContributor: contributor,
                        errorForSuspendedStatus: reason
                    )
                )
                changeStatus(to: .suspendedAwaitingStartOfRetryOperation(retryOperationTask: retryOperationTask, error: reason))
            }
        case .attaching:
            if !hasOperationInProgress, !contributorAnnotations[contributor].hasTransientDisconnectTimeout {
                // CHA-RL4b7
                let transientDisconnectTimeout = ContributorAnnotation.TransientDisconnectTimeout()
                contributorAnnotations[contributor].transientDisconnectTimeout = transientDisconnectTimeout
                logger.log(message: "Starting transient disconnect timeout \(transientDisconnectTimeout.id) for \(contributor)", level: .debug)
                transientDisconnectTimeout.task = Task {
                    do {
                        try await clock.sleep(timeInterval: 5)
                    } catch {
                        logger.log(message: "Transient disconnect timeout \(transientDisconnectTimeout.id) for \(contributor) was interrupted, error \(error)", level: .debug)

                        #if DEBUG
                            emitTransientDisconnectTimeoutHandledEventForTimeoutWithID(transientDisconnectTimeout.id)
                        #endif

                        return
                    }
                    logger.log(message: "Transient disconnect timeout \(transientDisconnectTimeout.id) for \(contributor) completed", level: .debug)
                    contributorAnnotations[contributor].transientDisconnectTimeout = nil
                    changeStatus(to: .attachingDueToContributorStateChange(error: stateChange.reason))

                    #if DEBUG
                        emitTransientDisconnectTimeoutHandledEventForTimeoutWithID(transientDisconnectTimeout.id)
                    #endif
                }
            }
        default:
            break
        }

        #if DEBUG
            logger.log(message: "Emitting state change handled event for \(stateChange)", level: .debug)
            stateChangeHandledSubscriptions.emit(stateChange)
        #endif
    }

    #if DEBUG
        private func emitTransientDisconnectTimeoutHandledEventForTimeoutWithID(_ id: UUID) {
            logger.log(message: "Emitting transient disconnect timeout handled event for \(id)", level: .debug)
            transientDisconnectTimeoutHandledSubscriptions.emit(id)
        }
    #endif

    private func clearTransientDisconnectTimeouts(for contributor: Contributor) {
        guard let transientDisconnectTimeout = contributorAnnotations[contributor].transientDisconnectTimeout else {
            return
        }

        logger.log(message: "Clearing transient disconnect timeout \(transientDisconnectTimeout.id) for \(contributor)", level: .debug)
        transientDisconnectTimeout.task?.cancel()
        contributorAnnotations[contributor].transientDisconnectTimeout = nil
    }

    private func clearTransientDisconnectTimeouts() {
        for contributor in contributors {
            clearTransientDisconnectTimeouts(for: contributor)
        }
    }

    private func recordPendingDiscontinuityEvent(for contributor: Contributor, error: ARTErrorInfo?) {
        // CHA-RL4a3, and I have assumed that the same behaviour is expected in CHA-RL4b1 too (https://github.com/ably/specification/pull/246 proposes this change).
        guard contributorAnnotations[contributor].pendingDiscontinuityEvent == nil else {
            logger.log(message: "Error \(String(describing: error)) will not replace existing pending discontinuity event for contributor \(contributor)", level: .info)
            return
        }

        let discontinuity = DiscontinuityEvent(error: error)
        logger.log(message: "Recording pending discontinuity event \(discontinuity) for contributor \(contributor)", level: .info)
        contributorAnnotations[contributor].pendingDiscontinuityEvent = discontinuity
    }

    // MARK: - Operation handling

    /// Whether the room lifecycle manager currently has a room lifecycle operation in progress.
    ///
    /// - Warning: I haven’t yet figured out the exact meaning of “has an operation in progress” — at what point is an operation considered to be no longer in progress? Is it the point at which the operation has updated the manager’s status to one that no longer indicates an in-progress operation (this is the meaning currently used by `hasOperationInProgress`)? Or is it the point at which the `bodyOf*Operation` method for that operation exits (i.e. the point at which ``performAnOperation(_:)`` considers the operation to have completed)? Does it matter? I’ve chosen to not think about this very much right now, but might need to revisit. See TODO against `emitPendingDiscontinuityEvents` in `performAttachmentCycle` for an example of something where these two notions of “has an operation in progress” are not equivalent.
    private var hasOperationInProgress: Bool {
        status.operationID != nil
    }

    /// Stores bookkeeping information needed for allowing one operation to await the result of another.
    private struct OperationResultContinuations {
        typealias Continuation = CheckedContinuation<Result<Void, ARTErrorInfo>, Never>

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
            internal var waitingOperationID: UUID?
            /// The ID of the operation whose completion will be awaited.
            internal var waitedOperationID: UUID
        }

        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToOperationWaitEvents()`` method.
        private var operationWaitEventSubscriptions = SubscriptionStorage<OperationWaitEvent>()

        /// Returns a subscription which emits an event each time one room lifecycle operation is going to wait for another to complete.
        internal func testsOnly_subscribeToOperationWaitEvents() -> Subscription<OperationWaitEvent> {
            return operationWaitEventSubscriptions.create(bufferingPolicy: .unbounded)
        }
    #endif

    private enum OperationWaitRequester {
        case anotherOperation(operationID: UUID)
        case waitToBeAbleToPerformPresenceOperations

        internal var loggingDescription: String {
            switch self {
            case let .anotherOperation(operationID):
                "Operation \(operationID)"
            case .waitToBeAbleToPerformPresenceOperations:
                "waitToBeAbleToPerformPresenceOperations"
            }
        }

        internal var waitingOperationID: UUID? {
            switch self {
            case let .anotherOperation(operationID):
                operationID
            case .waitToBeAbleToPerformPresenceOperations:
                nil
            }
        }
    }

    /// Waits for the operation with ID `waitedOperationID` to complete, re-throwing any error thrown by that operation.
    ///
    /// Note that this method currently treats all waited operations as throwing. If you wish to wait for an operation that you _know_ to be non-throwing (which the RELEASE operation currently is) then you’ll need to call this method with `try!` or equivalent. (It might be possible to improve this in the future, but I didn’t want to put much time into figuring it out.)
    ///
    /// It is guaranteed that if you call this method from a manager-isolated method, and subsequently call ``operationWithID(_:,didCompleteWithResult:)`` from another manager-isolated method, then the call to this method will return.
    ///
    /// - Parameters:
    ///   - waitedOperationID: The ID of the operation whose completion will be awaited.
    ///   - requester: A description of who is awaiting this result. Only used for logging.
    private func waitForCompletionOfOperationWithID(
        _ waitedOperationID: UUID,
        requester: OperationWaitRequester
    ) async throws(ARTErrorInfo) {
        logger.log(message: "\(requester.loggingDescription) started waiting for result of operation \(waitedOperationID)", level: .debug)

        do {
            let result = await withCheckedContinuation { (continuation: OperationResultContinuations.Continuation) in
                // My “it is guaranteed” in the documentation for this method is really more of an “I hope that”, because it’s based on my pretty vague understanding of Swift concurrency concepts; namely, I believe that if you call this manager-isolated `async` method from another manager-isolated method, the initial synchronous part of this method — in particular the call to `addContinuation` below — will occur _before_ the call to this method suspends. (I think this can be roughly summarised as “calls to async methods on self don’t do actor hopping” but I could be completely misusing a load of Swift concurrency vocabulary there.)
                operationResultContinuations.addContinuation(continuation, forResultOfOperationWithID: waitedOperationID)

                #if DEBUG
                    let operationWaitEvent = OperationWaitEvent(waitingOperationID: requester.waitingOperationID, waitedOperationID: waitedOperationID)
                    operationWaitEventSubscriptions.emit(operationWaitEvent)
                #endif
            }

            try result.get()

            logger.log(message: "\(requester.loggingDescription) completed waiting for result of operation \(waitedOperationID), which completed successfully", level: .debug)
        } catch {
            logger.log(message: "\(requester.loggingDescription) completed waiting for result of operation \(waitedOperationID), which threw error \(error)", level: .debug)
            throw error
        }
    }

    /// Operations should call this when they have completed, in order to complete any waits initiated by ``waitForCompletionOfOperationWithID(_:waitingOperationID:)``.
    private func operationWithID(_ operationID: UUID, didCompleteWithResult result: Result<Void, ARTErrorInfo>) {
        logger.log(message: "Operation \(operationID) completed with result \(result)", level: .debug)
        let continuationsToResume = operationResultContinuations.removeContinuationsForResultOfOperationWithID(operationID)

        for continuation in continuationsToResume {
            continuation.resume(returning: result)
        }
    }

    /// Executes a function that represents a room lifecycle operation.
    ///
    /// - Note: Note that `DefaultRoomLifecycleManager` does not implement any sort of mutual exclusion mechanism that _enforces_ that one room lifecycle operation must wait for another (e.g. it is _not_ a queue); each operation needs to implement its own logic for whether it should proceed in the presence of other in-progress operations.
    ///
    /// Note that this method currently treats all performed operations as throwing. If you wish to wait for an operation that you _know_ to be non-throwing (which the RELEASE operation currently is) then you’ll need to call this method with `try!` or equivalent. (It might be possible to improve this in the future, but I didn’t want to put much time into figuring it out.)
    ///
    /// - Parameters:
    ///   - forcedOperationID: Forces the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    ///   - body: The implementation of the operation to be performed. Once this function returns or throws an error, the operation is considered to have completed, and any waits for this operation’s completion initiated via ``waitForCompletionOfOperationWithID(_:waitingOperationID:)`` will complete.
    private func performAnOperation(
        forcingOperationID forcedOperationID: UUID?,
        _ body: (UUID) async throws(ARTErrorInfo) -> Void
    ) async throws(ARTErrorInfo) {
        let operationID = forcedOperationID ?? UUID()
        logger.log(message: "Performing operation \(operationID)", level: .debug)
        let result: Result<Void, ARTErrorInfo>
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

    /// The kinds of operation that you can schedule using ``scheduleAnOperation(kind:)``.
    private enum OperationKind {
        /// The RETRY operation.
        case retry(triggeringContributor: Contributor, errorForSuspendedStatus: ARTErrorInfo)
        /// The RUNDOWN operation.
        case rundown(errorForFailedStatus: ARTErrorInfo)
    }

    /// Requests that a room lifecycle operation be performed asynchronously.
    private func scheduleAnOperation(kind: OperationKind) -> Task<Void, Never> {
        logger.log(message: "Scheduling operation \(kind)", level: .debug)
        return Task {
            logger.log(message: "Performing scheduled operation \(kind)", level: .debug)
            switch kind {
            case let .retry(triggeringContributor, errorForSuspendedStatus):
                await performRetryOperation(
                    triggeredByContributor: triggeringContributor,
                    errorForSuspendedStatus: errorForSuspendedStatus
                )
            case let .rundown(errorForFailedStatus):
                await performRundownOperation(
                    errorForFailedStatus: errorForFailedStatus
                )
            }
        }
    }

    // MARK: - ATTACH operation

    internal func performAttachOperation() async throws {
        try await _performAttachOperation(forcingOperationID: nil)
    }

    internal func performAttachOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async throws {
        try await _performAttachOperation(forcingOperationID: forcedOperationID)
    }

    /// Implements CHA-RL1’s `ATTACH` operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    private func _performAttachOperation(forcingOperationID forcedOperationID: UUID?) async throws {
        try await performAnOperation(forcingOperationID: forcedOperationID) { operationID throws(ARTErrorInfo) in
            try await bodyOfAttachOperation(operationID: operationID)
        }
    }

    private func bodyOfAttachOperation(operationID: UUID) async throws(ARTErrorInfo) {
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
        case .initialized, .suspendedAwaitingStartOfRetryOperation, .suspended, .attachingDueToAttachOperation, .attachingDueToRetryOperation, .attachingDueToContributorStateChange, .detached, .detachedDueToRetryOperation, .detaching, .failed, .failedAwaitingStartOfRundownOperation, .failedAndPerformingRundownOperation:
            break
        }

        // CHA-RL1d
        if let currentOperationID = status.operationID {
            try? await waitForCompletionOfOperationWithID(currentOperationID, requester: .anotherOperation(operationID: operationID))
        }

        // CHA-RL1e
        changeStatus(to: .attachingDueToAttachOperation(attachOperationID: operationID))

        try await performAttachmentCycle()
    }

    /// Performs the “CHA-RL1e attachment cycle”, to use the terminology of CHA-RL5f.
    private func performAttachmentCycle() async throws(ARTErrorInfo) {
        // CHA-RL1f
        for contributor in contributors {
            do {
                logger.log(message: "Attaching contributor \(contributor)", level: .info)
                try await contributor.channel.attach()
                logger.log(message: "Successfully attached contributor \(contributor)", level: .info)
            } catch let contributorAttachError {
                let contributorState = await contributor.channel.state
                logger.log(message: "Failed to attach contributor \(contributor), which is now in state \(contributorState), error \(contributorAttachError)", level: .info)

                switch contributorState {
                case .suspended:
                    // CHA-RL1h2
                    let error = ARTErrorInfo(chatError: .attachmentFailed(feature: contributor.feature, underlyingError: contributorAttachError))

                    // CHA-RL1h3
                    // My understanding is that, since this task is being created inside an actor’s synchronous code, the two .suspended* statuses will always come in the right order; i.e. first .suspendedAwaitingStartOfRetryOperation and then .suspended.
                    let retryOperationTask = scheduleAnOperation(
                        kind: .retry(
                            triggeringContributor: contributor,
                            errorForSuspendedStatus: error
                        )
                    )
                    changeStatus(to: .suspendedAwaitingStartOfRetryOperation(retryOperationTask: retryOperationTask, error: error))
                    throw error
                case .failed:
                    let error = ARTErrorInfo(chatError: .attachmentFailed(feature: contributor.feature, underlyingError: contributorAttachError))

                    // CHA-RL1h5
                    // My understanding is that, since this task is being created inside an actor’s synchronous code, the two .failed* statuses will always come in the right order; i.e. first .failedAwaitingStartOfRundownOperation and then .failedAndPerformingRundownOperation.
                    let rundownOperationTask = scheduleAnOperation(
                        kind: .rundown(
                            errorForFailedStatus: error
                        )
                    )

                    // CHA-RL1h4
                    changeStatus(to: .failedAwaitingStartOfRundownOperation(rundownOperationTask: rundownOperationTask, error: error))
                    throw error
                default:
                    // TODO: The spec assumes the channel will be in one of the above states, but working in a multi-threaded environment means it might not be (https://github.com/ably-labs/ably-chat-swift/issues/49)
                    preconditionFailure("Attach failure left contributor in unexpected state \(contributorState)")
                }
            }
        }

        // CHA-RL1g3
        clearTransientDisconnectTimeouts()

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
            if let pendingDiscontinuityEvent = contributorAnnotations[contributor].pendingDiscontinuityEvent {
                logger.log(message: "Emitting pending discontinuity event \(String(describing: pendingDiscontinuityEvent)) to contributor \(contributor)", level: .info)
                await contributor.emitDiscontinuity(pendingDiscontinuityEvent)
            }
        }

        contributorAnnotations.clearPendingDiscontinuityEvents()
    }

    // MARK: - DETACH operation

    internal func performDetachOperation() async throws {
        try await _performDetachOperation(forcingOperationID: nil)
    }

    internal func performDetachOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async throws {
        try await _performDetachOperation(forcingOperationID: forcedOperationID)
    }

    /// Implements CHA-RL2’s DETACH operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    private func _performDetachOperation(forcingOperationID forcedOperationID: UUID?) async throws {
        try await performAnOperation(forcingOperationID: forcedOperationID) { operationID throws(ARTErrorInfo) in
            try await bodyOfDetachOperation(operationID: operationID)
        }
    }

    private func bodyOfDetachOperation(operationID: UUID) async throws(ARTErrorInfo) {
        switch status {
        case .detached, .detachedDueToRetryOperation:
            // CHA-RL2a
            return
        case .releasing:
            // CHA-RL2b
            throw ARTErrorInfo(chatError: .roomIsReleasing)
        case .released:
            // CHA-RL2c
            throw ARTErrorInfo(chatError: .roomIsReleased)
        case .failed, .failedAwaitingStartOfRundownOperation, .failedAndPerformingRundownOperation:
            // CHA-RL2d
            throw ARTErrorInfo(chatError: .roomInFailedState)
        case .initialized, .suspendedAwaitingStartOfRetryOperation, .suspended, .attachingDueToAttachOperation, .attachingDueToRetryOperation, .attachingDueToContributorStateChange, .attached, .detaching:
            break
        }

        // CHA-RL2e
        clearTransientDisconnectTimeouts()
        changeStatus(to: .detaching(detachOperationID: operationID))

        try await performDetachmentCycle(trigger: .detachOperation)
    }

    /// Describes the reason a CHA-RL2f detachment cycle is being performed.
    private enum DetachmentCycleTrigger {
        case detachOperation
        case retryOperation(retryOperationID: UUID, triggeringContributor: Contributor)

        /// Given a CHA-RL2f detachment cycle triggered by this trigger, returns the DETACHED status to which the room should transition per CHA-RL2g.
        var detachedStatus: Status {
            switch self {
            case .detachOperation:
                .detached
            case let .retryOperation(retryOperationID, _):
                .detachedDueToRetryOperation(retryOperationID: retryOperationID)
            }
        }
    }

    /// Performs the “CHA-RL2f detachment cycle”, to use the terminology of CHA-RL5a.
    private func performDetachmentCycle(trigger: DetachmentCycleTrigger) async throws(ARTErrorInfo) {
        // CHA-RL2f
        var firstDetachError: ARTErrorInfo?
        for contributor in contributorsForDetachmentCycle(trigger: trigger) {
            logger.log(message: "Detaching contributor \(contributor)", level: .info)
            do {
                try await contributor.channel.detach()
            } catch {
                let contributorState = await contributor.channel.state
                logger.log(message: "Failed to detach contributor \(contributor), which is now in state \(contributorState), error \(error)", level: .info)

                switch contributorState {
                case .failed:
                    // CHA-RL2h1
                    let error = ARTErrorInfo(chatError: .detachmentFailed(feature: contributor.feature, underlyingError: error))

                    if firstDetachError == nil {
                        // We’ll throw this after we’ve tried detaching all the channels
                        firstDetachError = error
                    }

                    // This check is CHA-RL2h2
                    if !status.toRoomStatus.isFailed {
                        changeStatus(to: .failed(error: error))
                    }
                default:
                    // CHA-RL2h3: Retry until detach succeeds, with a pause before each attempt
                    while true {
                        do {
                            let waitDuration = 0.25
                            logger.log(message: "Will attempt to detach non-failed contributor \(contributor) in \(waitDuration)s.", level: .info)
                            try await clock.sleep(timeInterval: waitDuration)
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
        changeStatus(to: trigger.detachedStatus)
    }

    /// Returns the contributors that should be detached in a CHA-RL2f detachment cycle.
    private func contributorsForDetachmentCycle(trigger: DetachmentCycleTrigger) -> [Contributor] {
        switch trigger {
        case .detachOperation:
            // CHA-RL2f
            contributors
        case let .retryOperation(_, triggeringContributor):
            // CHA-RL5a
            contributors.filter { $0.id != triggeringContributor.id }
        }
    }

    // MARK: - RELEASE operation

    internal func performReleaseOperation() async {
        await _performReleaseOperation(forcingOperationID: nil)
    }

    internal func performReleaseOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil) async {
        await _performReleaseOperation(forcingOperationID: forcedOperationID)
    }

    /// Implements CHA-RL3’s RELEASE operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    internal func _performReleaseOperation(forcingOperationID forcedOperationID: UUID? = nil) async {
        // See note on performAnOperation for the current need for this force try
        // swiftlint:disable:next force_try
        try! await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            await bodyOfReleaseOperation(operationID: operationID)
        }
    }

    private func bodyOfReleaseOperation(operationID: UUID) async {
        switch status {
        case .released:
            // CHA-RL3a
            return
        case
            // CHA-RL3b
            .detached, .detachedDueToRetryOperation,
            // CHA-RL3j
            .initialized:
            changeStatus(to: .released)
            return
        case let .releasing(releaseOperationID):
            // CHA-RL3c
            // See note on waitForCompletionOfOperationWithID for the current need for this force try
            // swiftlint:disable:next force_try
            return try! await waitForCompletionOfOperationWithID(releaseOperationID, requester: .anotherOperation(operationID: operationID))
        case .attached, .attachingDueToAttachOperation, .attachingDueToRetryOperation, .attachingDueToContributorStateChange, .detaching, .suspendedAwaitingStartOfRetryOperation, .suspended, .failed, .failedAwaitingStartOfRundownOperation, .failedAndPerformingRundownOperation:
            break
        }

        // CHA-RL3l
        clearTransientDisconnectTimeouts()
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
                    let waitDuration = 0.25
                    logger.log(message: "Failed to detach contributor \(contributor), error \(error). Will retry in \(waitDuration)s.", level: .info)
                    // TODO: Make this not trap in the case where the Task is cancelled (as part of the broader https://github.com/ably-labs/ably-chat-swift/issues/29 for handling task cancellation)
                    // swiftlint:disable:next force_try
                    try! await clock.sleep(timeInterval: waitDuration)
                    // Loop repeats
                }
            }
        }

        // CHA-RL3g
        changeStatus(to: .released)
    }

    // MARK: - RETRY operation

    /// Implements CHA-RL5’s RETRY operation.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    ///   - triggeringContributor: This is, in the language of CHA-RL5a, “the channel that became SUSPENDED”.
    internal func performRetryOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil, triggeredByContributor triggeringContributor: Contributor, errorForSuspendedStatus: ARTErrorInfo) async {
        // See note on performAnOperation for the current need for this force try
        // swiftlint:disable:next force_try
        try! await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            await bodyOfRetryOperation(
                operationID: operationID,
                triggeredByContributor: triggeringContributor,
                errorForSuspendedStatus: errorForSuspendedStatus
            )
        }
    }

    private func bodyOfRetryOperation(
        operationID: UUID,
        triggeredByContributor triggeringContributor: Contributor,
        errorForSuspendedStatus: ARTErrorInfo
    ) async {
        changeStatus(to: .suspended(retryOperationID: operationID, error: errorForSuspendedStatus))

        // CHA-RL5a
        do {
            try await performDetachmentCycle(
                trigger: .retryOperation(
                    retryOperationID: operationID,
                    triggeringContributor: triggeringContributor
                )
            )
        } catch {
            logger.log(message: "RETRY’s detachment cycle failed with error \(error). Ending RETRY.", level: .debug)
            return
        }

        // CHA-RL5d
        do {
            try await waitForContributorThatTriggeredRetryToBecomeAttached(triggeringContributor)
        } catch {
            // CHA-RL5e
            logger.log(message: "RETRY’s waiting for triggering contributor to attach failed with error \(error). Ending RETRY.", level: .debug)
            return
        }

        // CHA-RL5f
        changeStatus(to: .attachingDueToRetryOperation(retryOperationID: operationID))
        do {
            try await performAttachmentCycle()
        } catch {
            logger.log(message: "RETRY’s attachment cycle failed with error \(error). Ending RETRY.", level: .debug)
            return
        }
    }

    /// Performs CHA-RL5d’s “the room waits until the original channel that caused the retry loop naturally enters the ATTACHED state”.
    ///
    /// Throws an error if the room enters the FAILED status, which is considered terminal by the RETRY operation.
    private func waitForContributorThatTriggeredRetryToBecomeAttached(_ triggeringContributor: Contributor) async throws {
        logger.log(message: "RETRY waiting for \(triggeringContributor) to enter ATTACHED", level: .debug)

        let handleState = { [self] (state: ARTRealtimeChannelState, associatedError: ARTErrorInfo?) in
            switch state {
            // CHA-RL5d
            case .attached:
                logger.log(message: "RETRY completed waiting for \(triggeringContributor) to enter ATTACHED", level: .debug)
                return true
            // CHA-RL5e
            case .failed:
                guard let associatedError else {
                    preconditionFailure("Contributor entered FAILED but there’s no associated error")
                }
                logger.log(message: "RETRY failed waiting for \(triggeringContributor) to enter ATTACHED, since it entered FAILED with error \(associatedError)", level: .debug)

                changeStatus(to: .failed(error: associatedError))
                throw associatedError
            case .attaching, .detached, .detaching, .initialized, .suspended:
                return false
            @unknown default:
                return false
            }
        }

        // Check whether the contributor is already in one of the states that we’re going to wait for. CHA-RL5d doesn’t make this check explicit but it seems like the right thing to do (asked in https://github.com/ably/specification/issues/221).
        // TODO: this assumes that if you fetch a channel’s `state` and then its `errorReason`, they will both refer to the same channel state; this may not be true due to threading, address in https://github.com/ably-labs/ably-chat-swift/issues/49
        if try await handleState(triggeringContributor.channel.state, triggeringContributor.channel.errorReason) {
            return
        }

        // TODO: this assumes that if you check a channel’s state, and it’s x, and you then immediately add a state listener, you’ll definitely find out if the channel changes to a state other than x; this may not be true due to threading, address in https://github.com/ably-labs/ably-chat-swift/issues/49
        for await stateChange in await triggeringContributor.channel.subscribeToState() {
            // (I prefer this way of writing it, in this case)
            // swiftlint:disable:next for_where
            if try handleState(stateChange.current, stateChange.reason) {
                return
            }
        }
    }

    // MARK: - RUNDOWN operation

    /// Implements the RUNDOWN operation.
    ///
    /// This operation is not currently in the specification, but it comes from my suggestion in https://github.com/ably/specification/issues/253 for how to handle the fact that the spec, as currently written, does not guarantee that the CHA-RL1h5 detach behaviour is performed atomically with respect to room lifecycle operations. TODO bring in line with spec once spec updated.
    ///
    /// - Parameters:
    ///   - forcedOperationID: Allows tests to force the operation to have a given ID. In combination with the ``testsOnly_subscribeToOperationWaitEvents`` API, this allows tests to verify that one test-initiated operation is waiting for another test-initiated operation.
    internal func performRundownOperation(testsOnly_forcingOperationID forcedOperationID: UUID? = nil, errorForFailedStatus: ARTErrorInfo) async {
        // See note on performAnOperation for the current need for this force try
        // swiftlint:disable:next force_try
        try! await performAnOperation(forcingOperationID: forcedOperationID) { operationID in
            await bodyOfRundownOperation(
                operationID: operationID,
                errorForFailedStatus: errorForFailedStatus
            )
        }
    }

    private func bodyOfRundownOperation(
        operationID: UUID,
        errorForFailedStatus: ARTErrorInfo
    ) async {
        changeStatus(to: .failedAndPerformingRundownOperation(rundownOperationID: operationID, error: errorForFailedStatus))

        // CHA-RL1h5
        await detachNonFailedContributors()

        changeStatus(to: .failed(error: errorForFailedStatus))
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

    // MARK: - Waiting to be able to perform presence operations

    internal func waitToBeAbleToPerformPresenceOperations(requestedByFeature requester: RoomFeature) async throws(ARTErrorInfo) {
        // Although this method’s implementation only uses the manager’s public
        // API, it’s implemented as a method on the manager itself, so that the
        // implementation is isolated to the manager and hence doesn’t “miss”
        // any status changes. (There may be other ways to achieve the same
        // effect; can revisit.)

        switch status.toRoomStatus {
        case .attaching:
            // CHA-RL9, which is invoked by CHA-PR3d, CHA-PR10d, CHA-PR6c, CHA-T2c

            // CHA-RL9a
            let subscription = onRoomStatusChange(bufferingPolicy: .unbounded)
            logger.log(message: "waitToBeAbleToPerformPresenceOperations waiting for status change", level: .debug)
            #if DEBUG
            statusChangeWaitEventSubscriptions.emit(.init())
            #endif
            let nextRoomStatusChange = await (subscription.first { _ in true })
            logger.log(message: "waitToBeAbleToPerformPresenceOperations got status change \(String(describing: nextRoomStatusChange))", level: .debug)

            // CHA-RL9b
            // TODO: decide what to do if nextRoomStatusChange is nil; I believe that this will happen if the current Task is cancelled. For now, will just treat it as an invalid status change. Handle it properly in https://github.com/ably-labs/ably-chat-swift/issues/29
            if nextRoomStatusChange?.current != .attached {
                // CHA-RL9c
                throw .init(chatError: .roomTransitionedToInvalidStateForPresenceOperation(cause: nextRoomStatusChange?.current.error))
            }
        case .attached:
            // CHA-PR3e, CHA-PR10e, CHA-PR6d, CHA-T2d
            break
        default:
            // CHA-PR3h, CHA-PR10h, CHA-PR6h, CHA-T2g
            throw .init(chatError: .presenceOperationRequiresRoomAttach(feature: requester))
        }
    }

    #if DEBUG
        /// The manager emits a `StatusChangeWaitEvent` each time ``waitToBeAbleToPerformPresenceOperations(requestedByFeature:)`` is going to wait for a room status change. These events are emitted to support testing of the manager; see ``testsOnly_subscribeToStatusChangeWaitEvents``.
        internal struct StatusChangeWaitEvent: Equatable {
            // Nothing here currently, just created this type for consistency with OperationWaitEvent
        }

        // TODO: clean up old subscriptions (https://github.com/ably-labs/ably-chat-swift/issues/36)
        /// Supports the ``testsOnly_subscribeToStatusChangeWaitEvents()`` method.
        private var statusChangeWaitEventSubscriptions = SubscriptionStorage<StatusChangeWaitEvent>()

        /// Returns a subscription which emits an event each time ``waitToBeAbleToPerformPresenceOperations(requestedByFeature:)`` is going to wait for a room status change.
        internal func testsOnly_subscribeToStatusChangeWaitEvents() -> Subscription<StatusChangeWaitEvent> {
            return statusChangeWaitEventSubscriptions.create(bufferingPolicy: .unbounded)
        }
    #endif
}
