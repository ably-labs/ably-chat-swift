import Ably
import AblyChat

typealias ErrorInfo = ARTErrorInfo
typealias AblyErrorInfo = ARTErrorInfo
typealias RealtimePresenceParams = PresenceQuery
typealias PaginatedResultMessage = PaginatedResult<Message>
typealias OnConnectionStatusChange = Subscription<ConnectionStatusChange>
typealias OnDiscontinuitySubscription = Subscription<ARTErrorInfo>
typealias OccupancySubscription = Subscription<OccupancyEvent>
typealias RoomReactionsSubscription = Subscription<Reaction>
typealias OnRoomStatusChange = Subscription<RoomStatusChange>
typealias TypingSubscription = Subscription<TypingEvent>
typealias PresenceSubscription = Subscription<PresenceEvent>

struct PresenceDataWrapper { }

fileprivate let altTypesMap = [
    "void": "Void",
    "PresenceData": "\(PresenceDataWrapper.self)",
    "MessageSubscriptionResponse": "\(MessageSubscription.self)",
    "OnConnectionStatusChangeResponse": "OnConnectionStatusChange",
    "OccupancySubscriptionResponse": "OccupancySubscription",
    "RoomReactionsSubscriptionResponse": "RoomReactionsSubscription",
    "OnDiscontinuitySubscriptionResponse": "OnDiscontinuitySubscription",
    "OnRoomStatusChangeResponse": "OnRoomStatusChange",
    "TypingSubscriptionResponse": "TypingSubscription",
    "PresenceSubscriptionResponse": "PresenceSubscription",
    "MessageEventPayload": "\(Message.self)"
]

fileprivate let jsonPrimitiveTypesMap = [
    "string": "\(String.self)",
    "boolean": "\(Bool.self)",
    "number": "\(Int.self)"
]

fileprivate let altMethodsMap = [
    "onDiscontinuity": "subscribeToDiscontinuities",
    "subscribe_listener": "subscribeAll",
]

func isJsonPrimitiveType(_ typeName: String) -> Bool {
    jsonPrimitiveTypesMap.keys.contains([typeName])
}

func altTypeName(_ typeName: String) -> String {
    (altTypesMap[typeName] ?? jsonPrimitiveTypesMap[typeName]) ?? typeName
}

func altMethodName(_ methodName: String) -> String {
    altMethodsMap[methodName] ?? methodName
}

extension Message {
    public func before(message: Message) throws -> Bool {
        try isBefore(message)
    }
    
    public func after(message: Message) throws -> Bool {
        try isAfter(message)
    }

    public func equal(message: Message) throws -> Bool {
        try isEqual(message)
    }
}

extension Messages {
    func send(options: SendMessageParams) async throws -> Message {
        try await send(params: options)
    }
}

extension String {
    func bigD() -> String {
        replacingOccurrences(of: "Id", with: "ID")
    }
}

extension Room {
    func options() -> RoomOptions { options }
}

extension PaginatedResult {
    func hasNext() -> Bool { hasNext }
    func isLast() -> Bool { isLast }
    func next() async throws -> (any PaginatedResult<T>)? { try await next }
    func first() async throws -> (any PaginatedResult<T>)? { try await first }
    func current() async throws -> (any PaginatedResult<T>)? { try await current }
}

extension Presence {
    func subscribeAll() async -> Subscription<PresenceEvent> {
        await subscribe(events: [.enter, .leave, .present, .update])
    }
}

extension Schema {
    // These paths were not yet implemented in SDK or require custom implementation:
    static let skipPaths = [
        "ChatClient", // custom constructor with realtime instance
        "ChatClient#logger", // not exposed
        "ConnectionStatus#error", // optional
        "Presence#channel", // not implemented
        "RoomStatus#error", // not available directly (via lifecycle object)
        "Message#createdAt", // optional
        "Presence.subscribe_eventsAndListener", // impossible to infer param type from `string`
        
        "ChatClient.addReactAgent",
        
        "Messages.unsubscribeAll",
        "Presence.unsubscribeAll",
        "Occupancy.unsubscribeAll",
        "RoomReactions.unsubscribeAll",
        "Typing.unsubscribeAll",
        
        "TypingSubscriptionResponse.unsubscribe",
        "MessageSubscriptionResponse.unsubscribe",
        "OccupancySubscriptionResponse.unsubscribe",
        "PresenceSubscriptionResponse.unsubscribe",
        "PresenceSubscriptionResponse.unsubscribe",
        "RoomReactionsSubscriptionResponse.unsubscribe",
        
        "OnConnectionStatusChangeResponse.off",
        "OnDiscontinuitySubscriptionResponse.off",
        "OnRoomStatusChangeResponse.off",
        
        "ConnectionStatus.offAll",
        "RoomStatus.offAll",

        "Logger.error",
        "Logger.trace",
        "Logger.info",
        "Logger.debug",
        "Logger.warn",
    ]
}
