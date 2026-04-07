import SwiftUI
import AppKit

struct CarouselViewerPanel: View {
    @Environment(AppState.self) private var appState
    @State private var carousels: [CarouselFolder] = []
    @State private var activeCarousel: CarouselFolder?
    @State private var currentSlideIndex: Int = 0

    struct CarouselFolder: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        var slides: [SlideFile]
    }

    struct SlideFile: Identifiable {
        let id = UUID()
        let url: URL
        let slideNumber: Int
        let provider: String
        var image: NSImage?
    }

    var body: some View {
        VStack(spacing: 0) {
            UtilityPanelHeader(
                eyebrow: "CAROUSELS",
                title: activeCarousel?.name ?? "Viewer",
                subtitle: activeCarousel.map { "\($0.slides.count) slides" } ?? "\(carousels.count) carousel(s)"
            ) {
                HStack(spacing: 4) {
                    if activeCarousel != nil {
                        Button {
                            activeCarousel = nil
                            currentSlideIndex = 0
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                Text("All")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(CinematicTheme.primary)
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 16)
                    }

                    Button {
                        loadCarousels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(UtilityTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let carousel = activeCarousel {
                slideViewer(carousel)
            } else if carousels.isEmpty {
                emptyState
            } else {
                carouselList
            }
        }
        .background(CinematicTheme.surfaceContainerLow)
        .onAppear { loadCarousels() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.4))
            Text("No carousels yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CinematicTheme.onSurfaceVariant)
            Text("Use generate_carousel to create slides")
                .font(.system(size: 11))
                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Carousel List

    private var carouselList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(carousels) { carousel in
                    Button {
                        activeCarousel = carousel
                        currentSlideIndex = 0
                    } label: {
                        HStack(spacing: 12) {
                            // Preview of first slide
                            if let first = carousel.slides.first, let img = first.image {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(1, contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CinematicTheme.surfaceContainerLowest)
                                    .frame(width: 56, height: 56)
                                    .overlay {
                                        Image(systemName: "rectangle.stack")
                                            .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.3))
                                    }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(carousel.name.replacingOccurrences(of: "_", with: " "))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CinematicTheme.onSurface)
                                    .lineLimit(1)
                                Text("\(carousel.slides.count) slides")
                                    .font(.system(size: 11))
                                    .foregroundStyle(CinematicTheme.onSurfaceVariant)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.5))
                        }
                        .padding(10)
                        .background(CinematicTheme.surfaceContainerHigh)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Slide Viewer (Instagram-style)

    private func slideViewer(_ carousel: CarouselFolder) -> some View {
        let slides = carousel.slides
        let safeIndex = min(currentSlideIndex, slides.count - 1)

        return VStack(spacing: 0) {
            // Slide image - full area
            ZStack {
                Color.black

                if safeIndex >= 0 && safeIndex < slides.count, let img = slides[safeIndex].image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Left/Right tap zones
                HStack(spacing: 0) {
                    // Previous
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if currentSlideIndex > 0 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentSlideIndex -= 1
                                }
                            }
                        }

                    // Next
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if currentSlideIndex < slides.count - 1 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentSlideIndex += 1
                                }
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom bar: arrows + dots + counter
            HStack(spacing: 16) {
                // Previous button
                Button {
                    if currentSlideIndex > 0 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentSlideIndex -= 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(currentSlideIndex > 0 ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(currentSlideIndex <= 0)

                Spacer()

                // Dot indicators
                HStack(spacing: 6) {
                    ForEach(0..<slides.count, id: \.self) { idx in
                        Circle()
                            .fill(idx == safeIndex ? CinematicTheme.primary : CinematicTheme.onSurfaceVariant.opacity(0.3))
                            .frame(width: idx == safeIndex ? 8 : 6, height: idx == safeIndex ? 8 : 6)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentSlideIndex = idx
                                }
                            }
                    }
                }

                // Counter
                Text("\(safeIndex + 1) / \(slides.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(CinematicTheme.onSurfaceVariant)

                Spacer()

                // Next button
                Button {
                    if currentSlideIndex < slides.count - 1 {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentSlideIndex += 1
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(currentSlideIndex < slides.count - 1 ? CinematicTheme.onSurface : CinematicTheme.onSurfaceVariant.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(currentSlideIndex >= slides.count - 1)

                Divider().frame(height: 20)

                // Copy to clipboard
                Button {
                    if safeIndex < slides.count, let img = slides[safeIndex].image {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([img])
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Copy slide to clipboard")

                // Show in Finder
                Button {
                    if safeIndex < slides.count {
                        NSWorkspace.shared.activateFileViewerSelecting([slides[safeIndex].url])
                    }
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")

                // Export all slides
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.message = "Choose folder to export all slides"
                    panel.prompt = "Export"
                    if panel.runModal() == .OK, let dest = panel.url {
                        for slide in slides {
                            let target = dest.appendingPathComponent(slide.url.lastPathComponent)
                            try? FileManager.default.copyItem(at: slide.url, to: target)
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13))
                        .foregroundStyle(UtilityTheme.textMuted)
                }
                .buttonStyle(.plain)
                .help("Export all slides")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(CinematicTheme.surfaceContainerHigh)
        }
    }

    // MARK: - Load Carousels

    private func loadCarousels() {
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let carouselDir = docsDir.appendingPathComponent("Carousels")

        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: carouselDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            carousels = []
            return
        }

        carousels = folders.compactMap { folderURL -> CarouselFolder? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return nil
            }

            let slides = files
                .filter { $0.pathExtension.lowercased() == "png" }
                .compactMap { url -> SlideFile? in
                    let filename = url.deletingPathExtension().lastPathComponent
                    // Parse: slide_{n}_{provider}_{i}
                    let parts = filename.components(separatedBy: "_")
                    guard parts.count >= 3,
                          parts.first == "slide",
                          let slideNum = Int(parts[1]) else {
                        return nil
                    }
                    let provider = parts.count >= 3 ? parts[2] : "unknown"
                    let image = NSImage(contentsOf: url)
                    return SlideFile(url: url, slideNumber: slideNum, provider: provider, image: image)
                }
                .sorted { $0.slideNumber < $1.slideNumber }

            guard !slides.isEmpty else { return nil }
            return CarouselFolder(name: folderURL.lastPathComponent, url: folderURL, slides: slides)
        }
        .sorted { $0.name < $1.name }
    }
}
