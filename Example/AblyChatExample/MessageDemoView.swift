import Ably
import AblyChat
import SwiftUI

// TODO: This entire file can be removed and replaced with the actual example app we're going with. Leaving it here as a reference to something that is currently working.

let clientId = "" // Set any string as a ClientID here e.g. "John"
let apiKey = "" // Set your Ably API Key here

struct MessageCell: View {
    var contentMessage: String
    var isCurrentUser: Bool

    var body: some View {
        Text(contentMessage)
            .padding(12)
            .foregroundColor(isCurrentUser ? Color.white : Color.black)
            .background(isCurrentUser ? Color.blue : Color.gray)
            .cornerRadius(12)
    }
}

struct MessageView: View {
    var currentMessage: Message

    var body: some View {
        HStack(alignment: .bottom) {
            if let messageClientId = currentMessage.clientID {
                if messageClientId == clientId {
                    Spacer()
                } else {}
                MessageCell(
                    contentMessage: currentMessage.text,
                    isCurrentUser: messageClientId == clientId
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

struct MessageDemoView: View {
    @State private var messages: [Message] = [] // Store the chat messages
    @State private var newMessage: String = "" // Store the message user is typing
    @State private var room: Room? // Keep track of the chat room

    var clientOptions: ARTClientOptions {
        let options = ARTClientOptions()
        options.clientId = clientId
        options.key = apiKey
        return options
    }

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages, id: \.self) { message in
                            MessageView(currentMessage: message)
                                .id(message)
                        }
                    }
                    .onChange(of: messages.count) {
                        withAnimation {
                            proxy.scrollTo(messages.last, anchor: .bottom)
                        }
                    }
                    .onAppear {
                        withAnimation {
                            proxy.scrollTo(messages.last, anchor: .bottom)
                        }
                    }
                }

                // send new message
                HStack {
                    TextField("Send a message", text: $newMessage)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane")
                    }
                }
                .padding()
            }
            .task {
                await startChat()
            }
        }
    }

    func startChat() async {
        let realtime = ARTRealtime(options: clientOptions)

        let chatClient = DefaultChatClient(
            realtime: realtime,
            clientOptions: nil
        )

        do {
            // Get the chat room
            room = try await chatClient.rooms.get(roomID: "umairsDemoRoom1", options: .init())

            // attach to room
            try await room?.attach()

            // subscribe to messages
            let subscription = try await room?.messages.subscribe(bufferingPolicy: .unbounded)

            // use subscription to get previous messages
            let prevMessages = try await subscription?.getPreviousMessages(params: .init(orderBy: .oldestFirst))

            // init local messages array with previous messages
            messages = .init(prevMessages?.items ?? [])

            // append new messages to local messages array as they are emitted
            if let subscription {
                for await message in subscription {
                    messages.append(message)
                }
            }
        } catch {
            print("Error starting chat: \(error)")
        }
    }

    func sendMessage() {
        guard !newMessage.isEmpty else {
            return
        }
        Task {
            do {
                _ = try await room?.messages.send(params: .init(text: newMessage))

                // Clear the text field after sending
                newMessage = ""
            } catch {
                print("Error sending message: \(error)")
            }
        }
    }
}

#Preview {
    MessageDemoView()
}
