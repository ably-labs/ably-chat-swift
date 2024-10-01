import Ably
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
        forTestingWhatHappensWhenCurrentlyIn status: RoomStatus? = nil,
        contributors: [RoomLifecycleManager<MockRoomLifecycleContributorChannel>.Contributor] = [],
        clock: SimpleClock = MockSimpleClock()
    ) -> RoomLifecycleManager<MockRoomLifecycleContributorChannel> {
        .init(
            testsOnly_status: status,
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
    ) -> RoomLifecycleManager<MockRoomLifecycleContributorChannel>.Contributor {
        .init(
            feature: feature,
            channel: .init(
                initialState: initialState,
                attachBehavior: attachBehavior,
                detachBehavior: detachBehavior
            )
        )
    }

    // MARK: - Initial state

    // @spec CHA-RS2a
    // @spec CHA-RS3
    @Test
    func status_startsAsInitialized() async {
        let manager = createManager()

        #expect(await manager.status == .initialized)
    }

    @Test
    func error_startsAsNil() async {
        let manager = createManager()

        #expect(await manager.error == nil)
    }

    // MARK: - ATTACH operation

    // @spec CHA-RL1a
    @Test
    func attach_whenAlreadyAttached() async throws {
        // Given: A RoomLifecycleManager in the ATTACHED status
        let contributor = createContributor()
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .attached, contributors: [contributor])

        // When: `performAttachOperation()` is called on the lifecycle manager
        try await manager.performAttachOperation()

        // Then: The room attach operation succeeds, and no attempt is made to attach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.attachCallCount == 0)
    }

    // @spec CHA-RL1b
    @Test
    func attach_whenReleasing() async throws {
        // Given: A RoomLifecycleManager in the RELEASING status
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .releasing)

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
        // Given: A RoomLifecycleManager in the RELEASED status
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .released)

        // When: `performAttachOperation()` is called on the lifecycle manager
        // Then: It throws a roomIsReleased error
        await #expect {
            try await manager.performAttachOperation()
        } throws: { error in
            isChatError(error, withCode: .roomIsReleased)
        }
    }

    // @spec CHA-RL1e
    @Test
    func attach_transitionsToAttaching() async throws {
        // Given: A RoomLifecycleManager, with a contributor on whom calling `attach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to ATTACHED, so that we can assert its current status as being ATTACHING)
        let contributorAttachOperation = SignallableChannelOperation()

        let manager = createManager(contributors: [createContributor(attachBehavior: contributorAttachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let _ = try await manager.performAttachOperation()

        // Then: It emits a status change to ATTACHING, and its current status is ATTACHING
        #expect(try #require(await statusChange).current == .attaching)

        #expect(await manager.status == .attaching)

        // Post-test: Now that we’ve seen the ATTACHING status, allow the contributor `attach` call to complete
        contributorAttachOperation.complete(result: .success)
    }

    // @spec CHA-RL1f
    // @spec CHA-RL1g1
    @Test
    func attach_attachesAllContributors_andWhenTheyAllAttachSuccessfully_transitionsToAttached() async throws {
        // Given: A RoomLifecycleManager, all of whose contributors’ calls to `attach` succeed
        let contributors = (1 ... 3).map { _ in createContributor(attachBehavior: .complete(.success)) }
        let manager = createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let attachedStatusChange = statusChangeSubscription.first { $0.current == .attached }

        // When: `performAttachOperation()` is called on the lifecycle manager
        try await manager.performAttachOperation()

        // Then: It calls `attach` on all the contributors, the room attach operation succeeds, it emits a status change to ATTACHED, and its current status is ATTACHED
        for contributor in contributors {
            #expect(await contributor.channel.attachCallCount > 0)
        }

        _ = try #require(await attachedStatusChange, "Expected status change to ATTACHED")
        try #require(await manager.status == .attached)
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

        let manager = createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeSuspendedStatusChange = statusChangeSubscription.first { $0.current == .suspended }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let roomAttachResult: Void = manager.performAttachOperation()

        // Then:
        //
        // 1. the room status transitions to SUSPENDED, with the status change’s `error` having the AttachmentFailed code corresponding to the feature of the failed contributor, `cause` equal to the error thrown by the contributor `attach` call
        // 2. the manager’s `error` is set to this same error
        // 3. the room attach operation fails with this same error
        let suspendedStatusChange = try #require(await maybeSuspendedStatusChange)

        #expect(await manager.status == .suspended)

        var roomAttachError: Error?
        do {
            _ = try await roomAttachResult
        } catch {
            roomAttachError = error
        }

        for error in await [suspendedStatusChange.error, manager.error, roomAttachError] {
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

        let manager = createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeFailedStatusChange = statusChangeSubscription.first { $0.current == .failed }

        // When: `performAttachOperation()` is called on the lifecycle manager
        async let roomAttachResult: Void = manager.performAttachOperation()

        // Then:
        // 1. the room status transitions to FAILED, with the status change’s `error` having the AttachmentFailed code corresponding to the feature of the failed contributor, `cause` equal to the error thrown by the contributor `attach` call
        // 2. the manager’s `error` is set to this same error
        // 3. the room attach operation fails with this same error
        let failedStatusChange = try #require(await maybeFailedStatusChange)

        #expect(await manager.status == .failed)

        var roomAttachError: Error?
        do {
            _ = try await roomAttachResult
        } catch {
            roomAttachError = error
        }

        for error in await [failedStatusChange.error, manager.error, roomAttachError] {
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

        let manager = createManager(contributors: contributors)

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

        let manager = createManager(contributors: contributors)

        // When: `performAttachOperation()` is called on the lifecycle manager
        try? await manager.performAttachOperation()

        // Then: the lifecycle manager will call `detach` twice on contributor 0 (i.e. it will retry the failed detach)
        #expect(await contributors[0].channel.detachCallCount == 2)
    }

    // MARK: - DETACH operation

    // @spec CHA-RL2a
    @Test
    func detach_whenAlreadyDetached() async throws {
        // Given: A RoomLifecycleManager in the DETACHED status
        let contributor = createContributor()
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .detached, contributors: [contributor])

        // When: `performDetachOperation()` is called on the lifecycle manager
        try await manager.performDetachOperation()

        // Then: The room detach operation succeeds, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @spec CHA-RL2b
    @Test
    func detach_whenReleasing() async throws {
        // Given: A RoomLifecycleManager in the RELEASING status
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .releasing)

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
        // Given: A RoomLifecycleManager in the RELEASED status
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .released)

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
        // Given: A RoomLifecycleManager in the FAILED status
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .failed)

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
        // Given: A RoomLifecycleManager, with a contributor on whom calling `detach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to DETACHED, so that we can assert its current status as being DETACHING)
        let contributorDetachOperation = SignallableChannelOperation()

        let manager = createManager(contributors: [createContributor(detachBehavior: contributorDetachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performDetachOperation()` is called on the lifecycle manager
        async let _ = try await manager.performDetachOperation()

        // Then: It emits a status change to DETACHING, and its current status is DETACHING
        #expect(try #require(await statusChange).current == .detaching)
        #expect(await manager.status == .detaching)

        // Post-test: Now that we’ve seen the DETACHING status, allow the contributor `detach` call to complete
        contributorDetachOperation.complete(result: .success)
    }

    // @spec CHA-RL2f
    // @spec CHA-RL2g
    @Test
    func detach_detachesAllContributors_andWhenTheyAllDetachSuccessfully_transitionsToDetached() async throws {
        // Given: A RoomLifecycleManager, all of whose contributors’ calls to `detach` succeed
        let contributors = (1 ... 3).map { _ in createContributor(detachBehavior: .complete(.success)) }
        let manager = createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let detachedStatusChange = statusChangeSubscription.first { $0.current == .detached }

        // When: `performDetachOperation()` is called on the lifecycle manager
        try await manager.performDetachOperation()

        // Then: It calls `detach` on all the contributors, the room detach operation succeeds, it emits a status change to DETACHED, and its current status is DETACHED
        for contributor in contributors {
            #expect(await contributor.channel.detachCallCount > 0)
        }

        _ = try #require(await detachedStatusChange, "Expected status change to DETACHED")
        #expect(await manager.status == .detached)
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

        let manager = createManager(contributors: contributors)

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let maybeFailedStatusChange = statusChangeSubscription.first { $0.current == .failed }

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
        // - emits a status change to FAILED and the call to `performDetachOperation()` fails; the error associated with the status change and the `performDetachOperation()` has the *DetachmentFailed code corresponding to contributor 1’s feature, and its `cause` is contributor 1’s `errorReason` (contributor 1 because it’s the "first feature to fail" as the spec says)
        // TODO: Understand whether it’s `errorReason` or the contributor `detach` thrown error that’s meant to be use (outstanding question https://github.com/ably/specification/pull/200/files#r1763792152)
        for contributor in contributors {
            #expect(await contributor.channel.detachCallCount > 0)
        }

        let failedStatusChange = try #require(await maybeFailedStatusChange)

        for maybeError in [maybeRoomDetachError, failedStatusChange.error] {
            #expect(isChatError(maybeError, withCode: .presenceDetachmentFailed, cause: contributor1DetachError))
        }
    }

    // @specUntested CHA-RL2h2 - I was unable to find a way to test this spec point in an environment in which concurrency is being used; there is no obvious moment at which to stop observing the emitted status changes in order to be sure that FAILED has not been emitted twice.

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

        let manager = createManager(contributors: [contributor], clock: clock)

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
        // Given: A RoomLifecycleManager in the RELEASED status
        let contributor = createContributor()
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .released, contributors: [contributor])

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then: The room release operation succeeds, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that a "no-op" happen)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @spec CHA-RL3b
    @Test
    func release_whenDetached() async throws {
        // Given: A RoomLifecycleManager in the DETACHED status
        let contributor = createContributor()
        let manager = createManager(forTestingWhatHappensWhenCurrentlyIn: .detached, contributors: [contributor])

        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        await manager.performReleaseOperation()

        // Then: The room release operation succeeds, the room transitions to RELEASED, and no attempt is made to detach a contributor (which we’ll consider as satisfying the spec’s requirement that the transition be "immediate")
        #expect(try #require(await statusChange).current == .released)
        #expect(await manager.status == .released)
        #expect(await contributor.channel.detachCallCount == 0)
    }

    // @specPartial CHA-RL3c - Haven’t implemented the part that refers to "transient disconnect timeouts"; TODO do this (https://github.com/ably-labs/ably-chat-swift/issues/48)
    @Test
    func release_transitionsToReleasing() async throws {
        // Given: A RoomLifecycleManager, with a contributor on whom calling `detach()` will not complete until after the "Then" part of this test (the motivation for this is to suppress the room from transitioning to RELEASED, so that we can assert its current status as being RELEASING)
        let contributorDetachOperation = SignallableChannelOperation()

        let manager = createManager(contributors: [createContributor(detachBehavior: contributorDetachOperation.behavior)])
        let statusChangeSubscription = await manager.onChange(bufferingPolicy: .unbounded)
        async let statusChange = statusChangeSubscription.first { _ in true }

        // When: `performReleaseOperation()` is called on the lifecycle manager
        async let _ = await manager.performReleaseOperation()

        // Then: It emits a status change to RELEASING, and its current status is RELEASING
        #expect(try #require(await statusChange).current == .releasing)
        #expect(await manager.status == .releasing)

        // Post-test: Now that we’ve seen the RELEASING status, allow the contributor `detach` call to complete
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

        let manager = createManager(contributors: contributors)

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

        #expect(await manager.status == .released)
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

        let manager = createManager(contributors: [contributor], clock: clock)

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

        let manager = createManager(contributors: [contributor], clock: clock)

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

        #expect(await manager.status == .released)
    }
}
