import SwiftUI
import EditorCore
import AIServices

struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            // Show search results view when available, chat otherwise
            if let query = appState.aiChat.lastSearchQuery,
               let results = appState.aiChat.lastSearchResults, !results.isEmpty {
                SearchResultsView(query: query, results: results)
            } else {
                messageList
            }

            inputBar
        }
        .background(CinematicTheme.surfaceContainerLow)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(CinematicTheme.primary)
                Text("AI INSIGHTS")
                    .font(.cinLabel)
                    .tracking(1.5)
                    .foregroundStyle(CinematicTheme.onSurface)
            }
            Spacer()
            if appState.aiChat.isProcessing {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(CinematicTheme.primary)
            }
            Button(action: { appState.aiChat.clearHistory() }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(appState.aiChat.messages.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CinematicTheme.surfaceContainer)
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

                    if let status = appState.aiChat.processingStatus {
                        processingIndicator(status)
                            .id("processing-status")
                    } else if appState.aiChat.isProcessing {
                        processingIndicator("Thinking...")
                            .id("processing-status")
                    }
                }
                .padding(12)
            }
            .onChange(of: appState.aiChat.messages.count) {
                if let last = appState.aiChat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func processingIndicator(_ status: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(CinematicTheme.primary)
            Text(status)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CinematicTheme.surfaceContainerLowest)
        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(CinematicTheme.primary.opacity(0.3))

            Text("Ask AI to edit your video")
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))

            VStack(spacing: 6) {
                suggestionPill("\"Remove all the silent parts\"")
                suggestionPill("\"Find where I mention pricing\"")
                suggestionPill("\"Add the video to the timeline\"")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func suggestionPill(_ text: String) -> some View {
        Text(text)
            .font(.cinLabelRegular)
            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(CinematicTheme.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.full))
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(CinematicTheme.primary.opacity(0.5))

            TextField("Ask AI...", text: $inputText)
                .textFieldStyle(.plain)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? CinematicTheme.onSurfaceVariant.opacity(0.3)
                            : CinematicTheme.primaryContainer
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || appState.aiChat.isProcessing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CinematicTheme.surfaceContainerLowest)
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
        VStack(alignment: alignment == .trailing ? .trailing : .leading, spacing: 4) {
            Text(message.content)
                .font(.cinBody)
                .foregroundStyle(CinematicTheme.onSurface)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.xl))

            // Tool results
            ForEach(message.toolResults.indices, id: \.self) { i in
                let result = message.toolResults[i]
                HStack(spacing: 4) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.success ? Color(hex: 0x53E16F) : CinematicTheme.error)
                        .font(.system(size: 10))
                    Text(result.toolName)
                        .font(.cinLabelRegular)
                        .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
                }
                .padding(.leading, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user: CinematicTheme.primaryContainer.opacity(0.15)
        case .assistant: CinematicTheme.surfaceContainerHighest
        case .system: CinematicTheme.errorContainer.opacity(0.2)
        }
    }
}
