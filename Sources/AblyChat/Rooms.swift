import Ably

public protocol Rooms: AnyObject, Sendable {
    func get(roomID: String, options: RoomOptions) async throws -> any Room
    func release(roomID: String) async throws
    var clientOptions: ClientOptions { get }
}

internal actor DefaultRooms: Rooms {
    private nonisolated let realtime: RealtimeClient
    private let chatAPI: ChatAPI

    #if DEBUG
        internal nonisolated var testsOnly_realtime: RealtimeClient {
            realtime
        }
    #endif

    internal nonisolated let clientOptions: ClientOptions

    private let logger: InternalLogger

    /// The set of rooms, keyed by room ID.
    private var rooms: [String: DefaultRoom] = [:]

    internal init(realtime: RealtimeClient, clientOptions: ClientOptions, logger: InternalLogger) {
        self.realtime = realtime
        self.clientOptions = clientOptions
        self.logger = logger
        chatAPI = ChatAPI(realtime: realtime)
    }

    internal func get(roomID: String, options: RoomOptions) throws -> any Room {
        // CHA-RC1b
        if let existingRoom = rooms[roomID] {
            if existingRoom.options != options {
                throw ARTErrorInfo(
                    chatError: .inconsistentRoomOptions(requested: options, existing: existingRoom.options)
                )
            }

            return existingRoom
        } else {
            let room = DefaultRoom(realtime: realtime, chatAPI: chatAPI, roomID: roomID, options: options, logger: logger)
            rooms[roomID] = room
            return room
        }
    }

    internal func release(roomID _: String) async throws {
        fatalError("Not yet implemented")
    }
}
