@testable import AblyChat
import Foundation

/// A mock implementation of ``SimpleClock`` which records its arguments but does not actually sleep.
actor MockSimpleClock: SimpleClock {
    private let sleepBehavior: SleepBehavior

    enum SleepBehavior {
        case success
        case fromFunction(@Sendable () async -> Void)
    }

    init(sleepBehavior: SleepBehavior? = nil) {
        self.sleepBehavior = sleepBehavior ?? .success
        _sleepCallArgumentsAsyncSequence = AsyncStream<TimeInterval>.makeStream()
    }

    private(set) var sleepCallArguments: [TimeInterval] = []

    /// Emits an element each time ``sleep(timeInterval:)`` is called.
    var sleepCallArgumentsAsyncSequence: AsyncStream<TimeInterval> {
        _sleepCallArgumentsAsyncSequence.stream
    }

    private let _sleepCallArgumentsAsyncSequence: (stream: AsyncStream<TimeInterval>, continuation: AsyncStream<TimeInterval>.Continuation)

    func sleep(timeInterval: TimeInterval) async throws {
        sleepCallArguments.append(timeInterval)
        _sleepCallArgumentsAsyncSequence.continuation.yield(timeInterval)

        switch sleepBehavior {
        case .success:
            break
        case let .fromFunction(function):
            await function()
        }
    }
}
