@testable import AblyChat
import Testing

struct DefaultRoomLifecycleTests {
    @Test
    func status_startsAsInitialized() async {
        let lifecycle = DefaultRoomLifecycle(logger: TestLogger())
        #expect(await lifecycle.status == .initialized)
    }

    @Test()
    func error_startsAsNil() async {
        let lifecycle = DefaultRoomLifecycle(logger: TestLogger())
        #expect(await lifecycle.error == nil)
    }

    @Test
    func transition() async throws {
        // Given: A DefaultRoomLifecycle
        let lifecycle = DefaultRoomLifecycle(logger: TestLogger())
        let originalStatus = await lifecycle.status
        let newStatus = RoomStatus.attached // arbitrary

        let subscription1 = await lifecycle.onChange(bufferingPolicy: .unbounded)
        let subscription2 = await lifecycle.onChange(bufferingPolicy: .unbounded)

        async let statusChange1 = subscription1.first { $0.current == newStatus }
        async let statusChange2 = subscription2.first { $0.current == newStatus }

        // When: transition(to:) is called
        await lifecycle.transition(to: newStatus)

        // Then: It emits a status change to all subscribers added via onChange(bufferingPolicy:), and updates its `status` property to the new status
        for statusChange in try await [#require(statusChange1), #require(statusChange2)] {
            #expect(statusChange.previous == originalStatus)
            #expect(statusChange.current == newStatus)
        }

        #expect(await lifecycle.status == .attached)
    }
}
