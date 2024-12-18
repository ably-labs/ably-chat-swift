internal class SubscriptionStorage<Element: Sendable> {
   private var subscriptions: [Subscription<Element>] = []

    func create(bufferingPolicy: BufferingPolicy) -> Subscription<Element> {
        let subscription = Subscription<Element>(bufferingPolicy: bufferingPolicy)
        subscriptions.append(subscription)
        return subscription
    }

    internal func emit(_ element: Element) {
        for subscription in subscriptions {
            subscription.emit(element)
        }
    }
}
