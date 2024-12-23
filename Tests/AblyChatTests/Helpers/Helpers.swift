import Ably
@testable import AblyChat

/**
 Tests whether a given optional `Error` is an `ARTErrorInfo` in the chat error domain with a given code and cause. Can optionally pass a message and it will check that it matches.
 */
func isChatError(_ maybeError: (any Error)?, withCodeAndStatusCode codeAndStatusCode: AblyChat.ErrorCodeAndStatusCode, cause: ARTErrorInfo? = nil, message: String? = nil) -> Bool {
    guard let ablyError = maybeError as? ARTErrorInfo else {
        return false
    }

    return ablyError.domain == AblyChat.errorDomain as String
        && ablyError.code == codeAndStatusCode.code.rawValue
        && ablyError.statusCode == codeAndStatusCode.statusCode
        && ablyError.cause == cause
        && {
            guard let message else {
                return true
            }

            return ablyError.message == message
        }()
}

extension ARTPresenceMessage {
    convenience init(clientId: String, data: Any? = [:], timestamp: Date = Date()) {
        self.init()
        self.clientId = clientId
        self.data = data
        self.timestamp = timestamp
    }
}

extension Array where Element == PresenceEventType {
    static let all = [
        PresenceEventType.present,
        PresenceEventType.enter,
        PresenceEventType.leave,
        PresenceEventType.update
    ]
}
