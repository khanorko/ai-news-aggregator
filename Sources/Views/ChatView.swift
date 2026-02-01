import SwiftUI

struct ChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss
    
    private let llmService = LLMService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI News Assistant")
                        .font(.custom("Georgia", size: 18))
                        .fontWeight(.semibold)
                    Text("Ask questions about AI news and trends")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Welcome message
                        if messages.isEmpty {
                            WelcomeCard()
                                .padding(.top, 20)
                        }
                        
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input
            HStack(spacing: 12) {
                TextField("Ask about AI news...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.borderless)
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private func sendMessage() {
        let userInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userInput.isEmpty else { return }
        
        // Add user message
        var userMessage = ChatMessage(
            role: .user,
            content: userInput,
            timestamp: Date(),
            relatedArticleId: nil
        )
        messages.append(userMessage)
        
        // Save to database
        Task {
            try? await DatabaseManager.shared.saveChatMessage(&userMessage)
        }
        
        inputText = ""
        isLoading = true
        
        // Get AI response
        Task {
            if let response = await llmService.chat(messages: messages) {
                await MainActor.run {
                    var assistantMessage = ChatMessage(
                        role: .assistant,
                        content: response,
                        timestamp: Date(),
                        relatedArticleId: nil
                    )
                    messages.append(assistantMessage)
                    isLoading = false
                    
                    // Save response
                    Task {
                        try? await DatabaseManager.shared.saveChatMessage(&assistantMessage)
                    }
                }
            } else {
                await MainActor.run {
                    isLoading = false
                    var errorMessage = ChatMessage(
                        role: .assistant,
                        content: "Sorry, I couldn't process that request. Please check your API key in Settings.",
                        timestamp: Date(),
                        relatedArticleId: nil
                    )
                    messages.append(errorMessage)
                }
            }
        }
    }
}

// MARK: - Welcome Card

struct WelcomeCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.purple)
            
            Text("Welcome to AI News Assistant")
                .font(.custom("Georgia", size: 20))
                .fontWeight(.semibold)
            
            Text("I can help you with:")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                SuggestionRow(icon: "newspaper", text: "Summarize recent AI news")
                SuggestionRow(icon: "magnifyingglass", text: "Find articles on specific topics")
                SuggestionRow(icon: "chart.line.uptrend.xyaxis", text: "Track AI benchmark trends")
                SuggestionRow(icon: "lightbulb", text: "Explain complex AI concepts")
                SuggestionRow(icon: "bubble.left.and.bubble.right", text: "Discuss AI developments")
            }
        }
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct SuggestionRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.system(size: 14))
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // AI Avatar
                Circle()
                    .fill(LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(18)
                
                Text(formatTime(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            if isUser {
                Spacer(minLength: 40)
            } else {
                Spacer()
            }
            
            if isUser {
                // User Avatar
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    )
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                )
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(dotCount == index ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(18)
            
            Spacer()
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

// MARK: - Quick Actions

struct QuickActionButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .foregroundColor(.accentColor)
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ChatView()
        .frame(width: 450, height: 600)
}
