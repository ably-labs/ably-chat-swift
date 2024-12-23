import Ably
@testable import AblyChat
import Testing

struct DefaultRoomTypingTests {
    // @spec CHA-T1
    @Test
    func channelNameIsSetAsTypingIndicatorsChannelName() async throws {
        // Given
        let channel = MockRealtimeChannel(name: "basketball::$chat::$typingIndicators")
        let featureChannel = MockFeatureChannel(channel: channel)

        // When
        let defaultTyping = DefaultTyping(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger(), timeout: 5)

        // Then
        #expect(defaultTyping.channel.name == "basketball::$chat::$typingIndicators")
    }

    // @spec CHA-T2
    @Test
    func retrieveCurrentlyTypingClientIDs() async throws {
        // Given
        let typingPresence = MockRealtimePresence(["client1", "client2"].map { .init(clientId: $0) })
        let channel = MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", mockPresence: typingPresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultTyping = DefaultTyping(featureChannel: featureChannel, roomID: "basketball", clientID: "mockClientId", logger: TestLogger(), timeout: 5)

        // When
        let typingInfo = try await defaultTyping.get()

        // Then
        #expect(typingInfo.sorted() == ["client1", "client2"])
    }

    // @spec CHA-T4
    // @spec CHA-T5
    @Test
    func usersMayIndicateThatTheyHaveStartedOrStoppedTyping() async throws {
        // Given
        let typingPresence = MockRealtimePresence([])
        let channel = MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", mockPresence: typingPresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultTyping = DefaultTyping(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger(), timeout: 5)

        // CHA-T4

        // When
        try await defaultTyping.start()

        // Then
        var typingInfo = try await defaultTyping.get()
        #expect(typingInfo == ["client1"])

        // CHA-T5

        // When
        try await defaultTyping.stop()

        // Then
        typingInfo = try await defaultTyping.get()
        #expect(typingInfo.isEmpty)
    }

    // @spec CHA-T6
    @Test
    func usersMaySubscribeToTypingEvents() async throws {
        // Given
        let typingPresence = MockRealtimePresence([])
        let channel = MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", mockPresence: typingPresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultTyping = DefaultTyping(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger(), timeout: 5)

        // When
        let subscription = await defaultTyping.subscribe()
        subscription.emit(TypingEvent(currentlyTyping: ["client1"]))

        // Then
        let typingEvent = try #require(await subscription.first { _ in true })
        #expect(typingEvent.currentlyTyping == ["client1"])
    }

    // @spec CHA-T7
    @Test
    func onDiscontinuity() async throws {
        // Given
        let typingPresence = MockRealtimePresence([])
        let channel = MockRealtimeChannel(mockPresence: typingPresence)
        let featureChannel = MockFeatureChannel(channel: channel, resultOfWaitToBeAblePerformPresenceOperations: .success(()))
        let defaultTyping = DefaultTyping(featureChannel: featureChannel, roomID: "basketball", clientID: "client1", logger: TestLogger(), timeout: 5)

        // When: The feature channel emits a discontinuity through `onDiscontinuity`
        let featureChannelDiscontinuity = DiscontinuityEvent(error: ARTErrorInfo.createUnknownError()) // arbitrary error
        let discontinuitySubscription = await defaultTyping.onDiscontinuity()
        await featureChannel.emitDiscontinuity(featureChannelDiscontinuity)

        // Then: The DefaultOccupancy instance emits this discontinuity through `onDiscontinuity`
        let discontinuity = try #require(await discontinuitySubscription.first { _ in true })
        #expect(discontinuity == featureChannelDiscontinuity)
    }
}
