@testable import AblyChat

struct TestLogger: InternalLogger {
    // By default, we don’t log in tests to keep the test logs easy to read. You can set this property to `true` to temporarily turn logging on if you want to debug a test.
    static let loggingEnabled = false

    private let underlyingLogger = DefaultInternalLogger(logHandler: nil, logLevel: .trace)

    func log(message: String, level: LogLevel, codeLocation: CodeLocation) {
        guard Self.loggingEnabled else {
            return
        }

        underlyingLogger.log(message: message, level: level, codeLocation: codeLocation)
    }
}
