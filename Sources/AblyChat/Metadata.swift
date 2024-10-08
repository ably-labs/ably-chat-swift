// TODO: (https://github.com/ably-labs/ably-chat-swift/issues/13): try to improve this type
// I attempted to address this issue by making a struct conforming to Codable which would at least give us some safety in knowing items can be encoded and decoded. However, the requirement for `Messages` to be Hashable made this difficult. Gone for the same approach as Headers for now, we can investigate whether we need to be open to more types than this later.

public enum MetadataValue: Sendable, Codable, Hashable {
    case string(String)
    case number(Int)
    case bool(Bool)
    case null
}

public typealias Metadata = [String: MetadataValue?]
