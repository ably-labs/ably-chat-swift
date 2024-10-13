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
            
        default:
            print("Unknown method provided.")
            return nil
        }
    }
}
