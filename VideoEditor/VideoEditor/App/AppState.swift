import SwiftUI
import AVFoundation
import EditorCore
import AIServices

@Observable
@MainActor
final class AppState {
    let context: EditingContext
    let commandHistory: CommandHistory
    let intentResolver: IntentResolver
    let timelineViewState: TimelineViewState
    let playbackEngine: PlaybackEngine
    let exportEngine: ExportEngine
    let media: MediaCoordinator
    let aiChat: AIChatController
    let projectStore: ProjectStore

    // Reactive access
    var timeline: Timeline { context.timelineState.timeline }
    var assets: [MediaAsset] { media.assets }

    // Clipboard
    private(set) var clipboardClips: [(clip: Clip, trackType: TrackType)] = []

    /// Project bundle directory.
    let projectBundleURL: URL

    private var playbackSyncTimer: Timer?
    private var saveDebounceTask: Task<Void, Never>?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleURL = appSupport.appendingPathComponent("VideoEditor/DefaultProject.veditor")
        for subdir in ["media", "proxies", "cache/thumbnails", "cache/waveforms", "cache/render", "analysis"] {
            try? FileManager.default.createDirectory(
                at: bundleURL.appendingPathComponent(subdir),
                withIntermediateDirectories: true
            )
        }

        self.projectBundleURL = bundleURL
        self.projectStore = ProjectStore()
        self.context = EditingContext()
        self.commandHistory = CommandHistory()
        self.intentResolver = IntentResolver()
        self.timelineViewState = TimelineViewState()
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()
        self.media = MediaCoordinator(bundleURL: bundleURL)
        self.aiChat = AIChatController()

        // Load API keys from .env file or environment
        let keys = Self.loadEnvKeys()
        if let claudeKey = keys["ANTHROPIC_API_KEY"] {
            aiChat.configure(provider: ClaudeProvider(apiKey: claudeKey))
        }
        if let dgKey = keys["DEEPGRAM_API_KEY"] {
            media.setTranscriptionProvider(DeepgramProvider(apiKey: dgKey))
        }

        // Rebuild composition when proxy/analysis completes in background
        media.onAnalysisComplete = { [weak self] in
            self?.rebuildComposition()
        }
        // Save when assets change (import, proxy, analysis, transcription)
        media.onAssetsChanged = { [weak self] in
            self?.scheduleSave()
        }

        // Load existing project if timeline.json exists
        loadProject()

        let dbPath = bundleURL.appendingPathComponent("metadata.sqlite").path
        Task {
            do {
                try await context.actionLog.open(at: dbPath)
            } catch {
                print("[AppState] ActionLog failed to open: \(error.localizedDescription). Using in-memory fallback.")
            }
        }

        startPlayheadSync()
    }

    // MARK: - Clipboard

    func copySelectedClips() {
        let selectedIDs = timelineViewState.selectedClipIDs
        guard !selectedIDs.isEmpty else { return }

        clipboardClips = []
        for track in timeline.tracks {
            for clip in track.clips where selectedIDs.contains(clip.id) {
                clipboardClips.append((clip: clip, trackType: track.type))
            }
        }
    }

    func pasteClips() {
        guard !clipboardClips.isEmpty else { return }
        let playhead = timelineViewState.playheadPosition

        // Find the earliest clip start to compute relative offsets
        let earliestStart = clipboardClips.map(\.clip.timelineRange.start).min() ?? 0

        for (original, trackType) in clipboardClips {
            let trackID = resolveTrackID(for: trackType, preferredTrackID: nil)
            let offset = original.timelineRange.start - earliestStart
            let pasteStart = playhead + offset

            let newClip = Clip(
                assetID: original.assetID,
                timelineRange: TimeRange(start: pasteStart, duration: original.timelineRange.duration),
                sourceRange: original.sourceRange,
                transform: original.transform,
                opacity: original.opacity,
                volume: original.volume,
                metadata: ClipMetadata(label: (original.metadata.label ?? "Clip") + " (paste)")
            )
            try? perform(.insertClip(clip: newClip, trackID: trackID))
        }
    }

    // MARK: - Add to timeline (creates linked audio track only when media actually has audio)

    func addAssetToTimeline(
        _ asset: MediaAsset,
        source: ActionSource = .user,
        preferredTrackID: UUID? = nil,
        startTime: TimeInterval? = nil
    ) async {
        let duration = max(asset.duration, 1)
        let requestedTrackID = preferredTrackID ?? timelineViewState.selectedTrackID
        let requestedTrack = requestedTrackID.flatMap { id in
            timeline.tracks.first(where: { $0.id == id })
        }

        switch asset.type {
        case .video:
            let hasAudio = await assetHasAudio(asset)
            let videoTrackID: UUID
            let audioTrackID: UUID?

            if let requestedTrack {
                switch requestedTrack.type {
                case .video:
                    videoTrackID = resolveTrackID(for: .video, preferredTrackID: requestedTrack.id)
                    audioTrackID = hasAudio ? pairedTrackID(for: requestedTrack.id, sourceType: .video, targetType: .audio) : nil
                case .audio:
                    videoTrackID = pairedTrackID(for: requestedTrack.id, sourceType: .audio, targetType: .video)
                    audioTrackID = hasAudio ? requestedTrack.id : nil
                default:
                    videoTrackID = resolveTrackID(for: .video, preferredTrackID: nil)
                    audioTrackID = hasAudio ? pairedTrackID(for: videoTrackID, sourceType: .video, targetType: .audio) : nil
                }
            } else {
                videoTrackID = resolveTrackID(for: .video, preferredTrackID: timelineViewState.selectedTrackID)
                audioTrackID = hasAudio ? pairedTrackID(for: videoTrackID, sourceType: .video, targetType: .audio) : nil
            }

            let clipStart = startTime ?? trackEnd(for: videoTrackID)
            let linkID = UUID() // Shared link group for video+audio pair
            let videoClip = Clip(
                assetID: asset.id,
                timelineRange: TimeRange(start: clipStart, duration: duration),
                sourceRange: TimeRange(start: 0, duration: duration),
                metadata: ClipMetadata(label: asset.name),
                linkGroupID: hasAudio ? linkID : nil
            )
            try? perform(.insertClip(clip: videoClip, trackID: videoTrackID), source: source)

            if let audioTrackID {
                let audioClip = Clip(
                    assetID: asset.id,
                    timelineRange: TimeRange(start: clipStart, duration: duration),
                    sourceRange: TimeRange(start: 0, duration: duration),
                    metadata: ClipMetadata(label: asset.name),
                    linkGroupID: linkID
                )
                try? perform(.insertClip(clip: audioClip, trackID: audioTrackID), source: source)
            }

        case .audio:
            let trackID: UUID
            if let requestedTrack {
                switch requestedTrack.type {
                case .audio:
                    trackID = requestedTrack.id
                case .video:
                    trackID = pairedTrackID(for: requestedTrack.id, sourceType: .video, targetType: .audio)
                default:
                    trackID = resolveTrackID(for: .audio, preferredTrackID: nil)
                }
            } else {
                trackID = resolveTrackID(for: .audio, preferredTrackID: timelineViewState.selectedTrackID)
            }

            let clipStart = startTime ?? trackEnd(for: trackID)
            let clip = Clip(
                assetID: asset.id,
                timelineRange: TimeRange(start: clipStart, duration: duration),
                sourceRange: TimeRange(start: 0, duration: duration),
                metadata: ClipMetadata(label: asset.name)
            )
            try? perform(.insertClip(clip: clip, trackID: trackID), source: source)

        case .image:
            let trackID = resolveTrackID(for: .video, preferredTrackID: requestedTrack?.type == .video ? requestedTrack?.id : nil)
            let clipStart = startTime ?? trackEnd(for: trackID)
            let clip = Clip(
                assetID: asset.id,
                timelineRange: TimeRange(start: clipStart, duration: duration),
                sourceRange: TimeRange(start: 0, duration: duration),
                metadata: ClipMetadata(label: asset.name)
            )
            try? perform(.insertClip(clip: clip, trackID: trackID), source: source)
        }
    }

    func addTrack(of type: TrackType, positionedAfter afterTrackID: UUID? = nil) {
        let insertionIndex = afterTrackID.flatMap { id in
            timeline.tracks.firstIndex(where: { $0.id == id }).map { $0 + 1 }
        }
        _ = createTrack(of: type, insertionIndex: insertionIndex)
    }

    func updateTrack(id: UUID, _ transform: (inout Track) -> Void) {
        var timeline = context.timelineState.timeline
        guard let index = timeline.tracks.firstIndex(where: { $0.id == id }) else { return }
        transform(&timeline.tracks[index])
        context.timelineState.timeline = timeline
        rebuildComposition()
        scheduleSave()
    }

    func updateClip(id: UUID, _ transform: (inout Clip) -> Void) {
        var timeline = context.timelineState.timeline

        for trackIndex in timeline.tracks.indices {
            guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == id }) else { continue }
            transform(&timeline.tracks[trackIndex].clips[clipIndex])
            context.timelineState.timeline = timeline
            rebuildComposition()
            scheduleSave()
            return
        }
    }

    @discardableResult
    private func createTrack(
        of type: TrackType,
        insertionIndex: Int? = nil,
        name: String? = nil,
        source: ActionSource = .user
    ) -> UUID {
        let track = Track(name: name ?? nextTrackName(for: type), type: type)
        var command = AddTrackCommand(track: track, insertionIndex: insertionIndex)
        try? commandHistory.execute(&command, context: context, source: source)
        rebuildComposition()
        scheduleSave()
        return track.id
    }

    private func resolveTrackID(for type: TrackType, preferredTrackID: UUID?) -> UUID {
        if let preferredTrackID,
           let preferredTrack = timeline.tracks.first(where: { $0.id == preferredTrackID }),
           preferredTrack.type == type {
            return preferredTrackID
        }

        if let existing = timeline.tracks.last(where: { $0.type == type }) {
            return existing.id
        }

        return createTrack(of: type)
    }

    private func pairedTrackID(for sourceTrackID: UUID, sourceType: TrackType, targetType: TrackType) -> UUID {
        guard let sourceTrackIndex = timeline.tracks.firstIndex(where: { $0.id == sourceTrackID }) else {
            return resolveTrackID(for: targetType, preferredTrackID: nil)
        }

        let preferredOffsets: [Int]
        switch (sourceType, targetType) {
        case (.video, .audio):
            preferredOffsets = [1, -1]
        case (.audio, .video):
            preferredOffsets = [-1, 1]
        default:
            preferredOffsets = [1, -1]
        }

        for offset in preferredOffsets {
            let candidateIndex = sourceTrackIndex + offset
            guard timeline.tracks.indices.contains(candidateIndex) else { continue }
            let candidateTrack = timeline.tracks[candidateIndex]
            if candidateTrack.type == targetType {
                return candidateTrack.id
            }
        }

        let sourceOrdinal = timeline.tracks
            .filter { $0.type == sourceType }
            .firstIndex(where: { $0.id == sourceTrackID }) ?? 0
        let targetTracks = timeline.tracks.filter { $0.type == targetType }
        if targetTracks.indices.contains(sourceOrdinal) {
            return targetTracks[sourceOrdinal].id
        }

        let insertionIndex = targetType == .audio ? sourceTrackIndex + 1 : sourceTrackIndex
        return createTrack(of: targetType, insertionIndex: insertionIndex)
    }

    private func nextTrackName(for type: TrackType) -> String {
        let count = timeline.tracks.filter { $0.type == type }.count + 1
        let baseName: String = switch type {
        case .video: "Video"
        case .audio: "Audio"
        case .text: "Text"
        case .effect: "Effect"
        }
        return count == 1 ? baseName : "\(baseName) \(count)"
    }

    private func trackEnd(for trackID: UUID) -> TimeInterval {
        timeline.tracks.first(where: { $0.id == trackID })?.clips.map(\.timelineRange.end).max() ?? 0
    }

    private func assetHasAudio(_ asset: MediaAsset) async -> Bool {
        switch asset.type {
        case .audio:
            return true
        case .image:
            return false
        case .video:
            let avAsset = AVURLAsset(url: asset.sourceURL)
            guard let tracks = try? await avAsset.loadTracks(withMediaType: .audio) else {
                return false
            }
            return !tracks.isEmpty
        }
    }

    private func removeAudiolessVideoClips(using assets: [MediaAsset]) async {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        var assetsWithNoAudio = Set<UUID>()

        for asset in assets where asset.type == .video {
            if await !assetHasAudio(asset) {
                assetsWithNoAudio.insert(asset.id)
            }
        }

        guard !assetsWithNoAudio.isEmpty else { return }

        var timeline = context.timelineState.timeline
        var removedAny = false

        for index in timeline.tracks.indices where timeline.tracks[index].type == .audio {
            let originalCount = timeline.tracks[index].clips.count
            timeline.tracks[index].clips.removeAll { clip in
                guard let asset = assetsByID[clip.assetID] else { return false }
                return asset.type == .video && assetsWithNoAudio.contains(asset.id)
            }
            removedAny = removedAny || timeline.tracks[index].clips.count != originalCount
        }

        guard removedAny else { return }
        context.timelineState.timeline = timeline
        scheduleSave()
    }

    // MARK: - Intent pipeline (ONLY write path)

    func perform(_ intent: EditorIntent, source: ActionSource = .user) throws {
        // Expand linked clips: if the intent targets a clip with a linkGroupID,
        // create the same intent for all siblings and execute as a batch.
        let expandedIntent = expandLinkedIntent(intent)
        var command = try intentResolver.resolve(expandedIntent)
        try commandHistory.execute(&command, context: context, source: source)
        rebuildComposition()
        scheduleSave()
    }

    /// If an intent targets a clip with linked siblings, expand to a batch.
    private func expandLinkedIntent(_ intent: EditorIntent) -> EditorIntent {
        let allClips = timeline.tracks.flatMap(\.clips)

        switch intent {
        case .moveClip(let clipID, let newStart, let trackID):
            guard let clip = allClips.first(where: { $0.id == clipID }),
                  let linkGroup = clip.linkGroupID else { return intent }
            let siblings = allClips.filter { $0.linkGroupID == linkGroup && $0.id != clipID }
            guard !siblings.isEmpty else { return intent }
            // Move all linked clips by the same delta
            let delta = newStart - clip.timelineRange.start
            var intents: [EditorIntent] = [intent]
            for sibling in siblings {
                let sibTrack = timeline.tracks.first(where: { $0.clips.contains { $0.id == sibling.id } })
                intents.append(.moveClip(clipID: sibling.id, newStart: sibling.timelineRange.start + delta, trackID: sibTrack?.id ?? trackID))
            }
            return intents.count == 1 ? intent : .batch(intents)

        case .trimClip(let clipID, let newSourceRange):
            guard let clip = allClips.first(where: { $0.id == clipID }),
                  let linkGroup = clip.linkGroupID else { return intent }
            let siblings = allClips.filter { $0.linkGroupID == linkGroup && $0.id != clipID }
            guard !siblings.isEmpty else { return intent }
            var intents: [EditorIntent] = [intent]
            for sibling in siblings {
                intents.append(.trimClip(clipID: sibling.id, newSourceRange: newSourceRange))
            }
            return .batch(intents)

        case .deleteClips(let clipIDs):
            var expanded = Set(clipIDs)
            for id in clipIDs {
                guard let clip = allClips.first(where: { $0.id == id }),
                      let linkGroup = clip.linkGroupID else { continue }
                let siblings = allClips.filter { $0.linkGroupID == linkGroup }
                siblings.forEach { expanded.insert($0.id) }
            }
            return .deleteClips(clipIDs: Array(expanded))

        case .splitClip(let clipID, let at):
            guard let clip = allClips.first(where: { $0.id == clipID }),
                  let linkGroup = clip.linkGroupID else { return intent }
            let siblings = allClips.filter { $0.linkGroupID == linkGroup && $0.id != clipID }
            guard !siblings.isEmpty else { return intent }
            var intents: [EditorIntent] = [intent]
            for sibling in siblings {
                intents.append(.splitClip(clipID: sibling.id, at: at))
            }
            return .batch(intents)

        default:
            return intent
        }
    }

    func undo() throws {
        try commandHistory.undo(context: context)
        rebuildComposition()
        scheduleSave()
    }

    func redo() throws {
        try commandHistory.redo(context: context)
        rebuildComposition()
        scheduleSave()
    }

    // MARK: - Project persistence

    /// Save project after a short debounce (avoids saving on every keystroke/drag).
    private func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            // Save timeline
            try? await projectStore.save(to: projectBundleURL, timeline: timeline)
            // Save asset registry
            let allAssets = await media.mediaManager.allAssets()
            let assetsURL = projectBundleURL.appendingPathComponent("assets.json")
            if let data = try? JSONEncoder().encode(allAssets) {
                try? data.write(to: assetsURL)
            }
        }
    }

    /// Load project from bundle on launch.
    private func loadProject() {
        let timelinePath = projectBundleURL.appendingPathComponent("timeline.json")
        guard FileManager.default.fileExists(atPath: timelinePath.path) else { return }

        Task {
            // Load timeline
            if let loadedTimeline = try? await projectStore.load(from: projectBundleURL) {
                context.timelineState.timeline = loadedTimeline
            }

            // Load assets and merge persisted transcripts
            let assetsURL = projectBundleURL.appendingPathComponent("assets.json")
            if let data = try? Data(contentsOf: assetsURL),
               let loadedAssets = try? JSONDecoder().decode([MediaAsset].self, from: data) {
                for var asset in loadedAssets {
                    // Restore transcript from disk if not in assets.json
                    if asset.analysis?.transcript == nil || asset.analysis!.transcript!.isEmpty {
                        if let diskResult = await media.transcriptionService.loadTranscript(
                            for: asset.id, bundleURL: projectBundleURL, sourceURL: asset.sourceURL
                        ) {
                            var analysis = asset.analysis ?? MediaAnalysis()
                            analysis.transcript = diskResult.words
                            analysis.speakerSegments = diskResult.speakers
                            asset.analysis = analysis
                        }
                    }
                    // Validate source file exists
                    if FileManager.default.fileExists(atPath: asset.sourceURL.path) {
                        await media.mediaManager.add(asset)
                    } else {
                        print("[AppState] Missing media file: \(asset.sourceURL.lastPathComponent)")
                    }
                }
                await media.refreshAssets()
                await removeAudiolessVideoClips(using: loadedAssets)
            }

            rebuildComposition()
        }
    }

    // MARK: - Media import

    func importMedia(from url: URL) async throws -> MediaAsset {
        let mediaDir = projectBundleURL.appendingPathComponent("media")
        return try await media.importMedia(from: url, mediaDir: mediaDir)
    }

    // MARK: - Playback

    func rebuildComposition() {
        playbackEngine.buildComposition(from: timeline, assets: assets)
    }

    func seekFromPlayhead() {
        playbackEngine.seek(to: timelineViewState.playheadPosition)
    }

    // MARK: - API key loading

    /// Load all KEY=VALUE pairs from .env files and environment.
    private static func loadEnvKeys() -> [String: String] {
        var keys: [String: String] = [:]

        // Load from .env files
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let envPaths = [
            appSupport?.appendingPathComponent("VideoEditor/.env"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("VideoEditor/.env"),
        ].compactMap { $0 }
        for envPath in envPaths {
            if let contents = try? String(contentsOf: envPath, encoding: .utf8) {
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    if let eqIndex = trimmed.firstIndex(of: "=") {
                        let key = String(trimmed[trimmed.startIndex..<eqIndex])
                        let value = String(trimmed[trimmed.index(after: eqIndex)...])
                        if !value.isEmpty { keys[key] = value }
                    }
                }
            }
        }

        // Environment variables override .env file
        for key in ["ANTHROPIC_API_KEY", "DEEPGRAM_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
                keys[key] = value
            }
        }

        return keys
    }

    private func startPlayheadSync() {
        playbackSyncTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.playbackEngine.isPlaying {
                    self.timelineViewState.playheadPosition = self.playbackEngine.currentTime
                    self.timelineViewState.isPlaying = true
                } else {
                    self.timelineViewState.isPlaying = false
                }
            }
        }
    }
}
