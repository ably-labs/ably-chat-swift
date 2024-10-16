@preconcurrency import Ably
@testable import AblyChat
import Testing

struct RoomLifecycleManagerTests {
    // MARK: - Test helpers

    /// A mock implementation of a realtime channel’s `attach` or `detach` operation. Its ``complete(result:)`` method allows you to signal to the mock that the mocked operation should complete with a given result.
    final class SignallableChannelOperation: Sendable {
        private let continuation: AsyncStream<MockRoomLifecycleContributorChannel.AttachOrDetachResult>.Continuation

        /// When this behavior is set as a ``MockRealtimeChannel``’s `attachBehavior` or `detachBehavior`, calling ``complete(result:)`` will cause the corresponding channel operation to complete with the result passed to that method.
        let behavior: MockRoomLifecycleContributorChannel.AttachOrDetachBehavior

        init() {
            let (stream, continuation) = AsyncStream.makeStream(of: MockRoomLifecycleContributorChannel.AttachOrDetachResult.self)
            self.continuation = continuation

            behavior = .fromFunction { _ in
                await (stream.first { _ in true })!
            }
        }

        /// Causes the async function embedded in ``behavior`` to return with the given result.
        func complete(result: MockRoomLifecycleContributorChannel.AttachOrDetachResult) {
            continuation.yield(result)
        }
    }

    private func createManager(
        forTestingWhatHappensWhenCurrentlyIn status: RoomLifecycleManager<MockRoomLifecycleContributor>.Status? = nil,
        forTestingWhatHappensWhenHasPendingDiscontinuityEvents pendingDiscontinuityEvents: [MockRoomLifecycleContributor.ID: [ARTErrorInfo]]? = nil,
        contributors: [MockRoomLifecycleContributor] = [],
        clock: SimpleClock = MockSimpleClock()
    ) async -> RoomLifecycleManager<MockRoomLifecycleContributor> {
        await .init(
            testsOnly_status: status,
            testsOnly_pendingDiscontinuityEvents: pendingDiscontinuityEvents,
            contributors: contributors,
            logger: TestLogger(),
            clock: clock
        )
    }

    private func createContributor(
        initialState: ARTRealtimeChannelState = .initialized,
        feature: RoomFeature = .messages, // Arbitrarily chosen, its value only matters in test cases where we check which error is thrown
        attachBehavior: MockRoomLifecycleContributorChannel.AttachOrDetachBehavior? = nil,
        detachBehavior: MockRoomLifecycleContributorChannel.AttachOrDetachBehavior? = nil
    ) -> MockRoomLifecycleContributor {
        .init(
            feature: feature,
            channel: .init(
                initialState: initialState,
                attachBehavior: attachBehavior,
                detachBehavior: detachBehavior
            )
        )
    }

    /// Given a room lifecycle manager and a channel state change, this method will return once the manager has performed all of the side effects that it will perform as a result of receiving this state change. You can provide a function which will be called after ``waitForManager`` has started listening for the manager’s “state change handled” notifications.
    func waitForManager(_ manager: RoomLifecycleManager<some RoomLifecycleContributor>, toHandleContributorStateChange stateChange: ARTChannelStateChange, during action: () async -> Void) async {
        let subscription = await manager.testsOnly_subscribeToHandledContributorStateChanges()
        async let handledSignal = subscription.first { $0 === stateChange }
        await action()
        _ = await handledSignal
    }

    // MARK: - Initial state

    // @spec CHA-RS2a
    // @spec CHA-RS3
    @Test
    func current_startsAsInitialized() async {
        let manager = await createManager()

        #expect(await manager.current == .initialized)
    }

    // MARK: - ATTACH operation

    // @spec CHA-RL1a
    @Test
    func attach_whenAlreadyAttached() async throws {
        // Given: A RoomLifecycleManager in the ATTACHED state
        let contributor = createContributor()
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .attached, contributors: [contributor])

        // When: `performAttachOperation()` is called on the lifecycle manager
        try await manager.performAttachOperation()

        // Then: The room attach operation succeeds, and no attempt is made to attach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.attachCallCount == 0)
    }

    // @spec CHA-RL1b
    @Test
    func attach_whenReleasing() async throws {
        // Given: A RoomLifecycleManager in the RELEASING state
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .releasing(releaseOperationID: UUID() /* arbitrary */ )
        )

        // When: `performAttachOperation()` is called on the lifecycle manager
        // Then: It throws a roomIsReleasing error
        await #expect {
            try await manager.performAttachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomIsReleasing)
        }
    }

    // @spec CHA-RL1c
    @Test
    func attach_whenReleased() async throws {
        // Given: A RoomLifecycleManager in the RELEASED state
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .released)

        // When: `performAttachOperation()` is called on the lifecycle manager
        // Then: It throws a roomIsReleased error
        await #expect {
            try await manager.performAttachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomIsReleased)
        }
    }

    // @spec CHA-RL1d
    @Test
    func attach_ifOtherOperationInProgress_waitsForItToComplete() async throws {
        // Given: A RoomLifecycleManager with a DETACH lifecycle operation in progress (the fact that it is a DETACH is not important; it is just an operation whose execution it is easy to prolong and subsequently complete, which is helpful for this test)
        let contributorDetachOperation = SignallableChannelOperation()
        let manager = await createManager(
            contributors: [
                createContributor(
                    // Arbitrary, allows the ATTACH to eventually complete
                    attachBehavior: .complete(.success),
                    // This allows us to prolong the execution of the DETACH triggered in (1)
                    detachBehavior: contributorDetachOperation.behavior
                ),
            ]
        )

        let detachOperationID = UUID()
        let attachOperationID = UUID()

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        // Wait for the manager to enter DETACHING; this our sign that the DETACH operation triggered in (1) has started
        async let detachingStatusChange = statusChangeSubscription.first { $0.current == .detaching }

        // (1) This is the "DETACH lifecycle operation in progress" mentioned in Given
        async let _ = manager.performDetachOperation(testsOnly_forcingOperationID: detachOperationID)
        _ = await detachingStatusChange

        let operationWaitEventSubscription = await manager.testsOnly_subscribeToOperationWaitEvents()
        async let attachedWaitingForDetachedEvent = operationWaitEventSubscription.first { operationWaitEvent in
            operationWaitEvent == .init(waitingOperationID: attachOperationID, waitedOperationID: detachOperationID)
        }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let attachResult: Void = manager.performAttachOperation(testsOnly_forcingOperationID: attachOperationID)

        // Then:
        // - the manager informs us that the ATTACH operation is waiting for the DETACH operation to complete
        // - when the DETACH completes, the ATTACH operation proceeds (which we check here by verifying that it eventually completes) — note that (as far as I can tell) there is no way to test that the ATTACH operation would have proceeded _only if_ the DETACH had completed; the best we can do is allow the manager to tell us that that this is indeed what it’s doing (which is what we check for in the previous bullet)

        _ = try #require(await attachedWaitingForDetachedEvent)

        // Allow the DETACH to complete
        contributorDetachOperation.complete(result: .success /* arbitrary */ )

        // Check that ATTACH completes
        try await attachResult
    }

    // @spec CHA-RL1e
    @Test
    func attach_transitionsToAttaching() async throws {
        // Given: A RoomLifecycleManager, with a contributor on whom calling `attach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to ATTACHED, so that we can assert its current state as being ATTACHING)
        let contributorAttachOperation = SignallableChannelOperation()

        let manager = await createManager(contributors: [createContributor(attachBehavior: contributorAttachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let _ = try await manager.performAttachOperation()

        // Then: It emits a status change to ATTACHING, and its current state is ATTACHING
        #expect(try #require(await statusChange).current == .attaching)

        #expect(await manager.current == .attaching)

        // Post-test: Now that we’ve seen the ATTACHING state, allow the contributor `attach` call to complete
        contributorAttachOperation.complete(result: .success)
    }

    // @spec CHA-RL1f
    // @spec CHA-RL1g1
    @Test
    func attach_attachesAllContributors_andWhenTheyAllAttachSuccessfully_transitionsToAttached() async throws {
        // Given: A RoomLifecycleManager, all of whose contributors’ calls to `attach` succeed
        let contributors = (1 ... 3).map { _ in createContributor(attachBehavior: .complete(.success)) }
        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let attachedStatusChange = statusChangeSubscription.first { $0.current == .attached }

        // When: `performAttachOperation()` is called on the lifecycle manager
        try await manager.performAttachOperation()

        // Then: It calls `attach` on all the contributors, the room attach operation succeeds, it emits a status change to ATTACHED, and its current state is ATTACHED
        for contributor in contributors {
            #expect(await contributor.channel.attachCallCount > 0)
        }

        _ = try #require(await attachedStatusChange, "Expected status change to ATTACHED")
        try #require(await manager.current == .attached)
    }

    // @spec CHA-RL1g2
    @Test
    func attach_uponSuccess_emitsPendingDiscontinuityEvents() async throws {
        // Given: A RoomLifecycleManager, all of whose contributors’ calls to `attach` succeed
        let contributors = (1 ... 3).map { _ in createContributor(attachBehavior: .complete(.success)) }
        let pendingDiscontinuityEvents: [MockRoomLifecycleContributor.ID: [ARTErrorInfo]] = [
            contributors[1].id: [.init(domain: "SomeDomain", code: 123) /* arbitrary */ ],
            contributors[2].id: [.init(domain: "SomeDomain", code: 456) /* arbitrary */ ],
        ]
        let manager = await createManager(
            forTestingWhatHappensWhenHasPendingDiscontinuityEvents: pendingDiscontinuityEvents,
            contributors: contributors
        )

        // When: `performAttachOperation()` is called on the lifecycle manager
        try await manager.performAttachOperation()

        // Then: It:
        // - emits all pending discontinuities to its contributors
        // - clears all pending discontinuity events (TODO: I assume this is the intended behaviour, but confirm; have asked in https://github.com/ably/specification/pull/200/files#r1781917231)
        for contributor in contributors {
            let expectedPendingDiscontinuityEvents = pendingDiscontinuityEvents[contributor.id] ?? []
            let emitDiscontinuityArguments = await contributor.emitDiscontinuityArguments
            try #require(emitDiscontinuityArguments.count == expectedPendingDiscontinuityEvents.count)
            for (emitDiscontinuityArgument, expectedArgument) in zip(emitDiscontinuityArguments, expectedPendingDiscontinuityEvents) {
                #expect(emitDiscontinuityArgument === expectedArgument)
            }
        }

        for contributor in contributors {
            #expect(await manager.testsOnly_pendingDiscontinuityEvents(for: contributor).isEmpty)
        }
    }

    // @spec CHA-RL1h2
    // @specOneOf(1/2) CHA-RL1h1 - tests that an error gets thrown when channel attach fails due to entering SUSPENDED (TODO: but I don’t yet fully understand the meaning of CHA-RL1h1; outstanding question https://github.com/ably/specification/pull/200/files#r1765476610)
    // @specPartial CHA-RL1h3 - Have tested the failure of the operation and the error that’s thrown. Have not yet implemented the "enter the recovery loop" (TODO: https://github.com/ably-labs/ably-chat-swift/issues/50)
    @Test
    func attach_whenContributorFailsToAttachAndEntersSuspended_transitionsToSuspended() async throws {
        // Given: A RoomLifecycleManager, one of whose contributors’ call to `attach` fails causing it to enter the SUSPENDED state
        let contributorAttachError = ARTErrorInfo(domain: "SomeDomain", code: 123)
        let contributors = (1 ... 3).map { i in
            if i == 1 {
                createContributor(attachBehavior: .completeAndChangeState(.failure(contributorAttachError), newState: .suspended))
            } else {
                createContributor(attachBehavior: .complete(.success))
            }
        }

        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeSuspendedStatusChange = statusChangeSubscription.suspendedElements().first { _ in true }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let roomAttachResult: Void = manager.performAttachOperation()

        // Then:
        //
        // 1. the room status transitions to SUSPENDED, with the state change’s `error` having the AttachmentFailed code corresponding to the feature of the failed contributor, `cause` equal to the error thrown by the contributor `attach` call
        // 2. the manager’s `error` is set to this same error
        // 3. the room attach operation fails with this same error
        let suspendedStatusChange = try #require(await maybeSuspendedStatusChange)

        #expect(await manager.current.isSuspended)

        var roomAttachError: Error?
        do {
            _ = try await roomAttachResult
        } catch {
            roomAttachError = error
        }

        for error in await [suspendedStatusChange.error, manager.current.error, roomAttachError] {
            #expect(isChatError(error, withCode: .messagesAttachmentFailed, cause: contributorAttachError))
        }
    }

    // @specOneOf(2/2) CHA-RL1h1 - tests that an error gets thrown when channel attach fails due to entering FAILED (TODO: but I don’t yet fully understand the meaning of CHA-RL1h1; outstanding question https://github.com/ably/specification/pull/200/files#r1765476610))
    // @spec CHA-RL1h4
    @Test
    func attach_whenContributorFailsToAttachAndEntersFailed_transitionsToFailed() async throws {
        // Given: A RoomLifecycleManager, one of whose contributors’ call to `attach` fails causing it to enter the FAILED state
        let contributorAttachError = ARTErrorInfo(domain: "SomeDomain", code: 123)
        let contributors = (1 ... 3).map { i in
            if i == 1 {
                createContributor(
                    feature: .messages, // arbitrary
                    attachBehavior: .completeAndChangeState(.failure(contributorAttachError), newState: .failed)
                )
            } else {
                createContributor(
                    feature: .occupancy, // arbitrary, just needs to be different to that used for the other contributor
                    attachBehavior: .complete(.success),
                    // The room is going to try to detach per CHA-RL1h5, so even though that's not what this test is testing, we need a detachBehavior so the mock doesn’t blow up
                    detachBehavior: .complete(.success)
                )
            }
        }

        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeFailedStatusChange = statusChangeSubscription.failedElements().first { _ in true }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let roomAttachResult: Void = manager.performAttachOperation()

        // Then:
        // 1. the room status transitions to FAILED, with the state change’s `error` having the AttachmentFailed code corresponding to the feature of the failed contributor, `cause` equal to the error thrown by the contributor `attach` call
        // 2. the manager’s `error` is set to this same error
        // 3. the room attach operation fails with this same error
        let failedStatusChange = try #require(await maybeFailedStatusChange)

        #expect(await manager.current.isFailed)

        var roomAttachError: Error?
        do {
            _ = try await roomAttachResult
        } catch {
            roomAttachError = error
        }

        for error in await [failedStatusChange.error, manager.current.error, roomAttachError] {
            #expect(isChatError(error, withCode: .messagesAttachmentFailed, cause: contributorAttachError))
        }
    }

    // @specPartial CHA-RL1h5 - My initial understanding of this spec point was that the "detach all non-failed channels" was meant to happen _inside_ the ATTACH operation, and that’s what I implemented. Andy subsequently updated the spec to clarify that it’s meant to happen _outside_ the ATTACH operation. I’ll implement this as a separate piece of work later (TODO: https://github.com/ably-labs/ably-chat-swift/issues/50)
    @Test
    func attach_whenAttachPutsChannelIntoFailedState_detachesAllNonFailedChannels() async throws {
        // Given: A room with the following contributors, in the following order:
        //
        // 0. a channel for whom calling `attach` will complete successfully, putting it in the ATTACHED state (i.e. an arbitrarily-chosen state that is not FAILED)
        // 1. a channel for whom calling `attach` will fail, putting it in the FAILED state
        // 2. a channel in the INITIALIZED state (another arbitrarily-chosen state that is not FAILED)
        //
        // for which, when `detach` is called on contributors 0 and 2 (i.e. the non-FAILED contributors), it completes successfully
        let contributors = [
            createContributor(
                attachBehavior: .completeAndChangeState(.success, newState: .attached),
                detachBehavior: .complete(.success)
            ),
            createContributor(
                attachBehavior: .completeAndChangeState(.failure(.create(withCode: 123, message: "")), newState: .failed)
            ),
            createContributor(
                detachBehavior: .complete(.success)
            ),
        ]

        let manager = await createManager(contributors: contributors)

        // When: `performAttachOperation()` is called on the lifecycle manager
        try? await manager.performAttachOperation()

        // Then:
        //
        // - the lifecycle manager will call `detach` on contributors 0 and 2
        // - the lifecycle manager will not call `detach` on contributor 1
        #expect(await contributors[0].channel.detachCallCount > 0)
        #expect(await contributors[2].channel.detachCallCount > 0)
        #expect(await contributors[1].channel.detachCallCount == 0)
    }

    // @spec CHA-RL1h6
    @Test
    func attach_whenChannelDetachTriggered_ifADetachFailsItIsRetriedUntilSuccess() async throws {
        // Given: A room with the following contributors, in the following order:
        //
        // 0. a channel:
        //     - for whom calling `attach` will complete successfully, putting it in the ATTACHED state (i.e. an arbitrarily-chosen state that is not FAILED)
        //     - and for whom subsequently calling `detach` will fail on the first attempt and succeed on the second
        // 1. a channel for whom calling `attach` will fail, putting it in the FAILED state (we won’t make any assertions about this channel; it’s just to trigger the room’s channel detach behaviour)

        let detachResult = { @Sendable (callCount: Int) async -> MockRoomLifecycleContributorChannel.AttachOrDetachResult in
            if callCount == 1 {
                return .failure(.create(withCode: 123, message: ""))
            } else {
                return .success
            }
        }

        let contributors = [
            createContributor(
                attachBehavior: .completeAndChangeState(.success, newState: .attached),
                detachBehavior: .fromFunction(detachResult)
            ),
            createContributor(
                attachBehavior: .completeAndChangeState(.failure(.create(withCode: 123, message: "")), newState: .failed)
            ),
        ]

        let manager = await createManager(contributors: contributors)

        // When: `performAttachOperation()` is called on the lifecycle manager
        try? await manager.performAttachOperation()

        // Then: the lifecycle manager will call `detach` twice on contributor 0 (i.e. it will retry the failed detach)
        #expect(await contributors[0].channel.detachCallCount == 2)
    }

    // MARK: - DETACH operation

    // @spec CHA-RL2a
    @Test
    func detach_whenAlreadyDetached() async throws {
        // Given: A RoomLifecycleManager in the DETACHED state
        let contributor = createContributor()
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .detached, contributors: [contributor])

        // When: `performDetachOperation()` is called on the lifecycle manager
        try await manager.performDetachOperation()

        // Then: The room detach operation succeeds, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @spec CHA-RL2b
    @Test
    func detach_whenReleasing() async throws {
        // Given: A RoomLifecycleManager in the RELEASING state
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .releasing(releaseOperationID: UUID() /* arbitrary */ )
        )

        // When: `performDetachOperation()` is called on the lifecycle manager
        // Then: It throws a roomIsReleasing error
        await #expect {
            try await manager.performDetachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomIsReleasing)
        }
    }

    // @spec CHA-RL2c
    @Test
    func detach_whenReleased() async throws {
        // Given: A RoomLifecycleManager in the RELEASED state
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .released)

        // When: `performAttachOperation()` is called on the lifecycle manager
        // Then: It throws a roomIsReleased error
        await #expect {
            try await manager.performDetachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomIsReleased)
        }
    }

    // @spec CHA-RL2d
    @Test
    func detach_whenFailed() async throws {
        // Given: A RoomLifecycleManager in the FAILED state
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .failed(
                error: .createUnknownError() /* arbitrary */
            )
        )

        // When: `performAttachOperation()` is called on the lifecycle manager
        // Then: It throws a roomInFailedState error
        await #expect {
            try await manager.performDetachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomInFailedState)
        }
    }

    // @specPartial CHA-RL2e - Haven’t implemented the part that refers to "transient disconnect timeouts"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/48)
    @Test
    func detach_transitionsToDetaching() async throws {
        // Given: A RoomLifecycleManager, with a contributor on whom calling `detach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to DETACHED, so that we can assert its current state as being DETACHING)
        let contributorDetachOperation = SignallableChannelOperation()

        let manager = await createManager(contributors: [createContributor(detachBehavior: contributorDetachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performDetachOperation()` is called on the lifecycle manager
        async let _ = try await manager.performDetachOperation()

        // Then: It emits a status change to DETACHING, and its current state is DETACHING
        #expect(try #require(await statusChange).current == .detaching)
        #expect(await manager.current == .detaching)

        // Post-test: Now that we’ve seen the DETACHING state, allow the contributor `detach` call to complete
        contributorDetachOperation.complete(result: .success)
    }

    // @spec CHA-RL2f
    // @spec CHA-RL2g
    @Test
    func detach_detachesAllContributors_andWhenTheyAllDetachSuccessfully_transitionsToDetached() async throws {
        // Given: A RoomLifecycleManager, all of whose contributors’ calls to `detach` succeed
        let contributors = (1 ... 3).map { _ in createContributor(detachBehavior: .complete(.success)) }
        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let detachedStatusChange = statusChangeSubscription.first { $0.current == .detached }

        // When: `performDetachOperation()` is called on the lifecycle manager
        try await manager.performDetachOperation()

        // Then: It calls `detach` on all the contributors, the room detach operation succeeds, it emits a status change to DETACHED, and its current state is DETACHED
        for contributor in contributors {
            #expect(await contributor.channel.detachCallCount > 0)
        }

        _ = try #require(await detachedStatusChange, "Expected status change to DETACHED")
        #expect(await manager.current == .detached)
    }

    // @spec CHA-RL2h1
    @Test
    func detach_whenAContributorFailsToDetachAndEntersFailed_detachesRemainingContributorsAndTransitionsToFailed() async throws {
        // Given: A RoomLifecycleManager, which has 4 contributors:
        //
        // 0: calling `detach` succeeds
        // 1: calling `detach` fails, causing that contributor to subsequently be in the FAILED state
        // 2: calling `detach` fails, causing that contributor to subsequently be in the FAILED state
        // 3: calling `detach` succeeds
        let contributor1DetachError = ARTErrorInfo(domain: "SomeDomain", code: 123)
        let contributor2DetachError = ARTErrorInfo(domain: "SomeDomain", code: 456)

        let contributors = [
            // Features arbitrarily chosen, just need to be distinct in order to make assertions about errors later
            createContributor(feature: .messages, detachBehavior: .success),
            createContributor(feature: .presence, detachBehavior: .completeAndChangeState(.failure(contributor1DetachError), newState: .failed)),
            createContributor(feature: .reactions, detachBehavior: .completeAndChangeState(.failure(contributor2DetachError), newState: .failed)),
            createContributor(feature: .typing, detachBehavior: .success),
        ]

        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeFailedStatusChange = statusChangeSubscription.failedElements().first { _ in true }

        // When: `performDetachOperation()` is called on the lifecycle manager
        let maybeRoomDetachError: Error?
        do {
            try await manager.performDetachOperation()
            maybeRoomDetachError = nil
        } catch {
            maybeRoomDetachError = error
        }

        // Then: It:
        // - calls `detach` on all of the contributors
        // - emits a state change to FAILED and the call to `performDetachOperation()` fails; the error associated with the state change and the `performDetachOperation()` has the *DetachmentFailed code corresponding to contributor 1’s feature, and its `cause` is contributor 1’s `errorReason` (contributor 1 because it’s the "first feature to fail" as the spec says)
        // TODO: Understand whether it’s `errorReason` or the contributor `detach` thrown error that’s meant to be use (outstanding question https://github.com/ably/specification/pull/200/files#r1763792152)
        for contributor in contributors {
            #expect(await contributor.channel.detachCallCount > 0)
        }

        let failedStatusChange = try #require(await maybeFailedStatusChange)

        for maybeError in [maybeRoomDetachError, failedStatusChange.error] {
            #expect(isChatError(maybeError, withCode: .presenceDetachmentFailed, cause: contributor1DetachError))
        }
    }

    // @specUntested CHA-RL2h2 - I was unable to find a way to test this spec point in an environment in which concurrency is being used; there is no obvious moment at which to stop observing the emitted state changes in order to be sure that FAILED has not been emitted twice.

    // @spec CHA-RL2h3
    @Test
    func detach_whenAContributorFailsToDetachAndEntersANonFailedState_pausesAWhileThenRetriesDetach() async throws {
        // Given: A RoomLifecycleManager, with a contributor for whom:
        //
        // - the first two times `detach` is called, it throws an error, leaving it in the ATTACHED state
        // - the third time `detach` is called, it succeeds
        let detachImpl = { @Sendable (callCount: Int) async -> MockRoomLifecycleContributorChannel.AttachOrDetachResult in
            if callCount < 3 {
                return .failure(ARTErrorInfo(domain: "SomeDomain", code: 123)) // exact error is unimportant
            }
            return .success
        }
        let contributor = createContributor(initialState: .attached, detachBehavior: .fromFunction(detachImpl))
        let clock = MockSimpleClock()

        let manager = await createManager(contributors: [contributor], clock: clock)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let asyncLetStatusChanges = Array(statusChangeSubscription.prefix(2))

        // When: `performDetachOperation()` is called on the manager
        try await manager.performDetachOperation()

        // Then: It attempts to detach the channel 3 times, waiting 1s between each attempt, the room transitions from DETACHING to DETACHED with no status updates in between, and the call to `performDetachOperation()` succeeds
        #expect(await contributor.channel.detachCallCount == 3)

        // We use "did it call clock.sleep(…)?" as a good-enough proxy for the question "did it wait for the right amount of time at the right moment?"
        #expect(await clock.sleepCallArguments == Array(repeating: 1, count: 2))

        #expect(await asyncLetStatusChanges.map(\.current) == [.detaching, .detached])
    }

    // MARK: - RELEASE operation

    // @spec CHA-RL3a
    @Test
    func release_whenAlreadyReleased() async {
        // Given: A RoomLifecycleManager in the RELEASED state
        let contributor = createContributor()
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .released, contributors: [contributor])

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then: The room release operation succeeds, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @spec CHA-RL3b
    @Test
    func release_whenDetached() async throws {
        // Given: A RoomLifecycleManager in the DETACHED state
        let contributor = createContributor()
        let manager = await createManager(forTestingWhatHappensWhenCurrentlyIn: .detached, contributors: [contributor])

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then: The room release operation succeeds, the room transitions to RELEASED, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that the transition be "immediate")
        #expect(try #require(await statusChange).current == .released)
        #expect(await manager.current == .released)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @specPartial CHA-RL3c - This is marked as specPartial because at time of writing the spec point CHA-RL3c has been accidentally duplicated to specify two separate behaviours. TODO: change this one to @spec once spec fixed (see discussion in https://github.com/ably/specification/pull/200#discussion_r1763770348)
    @Test
    func release_whenReleasing() async throws {
        // Given: A RoomLifecycleManager with a RELEASE lifecycle operation in progress, and hence in the RELEASING state
        let contributorDetachOperation = SignallableChannelOperation()
        let contributor = createContributor(
            // This allows us to prolong the execution of the RELEASE triggered in (1)
            detachBehavior: contributorDetachOperation.behavior
        )
        let manager = await createManager(contributors: [contributor])

        let firstReleaseOperationID = UUID()
        let secondReleaseOperationID = UUID()

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        // Wait for the manager to enter RELEASING; this our sign that the DETACH operation triggered in (1) has started
        async let releasingStatusChange = statusChangeSubscription.first { $0.current == .releasing }

        // (1) This is the "RELEASE lifecycle operation in progress" mentioned in Given
        async let _ = manager.performReleaseOperation(testsOnly_forcingOperationID: firstReleaseOperationID)
        _ = await releasingStatusChange

        let operationWaitEventSubscription = await manager.testsOnly_subscribeToOperationWaitEvents()
        async let secondReleaseWaitingForFirstReleaseEvent = operationWaitEventSubscription.first { operationWaitEvent in
            operationWaitEvent == .init(waitingOperationID: secondReleaseOperationID, waitedOperationID: firstReleaseOperationID)
        }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        async let secondReleaseResult: Void = manager.performReleaseOperation(testsOnly_forcingOperationID: secondReleaseOperationID)

        // Then:
        // - the manager informs us that the second RELEASE operation is waiting for first RELEASE operation to complete
        // - when the first RELEASE completes, the second RELEASE operation also completes
        // - the second RELEASE operation does not perform any side-effects (which we check here by confirming that the CHA-RL3d contributor detach only happened once, i.e. was only performed by the first RELEASE operation)

        _ = try #require(await secondReleaseWaitingForFirstReleaseEvent)

        // Allow the first RELEASE to complete
        contributorDetachOperation.complete(result: .success)

        // Check that the second RELEASE completes
        await secondReleaseResult

        #expect(await contributor.channel.detachCallCount == 1)
    }

    // @specPartial CHA-RL3c - Haven’t implemented the part that refers to "transient disconnect timeouts"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/48)
    @Test
    func release_transitionsToReleasing() async throws {
        // Given: A RoomLifecycleManager, with a contributor on whom calling `detach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to RELEASED, so that we can assert its current state as being RELEASING)
        let contributorDetachOperation = SignallableChannelOperation()

        let manager = await createManager(contributors: [createContributor(detachBehavior: contributorDetachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        async let _ = await manager.performReleaseOperation()

        // Then: It emits a status change to RELEASING, and its current state is RELEASING
        #expect(try #require(await statusChange).current == .releasing)
        #expect(await manager.current == .releasing)

        // Post-test: Now that we’ve seen the RELEASING state, allow the contributor `detach` call to complete
        contributorDetachOperation.complete(result: .success)
    }

    // @spec CHA-RL3d
    // @specOneOf(1/2) CHA-RL3e
    // @spec CHA-RL3g
    @Test
    func release_detachesAllNonFailedContributors() async throws {
        // Given: A RoomLifecycleManager, with the following contributors:
        // - two in a non-FAILED state, and on whom calling `detach()` succeeds
        // - one in the FAILED state
        let contributors = [
            createContributor(initialState: .attached /* arbitrary non-FAILED */, detachBehavior: .complete(.success)),
            // We put the one that will be skipped in the middle, to verify that the subsequent contributors don’t get skipped
            createContributor(initialState: .failed, detachBehavior: .complete(.failure(.init(domain: "SomeDomain", code: 123) /* arbitrary error */ ))),
            createContributor(initialState: .detached /* arbitrary non-FAILED */, detachBehavior: .complete(.success)),
        ]

        let manager = await createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let releasedStatusChange = statusChangeSubscription.first { $0.current == .released }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then:
        // - it calls `detach()` on the non-FAILED contributors
        // - it does not call `detach()` on the FAILED contributor
        // - the room transitions to RELEASED
        // - the call to `performReleaseOperation()` completes
        for nonFailedContributor in [contributors[0], contributors[2]] {
            #expect(await nonFailedContributor.channel.detachCallCount == 1)
        }

        #expect(await contributors[1].channel.detachCallCount == 0)

        _ = await releasedStatusChange

        #expect(await manager.current == .released)
    }

    // @spec CHA-RL3f
    @Test
    func release_whenDetachFails_ifContributorIsNotFailed_retriesAfterPause() async {
        // Given: A RoomLifecycleManager, with a contributor for which:
        // - the first two times that `detach()` is called, it fails, leaving the contributor in a non-FAILED state
        // - the third time that `detach()` is called, it succeeds
        let detachImpl = { @Sendable (callCount: Int) async -> MockRoomLifecycleContributorChannel.AttachOrDetachResult in
            if callCount < 3 {
                return .failure(ARTErrorInfo(domain: "SomeDomain", code: 123)) // exact error is unimportant
            }
            return .success
        }
        let contributor = createContributor(detachBehavior: .fromFunction(detachImpl))

        let clock = MockSimpleClock()

        let manager = await createManager(contributors: [contributor], clock: clock)

        // Then: When `performReleaseOperation()` is called on the manager
        await manager.performReleaseOperation()

        // It: calls `detach()` on the channel 3 times, with a 1s pause between each attempt, and the call to `performReleaseOperation` completes
        #expect(await contributor.channel.detachCallCount == 3)

        // We use "did it call clock.sleep(…)?" as a good-enough proxy for the question "did it wait for the right amount of time at the right moment?"
        #expect(await clock.sleepCallArguments == Array(repeating: 1, count: 2))
    }

    // @specOneOf(2/2) CHA-RL3e - Tests that this spec point suppresses CHA-RL3f retries
    @Test
    func release_whenDetachFails_ifContributorIsFailed_doesNotRetry() async {
        // Given: A RoomLifecycleManager, with a contributor for which, when `detach()` is called, it fails, causing the contributor to enter the FAILED state
        let contributor = createContributor(detachBehavior: .completeAndChangeState(.failure(.init(domain: "SomeDomain", code: 123) /* arbitrary error */ ), newState: .failed))

        let clock = MockSimpleClock()

        let manager = await createManager(contributors: [contributor], clock: clock)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let releasedStatusChange = statusChangeSubscription.first { $0.current == .released }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then:
        // - it calls `detach()` precisely once on the contributor (that is, it does not retry)
        // - it waits 1s (TODO: confirm my interpretation of CHA-RL3f, which is that the wait still happens, but is not followed by a retry; have asked in https://github.com/ably/specification/pull/200/files#r1765372854)
        // - the room transitions to RELEASED
        // - the call to `performReleaseOperation()` completes
        #expect(await contributor.channel.detachCallCount == 1)

        // We use "did it call clock.sleep(…)?" as a good-enough proxy for the question "did it wait for the right amount of time at the right moment?"
        #expect(await clock.sleepCallArguments == [1])

        _ = await releasedStatusChange

        #expect(await manager.current == .released)
    }

    // MARK: - Handling contributor UPDATE events

    // @spec CHA-RL4a1
    @Test
    func contributorUpdate_withResumedTrue_doesNothing() async throws {
        // Given: A RoomLifecycleManager
        let contributor = createContributor()
        let manager = await createManager(contributors: [contributor])

        // When: A contributor emits an UPDATE event with `resumed` flag set to true
        let contributorStateChange = ARTChannelStateChange(
            current: .attached, // arbitrary
            previous: .attached, // arbitrary
            event: .update,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: true
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributor.channel.emitStateChange(contributorStateChange)
        }

        // Then: The manager does not record a pending discontinuity event for this contributor, nor does it call `emitDiscontinuity` on the contributor (this is my interpretation of "no action should be taken" in CHA-RL4a1; i.e. that the actions described in CHA-RL4a2 and CHA-RL4a3 shouldn’t happen) (TODO: get clarification; have asked in https://github.com/ably/specification/pull/200#discussion_r1777385499)
        #expect(await manager.testsOnly_pendingDiscontinuityEvents(for: contributor).isEmpty)
        #expect(await contributor.emitDiscontinuityArguments.isEmpty)
    }

    // @spec CHA-RL4a3
    @Test
    func contributorUpdate_withResumedFalse_withOperationInProgress_recordsPendingDiscontinuityEvent() async throws {
        // Given: A RoomLifecycleManager, with a room lifecycle operation in progress
        let contributor = createContributor()
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .attaching(attachOperationID: UUID()), // case and ID arbitrary, just care that an operation is in progress
            contributors: [contributor]
        )

        // When: A contributor emits an UPDATE event with `resumed` flag set to false
        let contributorStateChange = ARTChannelStateChange(
            current: .attached, // arbitrary
            previous: .attached, // arbitrary
            event: .update,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributor.channel.emitStateChange(contributorStateChange)
        }

        // Then: The manager records a pending discontinuity event for this contributor, and this discontinuity event has error equal to the contributor UPDATE event’s `reason`
        let pendingDiscontinuityEvents = await manager.testsOnly_pendingDiscontinuityEvents(for: contributor)
        try #require(pendingDiscontinuityEvents.count == 1)

        let pendingDiscontinuityEvent = pendingDiscontinuityEvents[0]
        #expect(pendingDiscontinuityEvent === contributorStateChange.reason)
    }

    // @spec CHA-RL4a4
    @Test
    func contributorUpdate_withResumedTrue_withNoOperationInProgress_emitsDiscontinuityEvent() async throws {
        // Given: A RoomLifecycleManager, with no room lifecycle operation in progress
        let contributor = createContributor()
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .initialized, // case arbitrary, just care that no operation is in progress
            contributors: [contributor]
        )

        // When: A contributor emits an UPDATE event with `resumed` flag set to false
        let contributorStateChange = ARTChannelStateChange(
            current: .attached, // arbitrary
            previous: .attached, // arbitrary
            event: .update,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributor.channel.emitStateChange(contributorStateChange)
        }

        // Then: The manager calls `emitDiscontinuity` on the contributor, with error equal to the contributor UPDATE event’s `reason`
        let emitDiscontinuityArguments = await contributor.emitDiscontinuityArguments
        try #require(emitDiscontinuityArguments.count == 1)

        let discontinuity = emitDiscontinuityArguments[0]
        #expect(discontinuity === contributorStateChange.reason)
    }

    // @specPartial CHA-RL4b1 - I don’t know the meaning of "and the particular contributor has been attached previously" so haven’t implemented that part of the spec point (TODO: asked in https://github.com/ably/specification/pull/200/files#r1775552624)
    @Test
    func contributorAttachEvent_withResumeFalse_withOperationInProgress_recordsPendingDiscontinuityEvent() async throws {
        // Given: A RoomLifecycleManager, with a room lifecycle operation in progress
        let contributor = createContributor()
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .attaching(attachOperationID: UUID()), // case and ID arbitrary, just care that an operation is in progress
            contributors: [contributor]
        )

        // When: A contributor emits an ATTACHED event with `resumed` flag set to false
        let contributorStateChange = ARTChannelStateChange(
            current: .attached,
            previous: .attaching, // arbitrary
            event: .attached,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributor.channel.emitStateChange(contributorStateChange)
        }

        // Then: The manager records a pending discontinuity event for this contributor, and this discontinuity event has error equal to the contributor ATTACHED event’s `reason`
        let pendingDiscontinuityEvents = await manager.testsOnly_pendingDiscontinuityEvents(for: contributor)
        try #require(pendingDiscontinuityEvents.count == 1)

        let pendingDiscontinuityEvent = pendingDiscontinuityEvents[0]
        #expect(pendingDiscontinuityEvent === contributorStateChange.reason)
    }

    // @specPartial CHA-RL4b5 - Haven’t implemented the part that refers to "transient disconnect timeouts"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/48)
    @Test
    func contributorFailedEvent_withNoOperationInProgress() async throws {
        // Given: A RoomLifecycleManager, with no room lifecycle operation in progress
        let contributors = [
            // TODO: The .success is currently arbitrary since the spec doesn’t say what to do if detach fails (have asked in https://github.com/ably/specification/pull/200#discussion_r1777471810)
            createContributor(detachBehavior: .success),
            createContributor(detachBehavior: .success),
        ]
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .initialized, // case arbitrary, just care that no operation is in progress
            contributors: contributors
        )

        let roomStatusSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let failedStatusChange = roomStatusSubscription.failedElements().first { _ in true }

        // When: A contributor emits an FAILED event
        let contributorStateChange = ARTChannelStateChange(
            current: .failed,
            previous: .attached, // arbitrary
            event: .failed,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false // arbitrary
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributors[0].channel.emitStateChange(contributorStateChange)
        }

        // Then:
        // - the room status transitions to failed, with the error of the status change being the `reason` of the contributor FAILED event
        // - and it calls `detach` on all contributors
        _ = try #require(await failedStatusChange)
        #expect(await manager.current.isFailed)

        for contributor in contributors {
            #expect(await contributor.channel.detachCallCount == 1)
        }
    }

    // @specOneOf(1/2) CHA-RL4b8
    @Test
    func contributorAttachedEvent_withNoOperationInProgress_roomNotAttached_allContributorsAttached() async throws {
        // Given: A RoomLifecycleManager, with no operation in progress and not in the ATTACHED state, all of whose contributors are in the ATTACHED state (to satisfy the condition of CHA-RL4b8; for the purposes of this test I don’t care that they’re in this state even _before_ the state change of the When)
        let contributors = [
            createContributor(initialState: .attached),
            createContributor(initialState: .attached),
        ]

        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .initialized, // arbitrary non-ATTACHED
            contributors: contributors
        )

        let roomStatusSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeAttachedRoomStatusChange = roomStatusSubscription.first { $0.current == .attached }

        // When: A contributor emits a state change to ATTACHED
        let contributorStateChange = ARTChannelStateChange(
            current: .attached,
            previous: .attaching, // arbitrary
            event: .attached,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false // arbitrary
        )

        await contributors[0].channel.emitStateChange(contributorStateChange)

        // Then: The room status transitions to ATTACHED
        _ = try #require(await maybeAttachedRoomStatusChange)
        #expect(await manager.current == .attached)
    }

    // @specOneOf(2/2) CHA-RL4b8 - Tests that the specified side effect doesn’t happen if part of the condition (i.e. all contributors now being ATTACHED) is not met
    @Test
    func contributorAttachedEvent_withNoOperationInProgress_roomNotAttached_notAllContributorsAttached() async throws {
        // Given: A RoomLifecycleManager, with no operation in progress and not in the ATTACHED state, one of whose contributors is not in the ATTACHED state state (to simulate the condition of CHA-RL4b8 not being met; for the purposes of this test I don’t care that they’re in this state even _before_ the state change of the When)
        let contributors = [
            createContributor(initialState: .attached),
            createContributor(initialState: .detached),
        ]

        let initialManagerStatus = RoomLifecycleManager<MockRoomLifecycleContributor>.Status.detached // arbitrary non-ATTACHED, no-operation-in-progress
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: initialManagerStatus,
            contributors: contributors
        )

        // When: A contributor emits a state change to ATTACHED
        let contributorStateChange = ARTChannelStateChange(
            current: .attached,
            previous: .attaching, // arbitrary
            event: .attached,
            reason: ARTErrorInfo(domain: "SomeDomain", code: 123), // arbitrary
            resumed: false // arbitrary
        )

        await waitForManager(manager, toHandleContributorStateChange: contributorStateChange) {
            await contributors[0].channel.emitStateChange(contributorStateChange)
        }

        // Then: The room status does not change
        #expect(await manager.current == initialManagerStatus.toRoomLifecycle)
    }

    // @specPartial CHA-RL4b9 - Haven’t implemented the part that refers to "transient disconnect timeouts"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/48). Nor have I implemented "the room enters the RETRY loop"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/51)
    @Test
    func contributorSuspendedEvent_withNoOperationInProgress() async throws {
        // Given: A RoomLifecycleManager with no lifecycle operation in progress
        let contributor = createContributor()
        let manager = await createManager(
            forTestingWhatHappensWhenCurrentlyIn: .initialized, // case arbitrary, just care that no operation is in progress
            contributors: [contributor]
        )

        let roomStatusSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeSuspendedRoomStatusChange = roomStatusSubscription.suspendedElements().first { _ in true }

        // When: A contributor emits a state change to SUSPENDED
        let contributorStateChangeReason = ARTErrorInfo(domain: "SomeDomain", code: 123) // arbitrary
        let contributorStateChange = ARTChannelStateChange(
            current: .suspended,
            previous: .attached, // arbitrary
            event: .suspended,
            reason: contributorStateChangeReason,
            resumed: false // arbitrary
        )

        await contributor.channel.emitStateChange(contributorStateChange)

        // Then: The room transitions to SUSPENDED, and this state change has error equal to the contributor state change’s `reason`
        let suspendedRoomStatusChange = try #require(await maybeSuspendedRoomStatusChange)
        #expect(suspendedRoomStatusChange.error === contributorStateChangeReason)

        #expect(await manager.current == .suspended(error: contributorStateChangeReason))
    }
}
