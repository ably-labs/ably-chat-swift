import Foundation

final class WebSocketWrapper: NSObject, URLSessionWebSocketDelegate {
    
    private var webSocket: URLSessionWebSocketTask!
    
    func start(onMessage: @escaping (URLSessionWebSocketTask.Message) async throws -> Void) async throws {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .current)
        let url = URL(string: "ws://localhost:3000")
        
        self.webSocket = session.webSocketTask(with: url!)
        self.webSocket.resume()
        
        while true {
            let message = try await webSocket.receive()
            try await onMessage(message)
        }
    }
    
    func send(text: String) {
        print("Send: \(text)")
        webSocket.send(URLSessionWebSocketTask.Message.string(text)) { error in
            print(error == nil ? "Message sent" : "Error sending message: \(error!)")
        }
    }
    
    // MARK: URLSessionWebSocketDelegate
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("Connected to server")
        send(text: "{\"role\":\"IMPLEMENTATION\"}")
    }
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("Disconnected from server")
    }
}
