import Ably

// TODO: Just copied chat-js implementation for now to send up agent info. https://github.com/ably-labs/ably-chat-swift/issues/76

// Update this when you release a new version
// Version information
public let version = "0.1.0"

// Channel options agent string
public let channelOptionsAgentString = "chat-ios/\(version)"

// Default channel options
public var defaultChannelOptions: ARTRealtimeChannelOptions {
    let options = ARTRealtimeChannelOptions()
    options.params = ["agent": channelOptionsAgentString]
    return options
}
