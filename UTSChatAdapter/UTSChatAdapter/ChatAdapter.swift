import Ably
import AblyChat

/**
 * Unified Test Suite adapter for swift Chat SDK
 */
class ChatAdapter {
    // Runtime SDK objects storage
    private var idToChannel = [String: ARTRealtimeChannel]()
    private var idToChannels = [String: ARTRealtimeChannels]()
    private var idToChatClient = [String: ChatClient]()
    private var idToConnection = [String: Connection]()
    private var idToConnectionStatus = [String: ConnectionStatus]()
    private var idToMessage = [String: Message]()
    private var idToMessages = [String: Messages]()
    private var idToOccupancy = [String: Occupancy]()
    private var idToPaginatedResult = [String: any PaginatedResult]()
    private var idToPresence = [String: Presence]()
    private var idToRealtime = [String: RealtimeClient]()
    private var idToRealtimeChannel = [String: RealtimeChannelProtocol]()
    private var idToRoom = [String: Room]()
    private var idToRoomReactions = [String: RoomReactions]()
    private var idToRooms = [String: Rooms]()
    private var idToRoomStatus = [String: RoomStatus]()
    private var idToTyping = [String: Typing]()
    private var idToPaginatedResultMessage = [String: any PaginatedResultMessage]()
    private var idToMessageSubscription = [String: MessageSubscription]()
    private var idToOnConnectionStatusChange = [String: OnConnectionStatusChange]()
    private var idToOnDiscontinuitySubscription = [String: OnDiscontinuitySubscription]()
    private var idToOccupancySubscription = [String: OccupancySubscription]()
    private var idToRoomReactionsSubscription = [String: RoomReactionsSubscription]()
    private var idToOnRoomStatusChange = [String: OnRoomStatusChange]()
    private var idToTypingSubscription = [String: TypingSubscription]()
    private var idToPresenceSubscription = [String: PresenceSubscription]()
    
    private var webSocket: WebSocketWrapper
    
    init(webSocket: WebSocketWrapper) {
        self.webSocket = webSocket
    }
    
    func handleRpcCall(rpcParams: JSON) async throws -> String? {
        guard let method = rpcParams["method"] as? String else {
            print("Method not found.")
            return nil
        }
        
        switch method {
        
        // GENERATED CONTENT BEGIN
        // ...
        // GENERATED CONTENT END
        
        // Custom fields implementation (see `Schema.skipPaths` for reasons):
        
        case "ChatClient":
            let requestId = rpcParams["id"] as! String
            let chatOptions = ClientOptions.from(rpcParams["clientOptions"])
            let realtimeOptions = ARTClientOptions.from(rpcParams["realtimeClientOptions"])
            let realtime = ARTRealtime(options: realtimeOptions)
            let chatClient = DefaultChatClient(realtime: realtime, clientOptions: chatOptions)
            let instanceId = generateId()
            idToChatClient[instanceId] = chatClient
            return jsonRpcResult(requestId, "{\"instanceId\":\"\(instanceId)\"}")
            
        // This field is optional and should be included in a corresponding json schema for automatic generation
        case "ConnectionStatus#error":
            let refId = rpcParams["refId"] as! String
            guard let instance = idToConnectionStatus[refId] else {
                print("Instance with this `refId` doesn't exist."); return nil;
            }
            if let error = instance.error { // ErrorInfo
                return jsonRpcResult(rpcParams["id"] as! String, "{\"response\": \"\(error.json())\"}")
            } else {
                return jsonRpcResult(rpcParams["id"] as! String, "{\"response\": \(NSNull()) }")
            }
            
        // This field is optional and should be included in a corresponding json schema for automatic generation
        case "Message#createdAt":
            let refId = rpcParams["refId"] as! String
            guard let message = idToMessage[refId] else {
                print("Message with `refId == \(refId)` doesn't exist.")
                return nil
            }
            if let createdAt = message.createdAt { // number
                return jsonRpcResult(rpcParams["id"] as! String, "{\"response\": \"\(createdAt)\"}")
            } else {
                return jsonRpcResult(rpcParams["id"] as! String, "{\"response\": \(NSNull()) }")
            }
            
        // `events` is an array of strings in schema file which is not enougth for param auto-generation (should be `PresenceEventType`)
        case "Presence.subscribe_eventsAndListener":
            guard let events = rpcParams["events"] as? [String] else {
                return nil
            }
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await presenceRef.subscribe(events: events.map { PresenceEventType.from($0) })
            let callback: (PresenceEvent) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await event in subscription {
                    callback(event)
                }
            }
            let resultRefId = generateId()
            idToPresenceSubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        default:
            print("Unknown method provided.")
            return nil
        }
    }
}
