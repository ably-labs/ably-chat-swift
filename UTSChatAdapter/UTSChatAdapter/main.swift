import Foundation

func serve() async throws {
    let webSocket = WebSocketWrapper()
    let adapter = ChatAdapter(webSocket: webSocket)
    
    try await webSocket.start { message in
        var result: String? = nil

        guard let params = jsonFromWebSocketMessage(message) else {
            print("Websocket message can't be processed.")
            return
        }
        result = try await adapter.handleRpcCall(rpcParams: params)

        if result != nil {
            webSocket.send(text: result!)
        }
    }
}

if CommandLine.hasParam("generate") {
    ChatAdapterGenerator().generate()
}
else {
    Task {
        do {
            try await serve()
        } catch {
            print("Exiting due to fatal error: \(error)") // TODO: replace with logger
        }
    }
}
