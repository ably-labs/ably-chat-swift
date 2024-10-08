import Foundation

internal protocol Timeserial: Sendable {
    var seriesId: String { get }
    var timestamp: Int { get }
    var counter: Int { get }
    var index: Int? { get }

    func before(_ timeserial: Timeserial) -> Bool
    func after(_ timeserial: Timeserial) -> Bool
    func equal(_ timeserial: Timeserial) -> Bool
}

internal struct DefaultTimeserial: Timeserial {
    internal let seriesId: String
    internal let timestamp: Int
    internal let counter: Int
    internal let index: Int?

    private init(seriesId: String, timestamp: Int, counter: Int, index: Int?) {
        self.seriesId = seriesId
        self.timestamp = timestamp
        self.counter = counter
        self.index = index
    }

    // Static method to parse a timeserial string
    internal static func calculateTimeserial(from timeserial: String) throws -> DefaultTimeserial {
        let components = timeserial.split(separator: "@")
        guard components.count == 2, let rest = components.last else {
            throw TimeserialError.invalidFormat
        }

        let seriesId = String(components[0])
        let parts = rest.split(separator: "-")
        guard parts.count == 2 else {
            throw TimeserialError.invalidFormat
        }

        let timestamp = Int(parts[0]) ?? 0
        let counterAndIndex = parts[1].split(separator: ":")
        let counter = Int(counterAndIndex[0]) ?? 0
        let index = counterAndIndex.count > 1 ? Int(counterAndIndex[1]) : nil

        return DefaultTimeserial(seriesId: seriesId, timestamp: timestamp, counter: counter, index: index)
    }

    // Compare timeserials
    private func timeserialCompare(_ other: Timeserial) -> Int {
        // Compare timestamps
        let timestampDiff = timestamp - other.timestamp
        if timestampDiff != 0 {
            return timestampDiff
        }

        // Compare counters
        let counterDiff = counter - other.counter
        if counterDiff != 0 {
            return counterDiff
        }

        // Compare seriesId lexicographically
        if seriesId != other.seriesId {
            return seriesId < other.seriesId ? -1 : 1
        }

        // Compare index if present
        if let idx1 = index, let idx2 = other.index {
            return idx1 - idx2
        }

        return 0
    }

    // Check if this timeserial is before the given timeserial
    internal func before(_ timeserial: Timeserial) -> Bool {
        timeserialCompare(timeserial) < 0
    }

    // Check if this timeserial is after the given timeserial
    internal func after(_ timeserial: Timeserial) -> Bool {
        timeserialCompare(timeserial) > 0
    }

    // Check if this timeserial is equal to the given timeserial
    internal func equal(_ timeserial: Timeserial) -> Bool {
        timeserialCompare(timeserial) == 0
    }

    // TODO: Revisit as part of https://github.com/ably-labs/ably-chat-swift/issues/32 (should we only throw ARTErrors?)
    internal enum TimeserialError: Error {
        case invalidFormat
    }
}
