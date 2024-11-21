import Ably

public protocol Room: AnyObject, Sendable {
    var roomID: String { get }
    var messages: any Messages { get }
    // To access this property if presence is not enabled for the room is a programmer error, and will lead to `fatalError` being called.
    var presence: any Presence { get }
    // To access this property if reactions are not enabled for the room is a programmer error, and will lead to `fatalError` being called.
    var reactions: any RoomReactions { get }
    // To access this property if typing is not enabled for the room is a programmer error, and will lead to `fatalError` being called.
    var typing: any Typing { get }
    // To access this property if occupancy is not enabled for the room is a programmer error, and will lead to `fatalError` being called.
    var occupancy: any Occupancy { get }
    // TODO: change to `status`
    var status: RoomStatus { get async }
    func onStatusChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange>
    func attach() async throws
    func detach() async throws
    var options: RoomOptions { get }
}

/// A ``Room`` that exposes additional functionality for use within the SDK.
internal protocol InternalRoom: Room {
    func release() async
}

public struct RoomStatusChange: Sendable, Equatable {
    public var current: RoomStatus
    public var previous: RoomStatus

    public init(current: RoomStatus, previous: RoomStatus) {
        self.current = current
        self.previous = previous
    }
}

internal protocol RoomFactory: Sendable {
    associatedtype Room: AblyChat.InternalRoom

    func createRoom(realtime: RealtimeClient, chatAPI: ChatAPI, roomID: String, options: RoomOptions, logger: InternalLogger) async throws -> Room
}

internal final class DefaultRoomFactory: Sendable, RoomFactory {
    private let lifecycleManagerFactory = DefaultRoomLifecycleManagerFactory()

    internal func createRoom(realtime: RealtimeClient, chatAPI: ChatAPI, roomID: String, options: RoomOptions, logger: InternalLogger) async throws -> DefaultRoom<DefaultRoomLifecycleManagerFactory> {
        try await DefaultRoom(
            realtime: realtime,
            chatAPI: chatAPI,
            roomID: roomID,
            options: options,
            logger: logger,
            lifecycleManagerFactory: lifecycleManagerFactory
        )
    }
}

internal actor DefaultRoom<LifecycleManagerFactory: RoomLifecycleManagerFactory>: InternalRoom where LifecycleManagerFactory.Contributor == DefaultRoomLifecycleContributor {
    internal nonisolated let roomID: String
    internal nonisolated let options: RoomOptions
    private let chatAPI: ChatAPI

    public nonisolated let messages: any Messages
    private let _reactions: (any RoomReactions)?
    private let _presence: (any Presence)?
    private let _occupancy: (any Occupancy)?

    // Exposed for testing.
    private nonisolated let realtime: RealtimeClient

    private let lifecycleManager: any RoomLifecycleManager
    private let channels: [RoomFeature: any RealtimeChannelProtocol]

    private let logger: InternalLogger

    private enum RoomFeatureWithOptions {
        case messages
        case presence(PresenceOptions)
        case typing(TypingOptions)
        case reactions(RoomReactionsOptions)
        case occupancy(OccupancyOptions)

        var toRoomFeature: RoomFeature {
            switch self {
            case .messages:
                .messages
            case .presence:
                .presence
            case .typing:
                .typing
            case .reactions:
                .reactions
            case .occupancy:
                .occupancy
            }
        }

        static func fromRoomOptions(_ roomOptions: RoomOptions) -> [Self] {
            var result: [Self] = [.messages]

            if let presenceOptions = roomOptions.presence {
                result.append(.presence(presenceOptions))
            }

            if let typingOptions = roomOptions.typing {
                result.append(.typing(typingOptions))
            }

            if let reactionsOptions = roomOptions.reactions {
                result.append(.reactions(reactionsOptions))
            }

            if let occupancyOptions = roomOptions.occupancy {
                result.append(.occupancy(occupancyOptions))
            }

            return result
        }
    }

    internal init(realtime: RealtimeClient, chatAPI: ChatAPI, roomID: String, options: RoomOptions, logger: InternalLogger, lifecycleManagerFactory: LifecycleManagerFactory) async throws {
        self.realtime = realtime
        self.roomID = roomID
        self.options = options
        self.logger = logger
        self.chatAPI = chatAPI

        guard let clientId = realtime.clientId else {
            throw ARTErrorInfo.create(withCode: 40000, message: "Ensure your Realtime instance is initialized with a clientId.")
        }

        let featuresWithOptions = RoomFeatureWithOptions.fromRoomOptions(options)

        let featureChannelPartialDependencies = Self.createFeatureChannelPartialDependencies(roomID: roomID, featuresWithOptions: featuresWithOptions, realtime: realtime)
        channels = featureChannelPartialDependencies.mapValues(\.channel)
        let contributors = featureChannelPartialDependencies.values.map(\.contributor)

        lifecycleManager = await lifecycleManagerFactory.createManager(
            contributors: contributors,
            logger: logger
        )

        let featureChannels = Self.createFeatureChannels(partialDependencies: featureChannelPartialDependencies, lifecycleManager: lifecycleManager)

        messages = await DefaultMessages(
            featureChannel: featureChannels[.messages]!,
            chatAPI: chatAPI,
            roomID: roomID,
            clientID: clientId,
            logger: logger
        )

        _reactions = if let featureChannel = featureChannels[.reactions] {
            await DefaultRoomReactions(
                featureChannel: featureChannel,
                clientID: clientId,
                roomID: roomID,
                logger: logger
            )
        } else {
            nil
        }

        _presence = if let featureChannel = featureChannels[.presence] {
            await DefaultPresence(
                featureChannel: featureChannel,
                roomID: roomID,
                clientID: clientId,
                logger: logger
            )
        } else {
            nil
        }

        _occupancy = if let featureChannel = featureChannels[.occupancy] {
            DefaultOccupancy(
                featureChannel: featureChannel,
                chatAPI: chatAPI,
                roomID: roomID,
                logger: logger
            )
        } else {
            nil
        }
    }

    private struct FeatureChannelPartialDependencies {
        internal var channel: RealtimeChannelProtocol
        internal var contributor: DefaultRoomLifecycleContributor
    }

    /// The returned dictionary is guaranteed to have an entry for each element of `features`.
    private static func createChannelsForFeaturesWithOptions(_ featuresWithOptions: [RoomFeatureWithOptions], roomID: String, realtime: RealtimeClient) -> [RoomFeature: RealtimeChannelProtocol] {
        // CHA-RC3a

        // Multiple features can share a realtime channel. We fetch each realtime channel exactly once, merging the channel options for the various features that use this channel.

        let featuresGroupedByChannelName = Dictionary(grouping: featuresWithOptions) { $0.toRoomFeature.channelNameForRoomID(roomID) }

        let pairsOfFeatureAndChannel = featuresGroupedByChannelName.flatMap { channelName, features in
            var channelOptions = RealtimeChannelOptions()

            // channel setup for presence and occupancy
            for feature in features {
                if case /* let */ .presence /* (presenceOptions) */ = feature {
                    // TODO: Restore this code once we understand weird Realtime behaviour and spec points (https://github.com/ably-labs/ably-chat-swift/issues/133)
                    /*
                     if presenceOptions.enter {
                         channelOptions.modes.insert(.presence)
                     }

                     if presenceOptions.subscribe {
                         channelOptions.modes.insert(.presenceSubscribe)
                     }
                     */
                } else if case .occupancy = feature {
                    var params: [String: String] = channelOptions.params ?? [:]
                    params["occupancy"] = "metrics"
                    channelOptions.params = params
                }
            }

            let channel = realtime.getChannel(channelName, opts: channelOptions)
            return features.map { ($0.toRoomFeature, channel) }
        }

        return Dictionary(uniqueKeysWithValues: pairsOfFeatureAndChannel)
    }

    private static func createFeatureChannelPartialDependencies(roomID: String, featuresWithOptions: [RoomFeatureWithOptions], realtime: RealtimeClient) -> [RoomFeature: FeatureChannelPartialDependencies] {
        let channelsByFeature = createChannelsForFeaturesWithOptions(featuresWithOptions, roomID: roomID, realtime: realtime)

        return .init(uniqueKeysWithValues: channelsByFeature.map { feature, channel in
            let contributor = DefaultRoomLifecycleContributor(channel: .init(underlyingChannel: channel), feature: feature)
            return (feature, .init(channel: channel, contributor: contributor))
        })
    }

    private static func createFeatureChannels(partialDependencies: [RoomFeature: FeatureChannelPartialDependencies], lifecycleManager: RoomLifecycleManager) -> [RoomFeature: DefaultFeatureChannel] {
        partialDependencies.mapValues { partialDependencies in
            .init(
                channel: partialDependencies.channel,
                contributor: partialDependencies.contributor,
                roomLifecycleManager: lifecycleManager
            )
        }
    }

    public nonisolated var presence: any Presence {
        guard let _presence else {
            fatalError("Presence is not enabled for this room")
        }
        return _presence
    }

    public nonisolated var reactions: any RoomReactions {
        guard let _reactions else {
            fatalError("Reactions are not enabled for this room")
        }
        return _reactions
    }

    public nonisolated var typing: any Typing {
        fatalError("Not yet implemented")
    }

    public nonisolated var occupancy: any Occupancy {
        guard let _occupancy else {
            fatalError("Occupancy is not enabled for this room")
        }
        return _occupancy
    }

    public func attach() async throws {
        try await lifecycleManager.performAttachOperation()
    }

    public func detach() async throws {
        try await lifecycleManager.performDetachOperation()
    }

    internal func release() async {
        await lifecycleManager.performReleaseOperation()

        // CHA-RL3h
        for channel in channels.values {
            realtime.channels.release(channel.name)
        }
    }

    // MARK: - Room status

    internal func onStatusChange(bufferingPolicy: BufferingPolicy) async -> Subscription<RoomStatusChange> {
        await lifecycleManager.onRoomStatusChange(bufferingPolicy: bufferingPolicy)
    }

    internal var status: RoomStatus {
        get async {
            await lifecycleManager.roomStatus
        }
    }
}
