import Ably
@testable import AblyChat
import Testing

struct DefaultRoomTests {
    @Test
    func attach_attachesAllChannels_andSucceedsIfAllSucceed() async throws {
        // Given: a DefaultRoom instance with ID "basketball", with a Realtime client for which `attach(_:)` completes successfully if called on the following channels:
        //
        //  - basketball::$chat::$chatMessages
        //  - basketball::$chat::$typingIndicators
        //  - basketball::$chat::$reactions
        let channelsList = [
            MockRealtimeChannel(name: "basketball::$chat::$chatMessages", attachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", attachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$reactions", attachResult: .success),
        ]
        let channels = MockChannels(channels: channelsList)
        let realtime = MockRealtime.create(channels: channels)
        let room = DefaultRoom(realtime: realtime, roomID: "basketball", options: .init(), logger: TestLogger())

        let subscription = await room.lifecycle.onChange(bufferingPolicy: .unbounded)
        async let attachedStatusChange = subscription.first { $0.current == .attached }

        // When: `attach` is called on the room
        try await room.attach()

        // Then: `attach(_:)` is called on each of the channels, the room `attach` call succeeds, and the room transitions to ATTACHED
        for channel in channelsList {
            #expect(channel.attachCallCounter.isNonZero)
        }

        #expect(await room.lifecycle.status == .attached)
        #expect(try #require(await attachedStatusChange).current == .attached)
    }

    @Test
    func attach_attachesAllChannels_andFailsIfOneFails() async throws {
        // Given: a DefaultRoom instance, with a Realtime client for which `attach(_:)` completes successfully if called on the following channels:
        //
        //   - basketball::$chat::$chatMessages
        //   - basketball::$chat::$typingIndicators
        //
        // and fails when called on channel basketball::$chat::$reactions
        let channelAttachError = ARTErrorInfo.createUnknownError() // arbitrary
        let channelsList = [
            MockRealtimeChannel(name: "basketball::$chat::$chatMessages", attachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", attachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$reactions", attachResult: .failure(channelAttachError)),
        ]
        let channels = MockChannels(channels: channelsList)
        let realtime = MockRealtime.create(channels: channels)
        let room = DefaultRoom(realtime: realtime, roomID: "basketball", options: .init(), logger: TestLogger())

        // When: `attach` is called on the room
        let roomAttachError: Error?
        do {
            try await room.attach()
            roomAttachError = nil
        } catch {
            roomAttachError = error
        }

        // Then: the room `attach` call fails with the same error as the channel `attach(_:)` call
        #expect(try #require(roomAttachError as? ARTErrorInfo) === channelAttachError)
    }

    @Test
    func detach_detachesAllChannels_andSucceedsIfAllSucceed() async throws {
        // Given: a DefaultRoom instance with ID "basketball", with a Realtime client for which `detach(_:)` completes successfully if called on the following channels:
        //
        //  - basketball::$chat::$chatMessages
        //  - basketball::$chat::$typingIndicators
        //  - basketball::$chat::$reactions
        let channelsList = [
            MockRealtimeChannel(name: "basketball::$chat::$chatMessages", detachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", detachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$reactions", detachResult: .success),
        ]
        let channels = MockChannels(channels: channelsList)
        let realtime = MockRealtime.create(channels: channels)
        let room = DefaultRoom(realtime: realtime, roomID: "basketball", options: .init(), logger: TestLogger())

        let subscription = await room.lifecycle.onChange(bufferingPolicy: .unbounded)
        async let detachedStatusChange = subscription.first { $0.current == .detached }

        // When: `detach` is called on the room
        try await room.detach()

        // Then: `detach(_:)` is called on each of the channels, the room `detach` call succeeds, and the room transitions to DETACHED
        for channel in channelsList {
            #expect(channel.detachCallCounter.isNonZero)
        }

        #expect(await room.lifecycle.status == .detached)
        #expect(try #require(await detachedStatusChange).current == .detached)
    }

    @Test
    func detach_detachesAllChannels_andFailsIfOneFails() async throws {
        // Given: a DefaultRoom instance, with a Realtime client for which `detach(_:)` completes successfully if called on the following channels:
        //
        //   - basketball::$chat::$chatMessages
        //   - basketball::$chat::$typingIndicators
        //
        // and fails when called on channel basketball::$chat::$reactions
        let channelDetachError = ARTErrorInfo.createUnknownError() // arbitrary
        let channelsList = [
            MockRealtimeChannel(name: "basketball::$chat::$chatMessages", detachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$typingIndicators", detachResult: .success),
            MockRealtimeChannel(name: "basketball::$chat::$reactions", detachResult: .failure(channelDetachError)),
        ]
        let channels = MockChannels(channels: channelsList)
        let realtime = MockRealtime.create(channels: channels)
        let room = DefaultRoom(realtime: realtime, roomID: "basketball", options: .init(), logger: TestLogger())

        // When: `detach` is called on the room
        let roomDetachError: Error?
        do {
            try await room.detach()
            roomDetachError = nil
        } catch {
            roomDetachError = error
        }

        // Then: the room `detach` call fails with the same error as the channel `detach(_:)` call
        #expect(try #require(roomDetachError as? ARTErrorInfo) === channelDetachError)
    }
}
