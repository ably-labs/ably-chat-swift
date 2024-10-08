import Ably

public protocol Messages: AnyObject, Sendable, EmitsDiscontinuities {
    func subscribe(bufferingPolicy: BufferingPolicy) async throws -> MessageSubscription
    func get(options: QueryOptions) async throws -> any PaginatedResult<Message>
    func send(params: SendMessageParams) async throws -> Message
    var channel: RealtimeChannelProtocol { get }
}

public struct SendMessageParams: Sendable {
    public var text: String
    public var metadata: MessageMetadata?
    public var headers: MessageHeaders?

    public init(text: String, metadata: MessageMetadata? = nil, headers: MessageHeaders? = nil) {
        self.text = text
        self.metadata = metadata
        self.headers = headers
    }
}

// TODO: Start and End can be Dates in Swift so should be... will revisit this to properly convert from a timeserial represented as an Int to a Date and back. https://github.com/ably-labs/ably-chat-swift/issues/78
public struct QueryOptions: Sendable {
    public enum ResultOrder: Sendable {
        case oldestFirst
        case newestFirst
    }

    public var start: Date?
    public var end: Int? // represented as timeserial, represented as a number in JS.
    public var limit: Int?
    public var orderBy: ResultOrder?

    // (CHA-M5g) The subscribers subscription point must be additionally specified (internally, by us) in the fromSerial query parameter.
    internal var fromSerial: String?

    public init(start: Date? = nil, end: Int? = nil, limit: Int? = nil, orderBy: QueryOptions.ResultOrder? = nil) {
        self.start = start
        self.end = end
        self.limit = limit
        self.orderBy = orderBy
    }
}

public extension QueryOptions {
    func toDictionary() -> [String: String] {
        var dict: [String: String] = [:]
        if let start {
            dict["start"] = "\(start)"
        }

        if let end {
            dict["end"] = "\(end)"
        }

        if let limit {
            dict["limit"] = "\(limit)"
        }

        if let orderBy {
            switch orderBy {
            case .oldestFirst:
                dict["direction"] = "forwards"
            case .newestFirst:
                dict["direction"] = "backwards"
            }
        }

        if let fromSerial {
            dict["fromSerial"] = fromSerial
        }

        return dict
    }
}

// Currently a copy-and-paste of `Subscription`; see notes on that one. For `MessageSubscription`, my intention is that the `BufferingPolicy` passed to `subscribe(bufferingPolicy:)` will also define what the `MessageSubscription` does with messages that are received _before_ the user starts iterating over the sequence (this buffering will allow us to implement the requirement that there be no discontinuity between the the last message returned by `getPreviousMessages` and the first element you get when you iterate).
public struct MessageSubscription: Sendable, AsyncSequence {
    public typealias Element = Message

    private var subscription: Subscription<Element>

    // can be set by either initialiser
    private let getPreviousMessages: @Sendable (QueryOptions) async throws -> any PaginatedResult<Message>

    // used internally
    internal init(
        bufferingPolicy: BufferingPolicy,
        getPreviousMessages: @escaping @Sendable (QueryOptions) async throws -> any PaginatedResult<Message>
    ) {
        subscription = .init(bufferingPolicy: bufferingPolicy)
        self.getPreviousMessages = getPreviousMessages
    }

    // used for testing
    public init<T: AsyncSequence & Sendable>(mockAsyncSequence: T, mockGetPreviousMessages: @escaping @Sendable (QueryOptions) async throws -> any PaginatedResult<Message>) where T.Element == Element {
        subscription = .init(mockAsyncSequence: mockAsyncSequence)
        getPreviousMessages = mockGetPreviousMessages
    }

    internal func emit(_ element: Element) {
        subscription.emit(element)
    }

    public func getPreviousMessages(params: QueryOptions) async throws -> any PaginatedResult<Message> {
        try await getPreviousMessages(params)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private var subscriptionIterator: Subscription<Element>.AsyncIterator

        fileprivate init(subscriptionIterator: Subscription<Element>.AsyncIterator) {
            self.subscriptionIterator = subscriptionIterator
        }

        public mutating func next() async -> Element? {
            await subscriptionIterator.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        .init(subscriptionIterator: subscription.makeAsyncIterator())
    }
}
