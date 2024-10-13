import Ably
import AblyChat

typealias JSON = [String: Any]

extension JSON {
    var name: String? { self["name"] as? String }
    var type: String? { self["type"] as? String }
    var args: JSON? { self["args"] as? JSON }
    var result: JSON { self["result"] as! JSON }
    var isSerializable: Bool { self["serializable"] as? Bool ?? false }
    var isOptional: Bool { self["optional"] as? Bool ?? false }
    var constructor: JSON? { self["konstructor"] as? JSON }
    var fields: JSON? { self["fields"] as? JSON }
    var syncMethods: JSON? { self["syncMethods"] as? JSON }
    var asyncMethods: JSON? { self["asyncMethods"] as? JSON }
    var listeners: JSON? { self["listeners"] as? JSON }
    var listener: JSON? { self["listener"] as? JSON }
    var callback: JSON? { args?.listener }
    
    var refId: String { self["refId"] as! String }
    var callbackId: String { self["callbackId"] as! String }
    var requestId: String { self["id"] as! String }
}

func jsonRpcResult(_ id: String, _ result: String) -> String {
    "{\"jsonrpc\":\"2.0\",\"id\":\"\(id)\",\"result\":\(result)}"
}

func jsonRpcCallback(_ callbackId: String, _ message: String) -> String {
    "{\"jsonrpc\":\"2.0\",\"id\":\"\(UUID().uuidString)\",\"method\":\"callback\",\"params\":{\"callbackId\":\"\(callbackId)\",\"args\":[\(message)]}}"
}

func jsonFromWebSocketMessage(_ message: URLSessionWebSocketTask.Message) -> JSON? {
    var json: [String: Any]?
    
    do {
        switch message {
        case .data(let data):
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        case .string(let string):
            json = try JSONSerialization.jsonObject(with: string.data(using: .utf8)!) as? JSON
        @unknown default:
            print("Unknown Websocket data.")
            return nil
        }
    } catch {
        print("Error parsing JSON: \(error)")
        return nil
    }
    
    guard let json else {
        print("Data provided is not a valid JSON dictionary.")
        return nil
    }
    
    print("Received: \(json)")
    
    if json["method"] == nil || json["jsonrpc"] == nil {
        print("No valid fields in the provided JSON were found.")
        return nil
    }
    return json
}

func generateId() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }

protocol JsonSerialisable {
    func json() -> Any
}

extension CommandLine {
    static func hasParam(_ name: String) -> Bool {
        arguments.contains(where: { $0 == name })
    }
}

extension StringProtocol {
    func firstLowercased() -> String { prefix(1).lowercased() + dropFirst() }
    func firstUppercased() -> String { prefix(1).uppercased() + dropFirst() }
}

extension JSON {
    func sortedByKey() -> Array<Element> {
        sorted {
            $0.key > $1.key
        }
    }
}

extension ClientOptions: JsonSerialisable {
    func json() -> Any {
        ["logLevel": logLevel ?? .info]
    }
}

extension RoomOptions: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension ErrorInfo: JsonSerialisable {
    func json() -> Any {
        ["error": description()]
    }
}

extension Set<String>: JsonSerialisable {
    func json() -> Any {
        Array(self)
    }
}

extension OccupancyEvent: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension Message: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension ConnectionStatusChange: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension RoomStatusChange: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension TypingEvent: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension Reaction: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension PresenceEvent: JsonSerialisable {
    func json() -> Any {
        fatalError("Not implemented")
    }
}

extension JSON {
    static func from(_ value: Any) -> Self {
        if value is JsonSerialisable {
            return (value as! JsonSerialisable).json() as! JSON
        }
        fatalError("Not implemented")
    }
}

extension Message {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension QueryOptions {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension SendMessageParams {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension String {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension RealtimePresenceParams {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension SendReactionParams {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension RoomOptions {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension ClientOptions {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension ARTClientOptions {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}

extension PresenceDataWrapper {
    static func from(_ value: Any?) -> PresenceData {
        fatalError("Not implemented")
    }
}

extension PresenceEventType {
    static func from(_ value: Any?) -> Self {
        fatalError("Not implemented")
    }
}
