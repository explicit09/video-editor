import SwiftUI
import EditorCore
import AIServices

struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AI Assistant")
                .font(.headline)
            Spacer()
            if appState.aiChat.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
            }
            Button(action: { appState.aiChat.clearHistory() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(appState.aiChat.messages.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if appState.aiChat.messages.isEmpty && !appState.aiChat.isProcessing {
                        emptyState
                    }
                    ForEach(appState.aiChat.messages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                    }

                    // Show processing status for long-running operations
                    if let status = appState.aiChat.processingStatus {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .id("processing-status")
                    } else if appState.aiChat.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .id("processing-status")
                    }
                }
                .padding(8)
            }
            .onChange(of: appState.aiChat.messages.count) {
                if let last = appState.aiChat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Ask AI to edit your video")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Try: \"Add a new video track\" or \"Split the selected clip at the playhead\"")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask AI...", text: $inputText)
                .textFieldStyle(.plain)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || appState.aiChat.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await appState.aiChat.send(message: text, appState: appState)
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: AIChatController.ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.content)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(bubbleBackground)
                .cornerRadius(8)

            // Show tool results
            ForEach(message.toolResults.indices, id: \.self) { i in
                let result = message.toolResults[i]
                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? .green : .red)
                        .font(.caption)
                    Text(result.toolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !result.success {
                        Text(result.message)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.leading, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: Color.accentColor.opacity(0.2)
        case .assistant: Color(nsColor: .controlBackgroundColor)
        case .system: Color.red.opacity(0.1)
        }
    }
}
