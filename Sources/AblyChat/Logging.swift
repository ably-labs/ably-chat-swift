public typealias LogContext = [String: any Sendable]

public protocol LogHandler: AnyObject, Sendable {
    func log(message: String, level: LogLevel, context: LogContext?)
}

public enum LogLevel: Sendable {
    case trace
    case debug
    case info
    case warn
    case error
    case silent
}