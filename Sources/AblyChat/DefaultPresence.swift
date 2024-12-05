import Ably

@MainActor
internal final class DefaultPresence: Presence, EmitsDiscontinuities {
    private let featureChannel: FeatureChannel
    private let roomID: String
    private let clientID: String
    private let logger: InternalLogger

    internal init(featureChannel: FeatureChannel, roomID: String, clientID: String, logger: InternalLogger) {
        self.roomID = roomID
        self.featureChannel = featureChannel
        self.clientID = clientID
        self.logger = logger
    }

    internal nonisolated var channel: any RealtimeChannelProtocol {
        featureChannel.channel
    }

    // (CHA-PR6) It must be possible to retrieve all the @Members of the presence set. The behaviour depends on the current room status, as presence operations in a Realtime Client cause implicit attaches.
    internal func get() async throws -> [PresenceMember] {
        logger.log(message: "Getting presence", level: .debug)

        // CHA-PR6b to CHA-PR6f
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence get operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.get { [processPresenceGet] members, error in
                do {
                    let presenceMembers = try processPresenceGet(members, error)
                    continuation.resume(returning: presenceMembers)
                } catch {
                    continuation.resume(throwing: error)
                    // processPresenceGet will log any errors
                }
            }
        }
    }

    internal func get(params: PresenceQuery) async throws -> [PresenceMember] {
        logger.log(message: "Getting presence with params: \(params)", level: .debug)

        // CHA-PR6b to CHA-PR6f
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence get operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.get(params.asARTRealtimePresenceQuery()) { [processPresenceGet] members, error in
                do {
                    let presenceMembers = try processPresenceGet(members, error)
                    continuation.resume(returning: presenceMembers)
                } catch {
                    continuation.resume(throwing: error)
                    // processPresenceGet will log any errors
                }
            }
        }
    }

    // (CHA-PR5) It must be possible to query if a given clientId is in the presence set.
    internal func isUserPresent(clientID: String) async throws -> Bool {
        logger.log(message: "Checking if user is present with clientID: \(clientID)", level: .debug)

        // CHA-PR6b to CHA-PR6f
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence get operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.get(ARTRealtimePresenceQuery(clientId: clientID, connectionId: nil)) { [logger] members, error in
                guard let members else {
                    let error = error ?? ARTErrorInfo.createUnknownError()
                    logger.log(message: error.message, level: .error)
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: !members.isEmpty)
            }
        }
    }

    // (CHA-PR3a) Users may choose to enter presence, optionally providing custom data to enter with. The overall presence data must retain the format specified in CHA-PR2.
    internal func enter(data: PresenceData? = nil) async throws {
        logger.log(message: "Entering presence", level: .debug)

        // CHA-PR3c to CHA-PR3g
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence enter operation: \(error)", level: .error)
            throw error
        }
        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.enterClient(clientID, data: data?.asJSONObject()) { [logger] error in
                if let error {
                    logger.log(message: "Error entering presence: \(error)", level: .error)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // (CHA-PR10a) Users may choose to update their presence data, optionally providing custom data to update with. The overall presence data must retain the format specified in CHA-PR2.
    internal func update(data: PresenceData? = nil) async throws {
        logger.log(message: "Updating presence", level: .debug)

        // CHA-PR10c to CHA-PR10g
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence update operation: \(error)", level: .error)
            throw error
        }

        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.update(data?.asJSONObject()) { [logger] error in
                if let error {
                    logger.log(message: "Error updating presence: \(error)", level: .error)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // (CHA-PR4a) Users may choose to leave presence, which results in them being removed from the Realtime presence set.
    internal func leave(data: PresenceData? = nil) async throws {
        logger.log(message: "Leaving presence", level: .debug)

        // CHA-PR6b to CHA-PR6f
        do {
            try await featureChannel.waitToBeAbleToPerformPresenceOperations(requestedByFeature: RoomFeature.presence)
        } catch {
            logger.log(message: "Error waiting to be able to perform presence leave operation: \(error)", level: .error)
            throw error
        }
        return try await withCheckedThrowingContinuation { continuation in
            channel.presence.leave(data?.asJSONObject()) { [logger] error in
                if let error {
                    logger.log(message: "Error leaving presence: \(error)", level: .error)
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // (CHA-PR7a) Users may provide a listener to subscribe to all presence events in a room.
    // (CHA-PR7b) Users may provide a listener and a list of selected presence events, to subscribe to just those events in a room.
    internal func subscribe(event: PresenceEventType, bufferingPolicy: BufferingPolicy) async -> Subscription<PresenceEvent> {
        logger.log(message: "Subscribing to presence events", level: .debug)
        let subscription = Subscription<PresenceEvent>(bufferingPolicy: bufferingPolicy)
        channel.presence.subscribe(event.toARTPresenceAction()) { [processPresenceSubscribe, logger] message in
            logger.log(message: "Received presence message: \(message)", level: .debug)
            Task {
                // processPresenceSubscribe is logging so we don't need to log here
                let presenceEvent = try processPresenceSubscribe(message, event)
                subscription.emit(presenceEvent)
            }
        }
        return subscription
    }

    internal func subscribe(events: [PresenceEventType], bufferingPolicy: BufferingPolicy) async -> Subscription<PresenceEvent> {
        logger.log(message: "Subscribing to presence events", level: .debug)
        let subscription = Subscription<PresenceEvent>(bufferingPolicy: bufferingPolicy)
        for event in events {
            channel.presence.subscribe(event.toARTPresenceAction()) { [processPresenceSubscribe, logger] message in
                logger.log(message: "Received presence message: \(message)", level: .debug)
                Task {
                    let presenceEvent = try processPresenceSubscribe(message, event)
                    subscription.emit(presenceEvent)
                }
            }
        }
        return subscription
    }

    // (CHA-PR8) Users may subscribe to discontinuity events to know when there’s been a break in presence. Their listener will be called when a discontinuity event is triggered from the room lifecycle. For presence, there shouldn’t need to be user action as the underlying core SDK will heal the presence set.
    internal func onDiscontinuity(bufferingPolicy: BufferingPolicy) async -> Subscription<DiscontinuityEvent> {
        await featureChannel.onDiscontinuity(bufferingPolicy: bufferingPolicy)
    }

    private func decodePresenceData(from data: Any?) -> PresenceData? {
        guard let userData = data as? [String: Any] else {
            return nil
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: userData, options: [])
            let presenceData = try JSONDecoder().decode(PresenceData.self, from: jsonData)
            return presenceData
        } catch {
            print("Failed to decode PresenceData: \(error)")
            logger.log(message: "Failed to decode PresenceData: \(error)", level: .error)
            return nil
        }
    }

    private func processPresenceGet(members: [ARTPresenceMessage]?, error: ARTErrorInfo?) throws -> [PresenceMember] {
        guard let members else {
            let error = error ?? ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without data or text")
            logger.log(message: error.message, level: .error)
            throw error
        }
        let presenceMembers = try members.map { member in
            guard let data = member.data as? [String: Any] else {
                let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without data")
                logger.log(message: error.message, level: .error)
                throw error
            }

            guard let clientID = member.clientId else {
                let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without clientId")
                logger.log(message: error.message, level: .error)
                throw error
            }

            guard let timestamp = member.timestamp else {
                let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without timestamp")
                logger.log(message: error.message, level: .error)
                throw error
            }

            let userCustomData = decodePresenceData(from: data)

            // Seems like we want to just forward on `extras` from the cocoa SDK but that is an `ARTJsonCompatible` type which is not `Sendable`... currently just converting this to a `Sendable` type (`String`) until we know what to do with this.
            let extras = member.extras?.toJSONString()

            let presenceMember = PresenceMember(
                clientID: clientID,
                data: userCustomData ?? .init(),
                action: PresenceMember.Action(from: member.action),
                extras: extras,
                updatedAt: timestamp
            )

            logger.log(message: "Returning presence member: \(presenceMember)", level: .debug)
            return presenceMember
        }
        return presenceMembers
    }

    private func processPresenceSubscribe(_ message: ARTPresenceMessage, for event: PresenceEventType) throws -> PresenceEvent {
        guard let clientID = message.clientId else {
            let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without clientId")
            logger.log(message: error.message, level: .error)
            throw error
        }

        guard let timestamp = message.timestamp else {
            let error = ARTErrorInfo.create(withCode: 50000, status: 500, message: "Received incoming message without timestamp")
            logger.log(message: error.message, level: .error)
            throw error
        }

        let userCustomDataDecoded = decodePresenceData(from: message.data)

        let presenceEvent = PresenceEvent(
            action: event,
            clientID: clientID,
            timestamp: timestamp,
            data: userCustomDataDecoded ?? .init()
        )

        logger.log(message: "Returning presence event: \(presenceEvent)", level: .debug)
        return presenceEvent
    }
}
