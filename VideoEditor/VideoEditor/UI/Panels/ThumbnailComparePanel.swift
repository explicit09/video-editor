import SwiftUI
import AppKit

struct ThumbnailComparePanel: View {
    @Environment(AppState.self) private var appState
    @State private var layoutMode: CompareLayout = .four
    @State private var thumbnails: [ThumbnailFile] = []
    @State private var selectedPath: String?
    @State private var fullViewThumb: ThumbnailFile?

    enum CompareLayout: String, CaseIterable {
        case one = "1-up"
        case two = "2-up"
        case four = "4-up"

        var columns: Int {
            switch self {
            case .one: return 1
            case .two: return 2
            case .four: return 2
            }
        }

        var maxItems: Int {
            switch self {
            case .one: return 1
            case .two: return 2
            case .four: return 4
            }
        }

        var icon: String {
            switch self {
            case .one: return "square"
            case .two: return "rectangle.split.2x1"
            case .four: return "rectangle.split.2x2"
            }
        }
    }

    struct ThumbnailFile: Identifiable {
        let id = UUID()
        let url: URL
        let provider: String  // "openai" or "gemini"
        let index: Int
        let title: String     // extracted from filename
        var image: NSImage?
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            UtilityPanelHeader(
                eyebrow: "THUMBNAILS",
                title: "Compare",
                subtitle: thumbnails.isEmpty ? "Generate thumbnails first" : "\(thumbnails.count) thumbnail(s)"
            ) {
                HStack(spacing: 4) {
                    // Layout mode picker
                    ForEach(CompareLayout.allCases, id: \.self) { mode in
                        Button {
                            layoutMode = mode
                        } label: {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(layoutMode == mode ? UtilityTheme.accentText : UtilityTheme.textMuted)
                                .frame(width: 24, height: 24)
                                .background(layoutMode == mode ? UtilityTheme.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().frame(height: 16)

                    // Refresh button
                    Button {
                        loadThumbnails()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(UtilityTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            if let thumb = fullViewThumb {
                fullView(thumb)
            } else if thumbnails.isEmpty {
                emptyState
            } else {
                ScrollView {
                    thumbnailGrid
                        .padding(8)
                }
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
        .onAppear { loadThumbnails() }
    }

    // Empty state
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
            Text("No thumbnails yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CinematicTheme.onSurfaceVariant)
            Text("Use generate_thumbnail to create options")
                .font(.system(size: 11))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // Grid layout
    private var thumbnailGrid: some View {
        let items = Array(thumbnails.prefix(layoutMode.maxItems))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: layoutMode.columns)

        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { thumb in
                thumbnailCard(thumb)
            }
        }
    }

    // Individual thumbnail card
    private func thumbnailCard(_ thumb: ThumbnailFile) -> some View {
        VStack(spacing: 4) {
            // Image
            Group {
                if let image = thumb.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(1536.0 / 1024.0, contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(CinematicTheme.surfaceContainerLowest)
                        .aspectRatio(1536.0 / 1024.0, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selectedPath == thumb.url.path ? CinematicTheme.primary : Color.clear, lineWidth: 2)
            )
            .onTapGesture(count: 2) {
                fullViewThumb = thumb
            }
            .onTapGesture(count: 1) {
                selectedPath = thumb.url.path
            }

            // Label
            HStack {
                Text(thumb.provider.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(thumb.provider == "openai" ? Color.green : Color.blue)
                Text("#\(thumb.index)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                Spacer()
                if selectedPath == thumb.url.path {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(CinematicTheme.primary)
                }
            }
        }
    }

    // Full view of a single thumbnail
    private func fullView(_ thumb: ThumbnailFile) -> some View {
        VStack(spacing: 0) {
            // Back bar
            HStack {
                Button {
                    fullViewThumb = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back to grid")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CinematicTheme.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(thumb.provider.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(thumb.provider == "openai" ? Color.green : Color.blue)
                Text("#\(thumb.index)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)

                Divider().frame(height: 16)

                // Copy to clipboard
                Button {
                    if let img = thumb.image {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Show in Finder
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([thumb.url])
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")

                // Export (Save As)
                Button {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = thumb.url.lastPathComponent
                    panel.allowedContentTypes = [.png]
                    if panel.runModal() == .OK, let dest = panel.url {
                        try? FileManager.default.copyItem(at: thumb.url, to: dest)
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Export")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(CinematicTheme.surfaceContainerHigh)

            // Full image
            if let image = thumb.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }
        }
    }

    // Load thumbnails from disk
    private func loadThumbnails() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let thumbDir = docsDir.appendingPathComponent("Thumbnails")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: thumbDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            thumbnails = []
            return
        }

        // Sort by modification date (newest first)
        let sorted = files
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return dateA > dateB
            }

        thumbnails = sorted.map { url in
            let filename = url.deletingPathExtension().lastPathComponent
            // Parse: thumbnail_{title}_{provider}_{index}
            let parts = filename.components(separatedBy: "_")
            let provider: String
            let index: Int
            let title: String

            if parts.count >= 3,
               let lastNum = Int(parts.last ?? ""),
               let providerPart = parts.dropLast().last {
                provider = String(providerPart)
                index = lastNum
                title = parts.dropFirst().dropLast(2).joined(separator: " ")
            } else {
                provider = "unknown"
                index = 0
                title = filename
            }

            let image = NSImage(contentsOf: url)
            return ThumbnailFile(url: url, provider: provider, index: index, title: title, image: image)
        }
    }
}
