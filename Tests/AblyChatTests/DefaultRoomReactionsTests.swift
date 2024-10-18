@testable import AblyChat
import Testing

struct DefaultRoomReactionsTests {
    // @spec CHA-ER1
    @Test
    func init_channelNameIsSetAsReactionsChannelName() async throws {
        // Given
        let realtime = MockRealtime.create(channels: .init(channels: [.init(name: "basketball::$chat::$reactions")]))

        // When
        let defaultRoomReactions = await DefaultRoomReactions(realtime: realtime, roomID: "basketball", logger: TestLogger())

        // Then
        await #expect(defaultRoomReactions.channel.name == "basketball::$chat::$reactions")
    }

    // @spec CHA-ER3a
    @Test
    func reactionsAreSentInTheCorrectFormat() async throws {
        // channel name and roomID values are arbitrary
        // Given
        let channel = MockRealtimeChannel(name: "basketball::$chat::$reactions")
        let realtime = MockRealtime.create(channels: .init(channels: [channel]))
        let defaultRoomReactions = await DefaultRoomReactions(realtime: realtime, roomID: "basketball", logger: TestLogger())

        let sendReactionParams = SendReactionParams(
            type: "like",
            metadata: ["test": MetadataValue.string("test")],
            headers: ["test": HeadersValue.string("test")]
        )

        // When
        try await defaultRoomReactions.send(params: sendReactionParams)

        // Then
        #expect(channel.lastMessagePublishedName == RoomReactionEvents.reaction.rawValue)
        #expect(channel.lastMessagePublishedData as? [String: String] == sendReactionParams.asQueryItems())
        #expect(channel.lastMessagePublishedExtras as? Dictionary == ["headers": sendReactionParams.headers])
    }

    // @spec CHA-ER4
    @Test
    func subscribe_returnsSubscription() async throws {
        // all setup values here are arbitrary
        // Given
        let realtime = MockRealtime.create(channels: .init(channels: [.init(name: "basketball::$chat::$reactions")]))
        let defaultRoomReactions = await DefaultRoomReactions(realtime: realtime, roomID: "basketball", logger: TestLogger())

        // When
        let subscription: Subscription<Reaction>? = await defaultRoomReactions.subscribe(bufferingPolicy: .unbounded)

        // Then
        #expect(subscription != nil)
    }
}
