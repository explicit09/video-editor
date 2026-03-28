import SwiftUI
import UniformTypeIdentifiers

/// Empty state — Stitch Screen 2: "today?" onboarding with AI prompt bar.
struct EmptyStateView: View {
    @Environment(AppState.self) private var appState
    @Binding var commandBarText: String
    var onSend: () -> Void
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero text
            VStack(spacing: 12) {
                Text("today?")
                    .font(.cinDisplayLarge)
                    .foregroundStyle(CinematicTheme.onSurface)

                Text("Start a new sequence, import your footage, or let the AI orchestrate your first rough cut.")
                    .font(.cinBody)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Spacer().frame(height: 40)

            // AI Command Bar (large version)
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(CinematicTheme.primary)
                    .font(.system(size: 16))

                TextField("Ask AI to start a project...", text: $commandBarText)
                    .textFieldStyle(.plain)
                    .font(.cinTitle)
                    .foregroundStyle(CinematicTheme.onSurface)
                    .onSubmit { onSend() }

                Button(action: onSend) {
                    Text("Generate")
                        .font(.cinTitleSmall)
                        .fontWeight(.semibold)
                        .foregroundStyle(CinematicTheme.onPrimaryContainer)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(CinematicTheme.primaryContainer)
                        .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.md))
                }
                .buttonStyle(.plain)
                .disabled(commandBarText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(CinematicTheme.surfaceContainerHighest)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.full))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.full)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: 600)

            Spacer().frame(height: 20)

            // Suggestion pills
            HStack(spacing: 10) {
                suggestionPill("\"Create a 30-second travel vlog from my clips\"")
                suggestionPill("\"Make a cinematic trailer from this interview\"")
            }
            HStack(spacing: 10) {
                suggestionPill("\"Sync these clips to a lo-fi beat\"")
                suggestionPill("\"Remove all silence and filler words\"")
            }
            .padding(.top, 6)

            Spacer().frame(height: 40)

            // Quick action cards
            HStack(spacing: 16) {
                actionCard(icon: "film", label: "Import Video", color: CinematicTheme.tertiary) {
                    isImporting = true
                }
                actionCard(icon: "sparkles", label: "AI Edit", color: CinematicTheme.primary) {
                    commandBarText = "Create a rough cut from my footage"
                }
                actionCard(icon: "waveform", label: "Import Audio", color: Color(hex: 0x53E16F)) {
                    isImporting = true
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CinematicTheme.surface)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie, .audio, .mp3, .wav],
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImport(result) }
        }
    }

    private func suggestionPill(_ text: String) -> some View {
        Button(action: {
            commandBarText = String(text.dropFirst().dropLast())
            onSend()
        }) {
            Text(text)
                .font(.cinLabelRegular)
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(CinematicTheme.surfaceContainerLowest)
                .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.full))
        }
        .buttonStyle(.plain)
    }

    private func actionCard(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(color.opacity(0.7))
                Text(label)
                    .font(.cinLabelRegular)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            }
            .frame(width: 100, height: 80)
            .background(CinematicTheme.surfaceContainerHigh)
            .clipShape(RoundedRectangle(cornerRadius: CinematicRadius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: CinematicRadius.xl)
                    .strokeBorder(CinematicTheme.outlineVariant.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func handleImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }
                _ = try? await appState.importMedia(from: url)
            }
        case .failure:
            break
        }
    }
}
