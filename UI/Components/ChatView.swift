//
//  ChatView.swift
//  FinalStorm
//
//  Chat interface for communication
//

import SwiftUI

struct ChatView: View {
    @State private var messages: [ChatMessage] = ChatMessage.sampleMessages
    @State private var inputText = ""
    @State private var selectedChannel: ChatChannel = .local
    
    var body: some View {
        VStack(spacing: 0) {
            // Channel selector
            HStack {
                ForEach(ChatChannel.allCases, id: \.self) { channel in
                    Button(action: { selectedChannel = channel }) {
                        Text(channel.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedChannel == channel ? Color.blue : Color.gray.opacity(0.3))
                            .cornerRadius(5)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.8))
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(filteredMessages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            // Input
            HStack {
                TextField("Type a message...", text: $inputText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                }
            }
            .padding()
            .background(Color.black.opacity(0.8))
        }
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
    }
    
    private var filteredMessages: [ChatMessage] {
        messages.filter { message in
            selectedChannel == .all || message.channel == selectedChannel
        }
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty else { return }
        
        let message = ChatMessage(
            sender: "You",
            content: inputText,
            channel: selectedChannel,
            timestamp: Date()
        )
        
        messages.append(message)
        inputText = ""
    }
}

struct ChatMessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text("[\(message.timestamp, formatter: timeFormatter)]")
                .font(.caption2)
                .foregroundColor(.gray)
            
            Text("[\(message.channel.rawValue)]")
                .font(.caption2)
                .foregroundColor(message.channel.color)
            
            Text(message.sender + ":")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(message.senderColor)
            
            Text(message.content)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Supporting Types
struct ChatMessage: Identifiable {
    let id = UUID()
    let sender: String
    let content: String
    let channel: ChatChannel
    let timestamp: Date
    
    var senderColor: Color {
        sender == "You" ? .green : .white
    }
    
    static let sampleMessages = [
        ChatMessage(
            sender: "System",
            content: "Welcome to Finalverse!",
            channel: .system,
            timestamp: Date()
        ),
        ChatMessage(
            sender: "Lumi",
            content: "Hello, Songweaver! The light guides your path.",
            channel: .local,
            timestamp: Date()
        ),
        ChatMessage(
            sender: "Player123",
            content: "Anyone want to explore the Whisperwood?",
            channel: .local,
            timestamp: Date()
        )
    ]
}

enum ChatChannel: String, CaseIterable {
    case all = "All"
    case local = "Local"
    case party = "Party"
    case guild = "Guild"
    case system = "System"
    
    var color: Color {
        switch self {
        case .all: return .white
        case .local: return .yellow
        case .party: return .green
        case .guild: return .blue
        case .system: return .orange
        }
    }
}
