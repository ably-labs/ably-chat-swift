import Foundation

public typealias MessageHeaders = Headers
public typealias MessageMetadata = Metadata

// (CHA-M2) A Message corresponds to a single message in a chat room. This is analogous to a single user-specified message on an Ably channel (NOTE: not a ProtocolMessage).
// Must conform to Hashable to use some SwiftUI niceties e.g. 'ForEach'.
public struct Message: Sendable, Codable, Hashable {
    public var timeserial: String
    public var clientID: String?
    public var roomID: String
    public var text: String
    public var createdAt: Date?
    public var metadata: MessageMetadata
    public var headers: MessageHeaders

    public init(timeserial: String, clientID: String?, roomID: String, text: String, createdAt: Date?, metadata: MessageMetadata, headers: MessageHeaders) {
        self.timeserial = timeserial
        self.clientID = clientID
        self.roomID = roomID
        self.text = text
        self.createdAt = createdAt
        self.metadata = metadata
        self.headers = headers
    }

    internal enum CodingKeys: String, CodingKey {
        case timeserial
        case clientID = "clientId"
        case roomID = "roomId"
        case text
        case createdAt
        case metadata
        case headers
    }

    // (CHA-M2a) A Message is considered before another Message in the global order if the timeserial of the corresponding realtime channel message comes first.
    public func isBefore(_ otherMessage: Message) throws -> Bool {
        let otherMessageTimeserial = try DefaultTimeserial.calculateTimeserial(from: otherMessage.timeserial)
        return try DefaultTimeserial.calculateTimeserial(from: timeserial).before(otherMessageTimeserial)
    }

    // CHA-M2b) A Message is considered after another Message in the global order if the timeserial of the corresponding realtime channel message comes second.
    public func isAfter(_ otherMessage: Message) throws -> Bool {
        let otherMessageTimeserial = try DefaultTimeserial.calculateTimeserial(from: otherMessage.timeserial)
        return try DefaultTimeserial.calculateTimeserial(from: timeserial).after(otherMessageTimeserial)
    }

    // (CHA-M2c) A Message is considered to be equal to another Message if they have the same timeserial.
    public func isEqual(_ otherMessage: Message) throws -> Bool {
        let otherMessageTimeserial = try DefaultTimeserial.calculateTimeserial(from: otherMessage.timeserial)
        return try DefaultTimeserial.calculateTimeserial(from: timeserial).equal(otherMessageTimeserial)
    }
}
