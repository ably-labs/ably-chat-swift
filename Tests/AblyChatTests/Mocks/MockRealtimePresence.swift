import Ably
import AblyChat

final class MockRealtimePresence: NSObject, @unchecked Sendable, RealtimePresenceProtocol {
    let syncComplete: Bool
    private var members: [ARTPresenceMessage]
    private var currentMember: ARTPresenceMessage?

    init(syncComplete: Bool = true, _ members: [ARTPresenceMessage]) {
        self.syncComplete = syncComplete
        self.members = members
        self.currentMember = members.count == 1 ? members[0] : nil
    }

    func get(_ callback: @escaping ARTPresenceMessagesCallback) {
        callback(members, nil)
    }

    func get(_ query: ARTRealtimePresenceQuery, callback: @escaping ARTPresenceMessagesCallback) {
        callback(members.filter { $0.clientId ==  query.clientId }, nil)
    }

    func enter(_: Any?) {
        fatalError("Not implemented")
    }

    func enter(_: Any?, callback _: ARTCallback? = nil) {
        fatalError("Not implemented")
    }

    func update(_ data: Any?) {
        currentMember?.data = data
    }

    func update(_ data: Any?, callback: ARTCallback? = nil) {
        currentMember?.data = data
        callback?(nil)
    }

    func leave(_: Any?) {
        members.removeAll { $0.clientId == currentMember?.clientId }
    }

    func leave(_: Any?, callback: ARTCallback? = nil) {
        members.removeAll { $0.clientId == currentMember?.clientId }
        callback?(nil)
    }

    func enterClient(_ clientId: String, data: Any?) {
        currentMember = ARTPresenceMessage(clientId: clientId, data: data)
        members.append(currentMember!)
    }

    func enterClient(_ clientId: String, data: Any?, callback: ARTCallback? = nil) {
        currentMember = ARTPresenceMessage(clientId: clientId, data: data)
        members.append(currentMember!)
        callback?(nil)
    }

    func updateClient(_ clientId: String, data: Any?) {
        members.first { $0.clientId == clientId }?.data = data
    }

    func updateClient(_ clientId: String, data: Any?, callback: ARTCallback? = nil) {
        members.first { $0.clientId == clientId }?.data = data
        callback?(nil)
    }

    func leaveClient(_ clientId: String, data _: Any?) {
        members.removeAll { $0.clientId == clientId }
    }

    func leaveClient(_ clientId: String, data _: Any?, callback _: ARTCallback? = nil) {
        members.removeAll { $0.clientId == clientId }
    }

    func subscribe(_: @escaping ARTPresenceMessageCallback) -> ARTEventListener? {
        ARTEventListener()
    }

    func subscribe(attachCallback _: ARTCallback?, callback _: @escaping ARTPresenceMessageCallback) -> ARTEventListener? {
        ARTEventListener()
    }

    func subscribe(_: ARTPresenceAction, callback _: @escaping ARTPresenceMessageCallback) -> ARTEventListener? {
        ARTEventListener()
    }

    func subscribe(_: ARTPresenceAction, onAttach _: ARTCallback?, callback _: @escaping ARTPresenceMessageCallback) -> ARTEventListener? {
        ARTEventListener()
    }

    func unsubscribe() {
        fatalError("Not implemented")
    }

    func unsubscribe(_: ARTEventListener) {
        fatalError("Not implemented")
    }

    func unsubscribe(_: ARTPresenceAction, listener _: ARTEventListener) {
        fatalError("Not implemented")
    }

    func history(_: @escaping ARTPaginatedPresenceCallback) {
        fatalError("Not implemented")
    }

    func history(_: ARTRealtimeHistoryQuery?, callback _: @escaping ARTPaginatedPresenceCallback) throws {
        fatalError("Not implemented")
    }
}
