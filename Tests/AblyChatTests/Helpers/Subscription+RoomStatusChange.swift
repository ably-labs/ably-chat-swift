import Ably
import AblyChat

/// Extensions for filtering a subscription by a given case, and then providing access to the values associated with these cases.
///
/// This provides better ergonomics than writing e.g. `failedStatusChange = await subscription.first { $0.isSuspended }`, because it means that you don’t have to write another `if case` (or equivalent) to get access to the associated value of `failedStatusChange.current`.
extension Subscription where Element == RoomStatusChange {
    struct StatusChangeWithError {
        /// A status change whose `current` has an associated error; ``error`` provides access to this error.
        var statusChange: RoomStatusChange
        /// The error associated with `statusChange.current`.
        var error: ARTErrorInfo
    }

    func suspendedElements() async -> AsyncCompactMapSequence<Subscription<RoomStatusChange>, Subscription<RoomStatusChange>.StatusChangeWithError> {
        compactMap { statusChange in
            if case let .suspended(error) = statusChange.current {
                StatusChangeWithError(statusChange: statusChange, error: error)
            } else {
                nil
            }
        }
    }

    func failedElements() async -> AsyncCompactMapSequence<Subscription<RoomStatusChange>, Subscription<RoomStatusChange>.StatusChangeWithError> {
        compactMap { statusChange in
            if case let .failed(error) = statusChange.current {
                StatusChangeWithError(statusChange: statusChange, error: error)
            } else {
                nil
            }
        }
    }
}
