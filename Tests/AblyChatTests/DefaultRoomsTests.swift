@testable import AblyChat
import Testing

struct DefaultRoomsTests {
    // @spec CHA-RC1a
    @Test
    func get_returnsRoomWithGivenID() async throws {
        // Given: an instance of DefaultRooms
        let realtime = MockRealtime.create(channels: .init(channels: [.init(name: "basketball::$chat::$chatMessages")]))
        let rooms = DefaultRooms(realtime: realtime, clientOptions: .init(), logger: TestLogger())

        // When: get(roomID:options:) is called
        let roomID = "basketball"
        let options = RoomOptions()
        let room = try await rooms.get(roomID: roomID, options: options)

        // Then: It returns a DefaultRoom instance that uses the same Realtime instance, with the given ID and options
        let defaultRoom = try #require(room as? DefaultRoom)
        #expect(defaultRoom.testsOnly_realtime === realtime)
        #expect(defaultRoom.roomID == roomID)
        #expect(defaultRoom.options == options)
    }

    // @spec CHA-RC1b
    @Test
    func get_returnsExistingRoomWithGivenID() async throws {
        // Given: an instance of DefaultRooms, on which get(roomID:options:) has already been called with a given ID
        let realtime = MockRealtime.create(channels: .init(channels: [.init(name: "basketball::$chat::$chatMessages")]))
        let rooms = DefaultRooms(realtime: realtime, clientOptions: .init(), logger: TestLogger())

        let roomID = "basketball"
        let options = RoomOptions()
        let firstRoom = try await rooms.get(roomID: roomID, options: options)

        // When: get(roomID:options:) is called with the same room ID
        let secondRoom = try await rooms.get(roomID: roomID, options: options)

        // Then: It returns the same room object
        #expect(secondRoom === firstRoom)
    }

    // @spec CHA-RC1c
    @Test
    func get_throwsErrorWhenOptionsDoNotMatch() async throws {
        // Given: an instance of DefaultRooms, on which get(roomID:options:) has already been called with a given ID and options
        let realtime = MockRealtime.create(channels: .init(channels: [.init(name: "basketball::$chat::$chatMessages")]))
        let rooms = DefaultRooms(realtime: realtime, clientOptions: .init(), logger: TestLogger())

        let roomID = "basketball"
        let options = RoomOptions()
        _ = try await rooms.get(roomID: roomID, options: options)

        // When: get(roomID:options:) is called with the same ID but different options
        let differentOptions = RoomOptions(presence: .init(subscribe: false))

        let caughtError: Error?
        do {
            _ = try await rooms.get(roomID: roomID, options: differentOptions)
            caughtError = nil
        } catch {
            caughtError = error
        }

        // Then: It throws an inconsistentRoomOptions error
        #expect(isChatError(caughtError, withCode: .inconsistentRoomOptions))
    }
}
