import Ably
import AblyChat

actor MockChatClient: ChatClient {
    let realtime: RealtimeClient
    nonisolated let clientOptions: ClientOptions
    nonisolated let rooms: Rooms

    init(realtime: RealtimeClient, clientOptions: ClientOptions?) {
        self.realtime = realtime
        self.clientOptions = clientOptions ?? .init()
        rooms = MockRooms(clientOptions: self.clientOptions)
    }

    nonisolated var connection: any Connection {
        fatalError("Not yet implemented")
    }

    nonisolated var clientID: String {
        fatalError("Not yet implemented")
    }
}

actor MockRooms: Rooms {
    let clientOptions: ClientOptions
    private var rooms = [String: MockRoom]()

    func get(roomID: String, options: RoomOptions) async throws -> any Room {
        if let room = rooms[roomID] {
            return room
        }
        let room = MockRoom(roomID: roomID, options: options)
        rooms[roomID] = room
        return room
    }

    func release(roomID _: String) async throws {
        fatalError("Not yet implemented")
    }

    init(clientOptions: ClientOptions) {
        self.clientOptions = clientOptions
    }
}

actor MockRoom: Room {
    private let clientID = "AblyTest"

    nonisolated let roomID: String
    nonisolated let options: RoomOptions

    init(roomID: String, options: RoomOptions) {
        self.roomID = roomID
        self.options = options
    }

    nonisolated lazy var messages: any Messages = MockMessages(clientID: clientID, roomID: roomID)

    nonisolated lazy var presence: any Presence = MockPresence(clientID: clientID, roomID: roomID)

    nonisolated lazy var reactions: any RoomReactions = MockRoomReactions(clientID: clientID, roomID: roomID)

    nonisolated lazy var typing: any Typing = MockTyping(clientID: clientID, roomID: roomID)

    nonisolated lazy var occupancy: any Occupancy = MockOccupancy(clientID: clientID, roomID: roomID)

    nonisolated lazy var status: any RoomStatus = MockRoomStatus(clientID: clientID, roomID: roomID)

    func attach() async throws {
        fatalError("Not yet implemented")
    }

    func detach() async throws {
        fatalError("Not yet implemented")
    }
}

actor MockMessages: Messages {
    let clientID: String
    let roomID: String
    let channel: RealtimeChannelProtocol

    private var mockSubscriptions: [MockSubscription<Message>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
        channel = MockRealtime.Channel()
    }

    private func createSubscription() -> MockSubscription<Message> {
        let subscription = MockSubscription<Message>(randomElement: {
            Message(
                timeserial: "\(Date().timeIntervalSince1970)",
                clientID: MockStrings.names.randomElement()!,
                roomID: self.roomID,
                text: MockStrings.randomPhrase(),
                createdAt: Date(),
                metadata: [:],
                headers: [:]
            )
        }, interval: 3)
        mockSubscriptions.append(subscription)
        return subscription
    }

    func subscribe(bufferingPolicy _: BufferingPolicy) async -> MessageSubscription {
        MessageSubscription(mockAsyncSequence: createSubscription()) { _ in
            MockMessagesPaginatedResult(clientID: self.clientID, roomID: self.roomID)
        }
    }

    func get(options _: QueryOptions) async throws -> any PaginatedResult<Message> {
        MockMessagesPaginatedResult(clientID: clientID, roomID: roomID)
    }

    func send(params: SendMessageParams) async throws -> Message {
        let message = Message(
            timeserial: "\(Date().timeIntervalSince1970)",
            clientID: clientID,
            roomID: roomID,
            text: params.text,
            createdAt: Date(),
            metadata: params.metadata ?? [:],
            headers: params.headers ?? [:]
        )
        for subscription in mockSubscriptions {
            subscription.emit(message)
        }
        return message
    }

    func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("Not yet implemented")
    }
}

actor MockRoomReactions: RoomReactions {
    let clientID: String
    let roomID: String
    let channel: RealtimeChannelProtocol

    private var mockSubscriptions: [MockSubscription<Reaction>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
        channel = MockRealtime.Channel()
    }

    private func createSubscription() -> MockSubscription<Reaction> {
        let subscription = MockSubscription<Reaction>(randomElement: {
            Reaction(
                type: ReactionType.allCases.randomElement()!.rawValue,
                metadata: [:],
                headers: [:],
                createdAt: Date(),
                clientID: self.clientID,
                isSelf: false
            )
        }, interval: Double.random(in: 0.1 ... 0.5))
        mockSubscriptions.append(subscription)
        return subscription
    }

    func send(params: SendReactionParams) async throws {
        let reaction = Reaction(
            type: params.type,
            metadata: [:],
            headers: [:],
            createdAt: Date(),
            clientID: clientID,
            isSelf: false
        )
        for subscription in mockSubscriptions {
            subscription.emit(reaction)
        }
    }

    func subscribe(bufferingPolicy _: BufferingPolicy) -> Subscription<Reaction> {
        .init(mockAsyncSequence: createSubscription())
    }

    func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("Not yet implemented")
    }
}

actor MockTyping: Typing {
    let clientID: String
    let roomID: String
    let channel: RealtimeChannelProtocol

    private var mockSubscriptions: [MockSubscription<TypingEvent>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
        channel = MockRealtime.Channel()
    }

    private func createSubscription() -> MockSubscription<TypingEvent> {
        let subscription = MockSubscription<TypingEvent>(randomElement: {
            TypingEvent(currentlyTyping: [
                MockStrings.names.randomElement()!,
                MockStrings.names.randomElement()!,
            ])
        }, interval: 2)
        mockSubscriptions.append(subscription)
        return subscription
    }

    func subscribe(bufferingPolicy _: BufferingPolicy) -> Subscription<TypingEvent> {
        .init(mockAsyncSequence: createSubscription())
    }

    func get() async throws -> Set<String> {
        Set(MockStrings.names.shuffled().prefix(2))
    }

    func start() async throws {
        for subscription in mockSubscriptions {
            subscription.emit(TypingEvent(currentlyTyping: [clientID]))
        }
    }

    func stop() async throws {
        for subscription in mockSubscriptions {
            subscription.emit(TypingEvent(currentlyTyping: []))
        }
    }

    func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("Not yet implemented")
    }
}

actor MockPresence: Presence {
    let clientID: String
    let roomID: String

    private var mockSubscriptions: [MockSubscription<PresenceEvent>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
    }

    private func createSubscription() -> MockSubscription<PresenceEvent> {
        let subscription = MockSubscription<PresenceEvent>(randomElement: {
            PresenceEvent(
                action: [.enter, .leave].randomElement()!,
                clientID: MockStrings.names.randomElement()!,
                timestamp: Date(),
                data: nil
            )
        }, interval: 5)
        mockSubscriptions.append(subscription)
        return subscription
    }

    func get() async throws -> [PresenceMember] {
        MockStrings.names.shuffled().map { name in
            PresenceMember(
                clientID: name,
                data: ["foo": "bar"],
                action: .present,
                extras: nil,
                updatedAt: Date()
            )
        }
    }

    func get(params _: PresenceQuery?) async throws -> [PresenceMember] {
        MockStrings.names.shuffled().map { name in
            PresenceMember(
                clientID: name,
                data: ["foo": "bar"],
                action: .present,
                extras: nil,
                updatedAt: Date()
            )
        }
    }

    func isUserPresent(clientID _: String) async throws -> Bool {
        fatalError("Not yet implemented")
    }

    func enter() async throws {
        for subscription in mockSubscriptions {
            subscription.emit(
                PresenceEvent(
                    action: .enter,
                    clientID: clientID,
                    timestamp: Date(),
                    data: nil
                )
            )
        }
    }

    func enter(data: PresenceData) async throws {
        for subscription in mockSubscriptions {
            subscription.emit(
                PresenceEvent(
                    action: .enter,
                    clientID: clientID,
                    timestamp: Date(),
                    data: data
                )
            )
        }
    }

    func update() async throws {
        fatalError("Not yet implemented")
    }

    func update(data _: PresenceData) async throws {
        fatalError("Not yet implemented")
    }

    func leave() async throws {
        for subscription in mockSubscriptions {
            subscription.emit(
                PresenceEvent(
                    action: .leave,
                    clientID: clientID,
                    timestamp: Date(),
                    data: nil
                )
            )
        }
    }

    func leave(data: PresenceData) async throws {
        for subscription in mockSubscriptions {
            subscription.emit(
                PresenceEvent(
                    action: .leave,
                    clientID: clientID,
                    timestamp: Date(),
                    data: data
                )
            )
        }
    }

    func subscribe(event _: PresenceEventType) -> Subscription<PresenceEvent> {
        .init(mockAsyncSequence: createSubscription())
    }

    func subscribe(events _: [PresenceEventType]) -> Subscription<PresenceEvent> {
        .init(mockAsyncSequence: createSubscription())
    }

    func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("Not yet implemented")
    }
}

actor MockOccupancy: Occupancy {
    let clientID: String
    let roomID: String
    let channel: RealtimeChannelProtocol

    private var mockSubscriptions: [MockSubscription<OccupancyEvent>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
        channel = MockRealtime.Channel()
    }

    private func createSubscription() -> MockSubscription<OccupancyEvent> {
        let subscription = MockSubscription<OccupancyEvent>(randomElement: {
            let random = Int.random(in: 1 ... 10)
            return OccupancyEvent(connections: random, presenceMembers: Int.random(in: 0 ... random))
        }, interval: 1)
        mockSubscriptions.append(subscription)
        return subscription
    }

    func subscribe(bufferingPolicy _: BufferingPolicy) async -> Subscription<OccupancyEvent> {
        .init(mockAsyncSequence: createSubscription())
    }

    func get() async throws -> OccupancyEvent {
        OccupancyEvent(connections: 10, presenceMembers: 5)
    }

    func subscribeToDiscontinuities() -> Subscription<ARTErrorInfo> {
        fatalError("Not yet implemented")
    }
}

actor MockRoomStatus: RoomStatus {
    let clientID: String
    let roomID: String

    var current: RoomLifecycle
    var error: ARTErrorInfo?

    private var mockSubscriptions: [MockSubscription<RoomStatusChange>] = []

    init(clientID: String, roomID: String) {
        self.clientID = clientID
        self.roomID = roomID
        current = .initialized
    }

    private func createSubscription() -> MockSubscription<RoomStatusChange> {
        let subscription = MockSubscription<RoomStatusChange>(randomElement: {
            RoomStatusChange(current: [.attached, .attached, .attached, .attached, .attaching(error: nil), .attaching(error: nil), .suspended(error: .createUnknownError())].randomElement()!, previous: .attaching(error: nil))
        }, interval: 8)
        mockSubscriptions.append(subscription)
        return subscription
    }

    func onChange(bufferingPolicy _: BufferingPolicy) async -> Subscription<RoomStatusChange> {
        .init(mockAsyncSequence: createSubscription())
    }
}
