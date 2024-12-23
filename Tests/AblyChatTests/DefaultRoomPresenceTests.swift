import Ably
@testable import AblyChat
import Testing

struct DefaultRoomPresenceTests {
    // @spec CHA-PR1
    @Test
    func channelNameIsSetAsChatMessagesChannelName() async throws {
        // Given
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages")
        let featureChannel = MockFeatureChannel(channel: channel)

        // When
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger())

        // Then
        #expect(defaultPresence.channel.name == "basketball::$chat::$chatMessages")
    }

    // @spec CHA-PR5
    @Test
    func ifUserIsPresent() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1", "client2"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(())) // CHA-PR6d
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger())

        // When
        let isUserPresent1 = try await defaultPresence.isUserPresent(clientID: "client2")
        let isUserPresent2 = try await defaultPresence.isUserPresent(clientID: "client3")

        // Then
        #expect(isUserPresent1 == true)
        #expect(isUserPresent2 == false)
    }

    // @spec CHA-PR3a
    // @spec CHA-PR3e
    @Test
    func usersMayEnterPresence() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "client2", logger: TestLogger())

        // When
        try await defaultPresence.enter(data: ["status": "Online"])

        // Then
        let presenceMembers = try await defaultPresence.get()
        #expect(presenceMembers.map { $0.clientID }.sorted() == ["client1", "client2"])
        let client2 = presenceMembers.filter { member in
            member.clientID == "client2" && member.data?.objectValue?["status"]?.stringValue == "Online"
        }
        #expect(client2 != nil)
    }

    // @spec CHA-PR10a
    // @spec CHA-PR10e
    @Test
    func usersMayUpdatePresence() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger())

        // When
        try await defaultPresence.update(data: ["status": "Online"])

        // Then
        let presenceMembers = try await defaultPresence.get()
        let client1 = presenceMembers.filter { member in
            member.clientID == "client1" && member.data?.objectValue?["status"]?.stringValue == "Online"
        }
        #expect(client1 != nil)
    }

    // @spec CHA-PR4a
    @Test
    func usersMayLeavePresence() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger())

        // When
        try await defaultPresence.leave()

        // Then
        let presenceMembers = try await defaultPresence.get()
        #expect(presenceMembers.isEmpty)
    }

    // @spec CHA-PR6
    // @spec CHA-PR6d
    @Test
    func retrieveAllTheMembersOfThePresenceSet() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1", "client2"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger())

        // When
        let presenceMembers = try await defaultPresence.get()

        // Then
        #expect(presenceMembers.map { $0.clientID }.sorted() == ["client1", "client2"])
    }

    // @spec CHA-PR6h
    @Test
    func failToRetrieveAllTheMembersOfThePresenceSetWhenRoomInInvalidState() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1", "client2"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let error = ARTErrorInfo(chatError: .presenceOperationRequiresRoomAttach(feature: .presence))
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .failure(error))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger())

        // Then
        await #expect(throws: ARTErrorInfo.self) {
            do {
                _ = try await defaultPresence.get()
            } catch {
                let error = try #require(error as? ARTErrorInfo)
                #expect(error.statusCode == 400)
                #expect(error.localizedDescription.contains("attach"))
                throw error
            }
        }
    }

    // @spec CHA-PR7a
    // @spec CHA-PR7b
    // @spec CHA-PR7c
    @Test
    func usersMaySubscribeToAllPresenceEvents() async throws {
        // Given
        let realtimePresence = MockRealtimePresence(["client1", "client2"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$chatMessages", mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(())) // CHA-PR6d
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger())

        // Given
        let subscription = await defaultPresence.subscribe(events: .all) // CHA-PR7a and CHA-PR7b since `all` is just a selection of all events

        // When
        subscription.emit(PresenceEvent(action: .present, clientID: "client1", timestamp: Date(), data: nil))

        // Then
        let presentEvent = try #require(await subscription.first { _ in true })
        #expect(presentEvent.action == .present)
        #expect(presentEvent.clientID == "client1")

        // When
        subscription.emit(PresenceEvent(action: .enter, clientID: "client1", timestamp: Date(), data: nil))

        // Then
        let enterEvent = try #require(await subscription.first { _ in true })
        #expect(enterEvent.action == .enter)
        #expect(enterEvent.clientID == "client1")

        // When
        subscription.emit(PresenceEvent(action: .update, clientID: "client1", timestamp: Date(), data: nil))

        // Then
        let updateEvent = try #require(await subscription.first { _ in true })
        #expect(updateEvent.action == .update)
        #expect(updateEvent.clientID == "client1")

        // When
        subscription.emit(PresenceEvent(action: .leave, clientID: "client1", timestamp: Date(), data: nil))

        // Then
        let leaveEvent = try #require(await subscription.first { _ in true })
        #expect(leaveEvent.action == .leave)
        #expect(leaveEvent.clientID == "client1")

        // CHA-PR7c

        // When
        subscription.unsubscribe()

        // When
        subscription.emit(PresenceEvent(action: .present, clientID: "client1", timestamp: Date(), data: nil))
        subscription.emit(PresenceEvent(action: .enter, clientID: "client1", timestamp: Date(), data: nil))
        subscription.emit(PresenceEvent(action: .leave, clientID: "client1", timestamp: Date(), data: nil))
        subscription.emit(PresenceEvent(action: .update, clientID: "client1", timestamp: Date(), data: nil))

        // Then
        let nilAnyEvent = await subscription.first { _ in true }
        #expect(nilAnyEvent == nil)
    }

    // @spec CHA-PR8
    @Test
    func onDiscontinuity() async throws {
        // Given
        let realtimePresence = MockRealtimePresence([])
        let channel = MockRealtimeChannel(mockPresence: realtimePresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultPresence = await DefaultPresence(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger())

        // When: The feature channel emits a discontinuity through `onDiscontinuity`
        let featureChannelDiscontinuity = DiscontinuityEvent(error: ARTErrorInfo.createUnknownError()) // arbitrary error
        let discontinuitySubscription = await defaultPresence.onDiscontinuity()
        await featureChannel.emitDiscontinuity(featureChannelDiscontinuity)

        // Then: The DefaultOccupancy instance emits this discontinuity through `onDiscontinuity`
        let discontinuity = try #require(await discontinuitySubscription.first { _ in true })
        #expect(discontinuity == featureChannelDiscontinuity)
    }
}

