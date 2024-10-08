import Foundation

public enum HeadersValue: Sendable, Codable, Hashable {
    case string(String)
    case number(Int)
    case bool(Bool)
    case null
}

// The corresponding type in TypeScript is
// Record<string, number | string | boolean | null | undefined>
// There may be a better way to represent it in Swift; this will do for now. Have omitted `undefined` because I don’t know how that would occur.
public typealias Headers = [String: HeadersValue]
