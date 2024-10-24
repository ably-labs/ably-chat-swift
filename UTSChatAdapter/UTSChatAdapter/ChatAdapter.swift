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
        
        case "ChatClient#rooms":
            guard let chatClientRef = idToChatClient[rpcParams.refId] else {
                print("ChatClient with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let rooms = chatClientRef.rooms // Rooms
            let fieldRefId = generateId()
            idToRooms[fieldRefId] = rooms
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "ChatClient#realtime":
            guard let chatClientRef = idToChatClient[rpcParams.refId] else {
                print("ChatClient with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let realtime = chatClientRef.realtime // Realtime
            let fieldRefId = generateId()
            idToRealtime[fieldRefId] = realtime
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "ChatClient#connection":
            guard let chatClientRef = idToChatClient[rpcParams.refId] else {
                print("ChatClient with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let connection = chatClientRef.connection // Connection
            let fieldRefId = generateId()
            idToConnection[fieldRefId] = connection
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "ChatClient#clientOptions":
            guard let chatClientRef = idToChatClient[rpcParams.refId] else {
                print("ChatClient with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let clientOptions = chatClientRef.clientOptions // ClientOptions
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(clientOptions))\"}")
            
        case "ChatClient#clientId":
            guard let chatClientRef = idToChatClient[rpcParams.refId] else {
                print("ChatClient with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let clientID = chatClientRef.clientID // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(clientID)\"}")
            
        case "ConnectionStatus#current":
            guard let connectionStatusRef = idToConnectionStatus[rpcParams.refId] else {
                print("ConnectionStatus with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let current = connectionStatusRef.current // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(current)\"}")
            
        case "ConnectionStatus.onChange":
            guard let connectionStatusRef = idToConnectionStatus[rpcParams.refId] else {
                print("ConnectionStatus with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = connectionStatusRef.onChange(bufferingPolicy: .unbounded)
            let callback: (ConnectionStatusChange) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await change in subscription {
                    callback(change)
                }
            }
            let resultRefId = generateId()
            idToOnConnectionStatusChange[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Connection#status":
            guard let connectionRef = idToConnection[rpcParams.refId] else {
                print("Connection with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let status = connectionRef.status // ConnectionStatus
            let fieldRefId = generateId()
            idToConnectionStatus[fieldRefId] = status
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Message.equal":
            let message = Message.from(rpcParams["message"])
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = try messageRef.equal(message: message) // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "Message.before":
            let message = Message.from(rpcParams["message"])
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = try messageRef.before(message: message) // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "Message.after":
            let message = Message.from(rpcParams["message"])
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = try messageRef.after(message: message) // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "Message#timeserial":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let timeserial = messageRef.timeserial // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(timeserial)\"}")
            
        case "Message#text":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let text = messageRef.text // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(text)\"}")
            
        case "Message#roomId":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let roomID = messageRef.roomID // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(roomID)\"}")
            
        case "Message#metadata":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let metadata = messageRef.metadata // object
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(metadata))\"}")
            
        case "Message#headers":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let headers = messageRef.headers // object
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(headers))\"}")
            
        case "Message#clientId":
            guard let messageRef = idToMessage[rpcParams.refId] else {
                print("Message with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let clientID = messageRef.clientID // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(clientID)\"}")
            
        case "Messages.send":
            let options = SendMessageParams.from(rpcParams["options"])
            guard let messagesRef = idToMessages[rpcParams.refId] else {
                print("Messages with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let message = try await messagesRef.send(options: options) // Message
            let resultRefId = generateId()
            idToMessage[resultRefId] = message
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Messages.get":
            let options = QueryOptions.from(rpcParams["options"])
            guard let messagesRef = idToMessages[rpcParams.refId] else {
                print("Messages with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let paginatedResultMessage = try await messagesRef.get(options: options) // PaginatedResultMessage
            let resultRefId = generateId()
            idToPaginatedResultMessage[resultRefId] = paginatedResultMessage
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Messages#channel":
            guard let messagesRef = idToMessages[rpcParams.refId] else {
                print("Messages with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let channel = messagesRef.channel // RealtimeChannel
            let fieldRefId = generateId()
            idToRealtimeChannel[fieldRefId] = channel
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Messages.subscribe":
            guard let messagesRef = idToMessages[rpcParams.refId] else {
                print("Messages with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = try await messagesRef.subscribe(bufferingPolicy: .unbounded)
            let callback: (Message) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await event in subscription {
                    callback(event)
                }
            }
            let resultRefId = generateId()
            idToMessageSubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Messages.onDiscontinuity":
            guard let messagesRef = idToMessages[rpcParams.refId] else {
                print("Messages with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await messagesRef.subscribeToDiscontinuities()
            let callback: (AblyErrorInfo?) -> Void = {
                if let param = $0 {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\(param.json())"))
                } else {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                }
            }
            Task {
                for await reason in subscription {
                    callback(reason)
                }
            }
            let resultRefId = generateId()
            idToOnDiscontinuitySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "MessageSubscriptionResponse.getPreviousMessages":
            let params = QueryOptions.from(rpcParams["params"])
            guard let messageSubscriptionRef = idToMessageSubscription[rpcParams.refId] else {
                print("MessageSubscription with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let paginatedResultMessage = try await messageSubscriptionRef.getPreviousMessages(params: params) // PaginatedResultMessage
            let resultRefId = generateId()
            idToPaginatedResultMessage[resultRefId] = paginatedResultMessage
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Occupancy.get":
            guard let occupancyRef = idToOccupancy[rpcParams.refId] else {
                print("Occupancy with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let occupancyEvent = try await occupancyRef.get() // OccupancyEvent
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(occupancyEvent))\"}")
            
        case "Occupancy#channel":
            guard let occupancyRef = idToOccupancy[rpcParams.refId] else {
                print("Occupancy with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let channel = occupancyRef.channel // RealtimeChannel
            let fieldRefId = generateId()
            idToRealtimeChannel[fieldRefId] = channel
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Occupancy.subscribe":
            guard let occupancyRef = idToOccupancy[rpcParams.refId] else {
                print("Occupancy with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await occupancyRef.subscribe(bufferingPolicy: .unbounded)
            let callback: (OccupancyEvent) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await event in subscription {
                    callback(event)
                }
            }
            let resultRefId = generateId()
            idToOccupancySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Occupancy.onDiscontinuity":
            guard let occupancyRef = idToOccupancy[rpcParams.refId] else {
                print("Occupancy with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await occupancyRef.subscribeToDiscontinuities()
            let callback: (AblyErrorInfo?) -> Void = {
                if let param = $0 {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\(param.json())"))
                } else {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                }
            }
            Task {
                for await reason in subscription {
                    callback(reason)
                }
            }
            let resultRefId = generateId()
            idToOnDiscontinuitySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "PaginatedResult.isLast":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = paginatedResultRef.isLast() // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "PaginatedResult.hasNext":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = paginatedResultRef.hasNext() // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "PaginatedResult.next":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let paginatedResult = try await paginatedResultRef.next() // PaginatedResult
            let resultRefId = generateId()
            idToPaginatedResult[resultRefId] = paginatedResult
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "PaginatedResult.first":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let paginatedResult = try await paginatedResultRef.first() // PaginatedResult
            let resultRefId = generateId()
            idToPaginatedResult[resultRefId] = paginatedResult
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "PaginatedResult.current":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let paginatedResult = try await paginatedResultRef.current() // PaginatedResult
            let resultRefId = generateId()
            idToPaginatedResult[resultRefId] = paginatedResult
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "PaginatedResult#items":
            guard let paginatedResultRef = idToPaginatedResult[rpcParams.refId] else {
                print("PaginatedResult with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let items = paginatedResultRef.items // object
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(items))\"}")
            
        case "Presence.update":
            let data = PresenceDataWrapper.from(rpcParams["data"])
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await presenceRef.update(data: data) // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Presence.leave":
            let data = PresenceDataWrapper.from(rpcParams["data"])
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await presenceRef.leave(data: data) // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Presence.isUserPresent":
            let clientID = String.from(rpcParams["clientId"])
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let bool = try await presenceRef.isUserPresent(clientID: clientID) // Bool
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(bool)\"}")
            
        case "Presence.get":
            let params = RealtimePresenceParams.from(rpcParams["params"])
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let presenceMember = try await presenceRef.get(params: params) // PresenceMember
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(presenceMember))\"}")
            
        case "Presence.enter":
            let data = PresenceDataWrapper.from(rpcParams["data"])
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await presenceRef.enter(data: data) // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Presence.subscribe_listener":
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await presenceRef.subscribeAll()
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
            
        case "Presence.onDiscontinuity":
            guard let presenceRef = idToPresence[rpcParams.refId] else {
                print("Presence with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await presenceRef.subscribeToDiscontinuities()
            let callback: (AblyErrorInfo?) -> Void = {
                if let param = $0 {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\(param.json())"))
                } else {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                }
            }
            Task {
                for await reason in subscription {
                    callback(reason)
                }
            }
            let resultRefId = generateId()
            idToOnDiscontinuitySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "RoomReactions.send":
            let params = SendReactionParams.from(rpcParams["params"])
            guard let roomReactionsRef = idToRoomReactions[rpcParams.refId] else {
                print("RoomReactions with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await roomReactionsRef.send(params: params) // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "RoomReactions#channel":
            guard let roomReactionsRef = idToRoomReactions[rpcParams.refId] else {
                print("RoomReactions with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let channel = roomReactionsRef.channel // RealtimeChannel
            let fieldRefId = generateId()
            idToRealtimeChannel[fieldRefId] = channel
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "RoomReactions.subscribe":
            guard let roomReactionsRef = idToRoomReactions[rpcParams.refId] else {
                print("RoomReactions with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await roomReactionsRef.subscribe(bufferingPolicy: .unbounded)
            let callback: (Reaction) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await reaction in subscription {
                    callback(reaction)
                }
            }
            let resultRefId = generateId()
            idToRoomReactionsSubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "RoomReactions.onDiscontinuity":
            guard let roomReactionsRef = idToRoomReactions[rpcParams.refId] else {
                print("RoomReactions with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await roomReactionsRef.subscribeToDiscontinuities()
            let callback: (AblyErrorInfo?) -> Void = {
                if let param = $0 {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\(param.json())"))
                } else {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                }
            }
            Task {
                for await reason in subscription {
                    callback(reason)
                }
            }
            let resultRefId = generateId()
            idToOnDiscontinuitySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "RoomStatus#current":
            guard let roomStatusRef = idToRoomStatus[rpcParams.refId] else {
                print("RoomStatus with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let current = await roomStatusRef.current // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(current)\"}")
            
        case "RoomStatus.onChange":
            guard let roomStatusRef = idToRoomStatus[rpcParams.refId] else {
                print("RoomStatus with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await roomStatusRef.onChange(bufferingPolicy: .unbounded)
            let callback: (RoomStatusChange) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await change in subscription {
                    callback(change)
                }
            }
            let resultRefId = generateId()
            idToOnRoomStatusChange[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Room.options":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let roomOptions = roomRef.options() // RoomOptions
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(roomOptions))\"}")
            
        case "Room.detach":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await roomRef.detach() // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Room.attach":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await roomRef.attach() // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Room#typing":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let typing = roomRef.typing // Typing
            let fieldRefId = generateId()
            idToTyping[fieldRefId] = typing
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Room#status":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let status = roomRef.status // RoomStatus
            let fieldRefId = generateId()
            idToRoomStatus[fieldRefId] = status
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Room#roomId":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let roomID = roomRef.roomID // string
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(roomID)\"}")
            
        case "Room#reactions":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let reactions = roomRef.reactions // RoomReactions
            let fieldRefId = generateId()
            idToRoomReactions[fieldRefId] = reactions
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Room#presence":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let presence = roomRef.presence // Presence
            let fieldRefId = generateId()
            idToPresence[fieldRefId] = presence
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Room#occupancy":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let occupancy = roomRef.occupancy // Occupancy
            let fieldRefId = generateId()
            idToOccupancy[fieldRefId] = occupancy
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Room#messages":
            guard let roomRef = idToRoom[rpcParams.refId] else {
                print("Room with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let messages = roomRef.messages // Messages
            let fieldRefId = generateId()
            idToMessages[fieldRefId] = messages
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Rooms.get":
            let roomID = String.from(rpcParams["roomId"])
            let options = RoomOptions.from(rpcParams["options"])
            guard let roomsRef = idToRooms[rpcParams.refId] else {
                print("Rooms with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let room = try await roomsRef.get(roomID: roomID, options: options) // Room
            let resultRefId = generateId()
            idToRoom[resultRefId] = room
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Rooms.release":
            let roomID = String.from(rpcParams["roomId"])
            guard let roomsRef = idToRooms[rpcParams.refId] else {
                print("Rooms with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await roomsRef.release(roomID: roomID) // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Rooms#clientOptions":
            guard let roomsRef = idToRooms[rpcParams.refId] else {
                print("Rooms with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let clientOptions = roomsRef.clientOptions // ClientOptions
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(JSON.from(clientOptions))\"}")
            
        case "Typing.stop":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await typingRef.stop() // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Typing.start":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            try await typingRef.start() // Void
            return jsonRpcResult(rpcParams.callbackId, "{}")
            
        case "Typing.get":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let string = try await typingRef.get() // String
            return jsonRpcResult(rpcParams.callbackId, "{\"response\": \"\(string)\"}")
            
        case "Typing#channel":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let channel = typingRef.channel // RealtimeChannel
            let fieldRefId = generateId()
            idToRealtimeChannel[fieldRefId] = channel
            return jsonRpcResult(rpcParams.callbackId, "{\"refId\":\"\(fieldRefId)\"}")
            
        case "Typing.subscribe":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await typingRef.subscribe(bufferingPolicy: .unbounded)
            let callback: (TypingEvent) -> Void = {
                self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\($0.json())"))
            }
            Task {
                for await event in subscription {
                    callback(event)
                }
            }
            let resultRefId = generateId()
            idToTypingSubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
        case "Typing.onDiscontinuity":
            guard let typingRef = idToTyping[rpcParams.refId] else {
                print("Typing with `refId == \(rpcParams.refId)` doesn't exist.")
                return nil
            }
            let subscription = await typingRef.subscribeToDiscontinuities()
            let callback: (AblyErrorInfo?) -> Void = {
                if let param = $0 {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "\(param.json())"))
                } else {
                    self.webSocket.send(text: jsonRpcCallback(rpcParams.callbackId, "{}"))
                }
            }
            Task {
                for await reason in subscription {
                    callback(reason)
                }
            }
            let resultRefId = generateId()
            idToOnDiscontinuitySubscription[resultRefId] = subscription
            return jsonRpcResult(rpcParams.requestId, "{\"refId\":\"\(resultRefId)\"}")
            
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
