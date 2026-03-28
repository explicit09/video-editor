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
    var clipCount: Int { timeline.tracks.reduce(into: 0) { $0 += $1.clips.count } }
    var canExportCurrentTimeline: Bool { clipCount > 0 && timeline.duration > 0 }

    // Clipboard
    private(set) var clipboardClips: [(clip: Clip, trackType: TrackType)] = []

    /// Project bundle directory.
    let projectBundleURL: URL
    private var mcpServer: MCPServer?

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

        // Start MCP server for external tool access (Claude Code, etc.)
        let server = MCPServer(appState: self)
        self.mcpServer = server
        server.start()
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

    func duplicateSelection(source: ActionSource = .user) {
        let selectedClips = timeline.tracks
            .enumerated()
            .flatMap { trackIndex, track in
                track.clips.compactMap { clip -> (trackIndex: Int, trackID: UUID, clip: Clip)? in
                    guard timelineViewState.selectedClipIDs.contains(clip.id) else { return nil }
                    return (trackIndex, track.id, clip)
                }
            }
            .sorted { lhs, rhs in
                if lhs.trackIndex != rhs.trackIndex {
                    return lhs.trackIndex < rhs.trackIndex
                }
                if lhs.clip.timelineRange.start != rhs.clip.timelineRange.start {
                    return lhs.clip.timelineRange.start < rhs.clip.timelineRange.start
                }
                return lhs.clip.timelineRange.end < rhs.clip.timelineRange.end
            }

        guard !selectedClips.isEmpty else { return }

        if selectedClips.count == 1, let onlyClip = selectedClips.first {
            try? perform(.duplicateClip(clipID: onlyClip.clip.id), source: source)
            return
        }

        var duplicatedIDs = Set<UUID>()
        var duplicatedClips: [UUID] = []
        var linkGroupMap: [UUID: UUID] = [:]
        let intents: [EditorIntent] = selectedClips.compactMap { entry in
            guard duplicatedIDs.insert(entry.clip.id).inserted else { return nil }

            let duplicateLinkGroupID = entry.clip.linkGroupID.map { originalID in
                linkGroupMap[originalID] ?? {
                    let newID = UUID()
                    linkGroupMap[originalID] = newID
                    return newID
                }()
            }

            let duplicate = Clip(
                assetID: entry.clip.assetID,
                timelineRange: TimeRange(
                    start: entry.clip.timelineRange.end,
                    duration: entry.clip.timelineRange.duration
                ),
                sourceRange: entry.clip.sourceRange,
                transform: entry.clip.transform,
                opacity: entry.clip.opacity,
                volume: entry.clip.volume,
                effects: entry.clip.effects,
                keyframes: entry.clip.keyframes,
                metadata: ClipMetadata(
                    label: (entry.clip.metadata.label ?? "Clip") + " (copy)",
                    tags: entry.clip.metadata.tags,
                    transcriptSegment: entry.clip.metadata.transcriptSegment,
                    sceneType: entry.clip.metadata.sceneType
                ),
                speed: entry.clip.speed,
                transitionIn: entry.clip.transitionIn,
                linkGroupID: duplicateLinkGroupID
            )
            duplicatedClips.append(duplicate.id)
            return .insertClip(clip: duplicate, trackID: entry.trackID)
        }

        guard !intents.isEmpty else { return }
        try? perform(intents.count == 1 ? intents[0] : .batch(intents), source: source)

        if let firstTrackID = intents.compactMap({ intentTrackID(for: $0) }).first {
            timelineViewState.selectedClipIDs = Set(duplicatedClips)
            timelineViewState.selectedTrackID = firstTrackID
        }
    }

    func toggleClipSelection(_ clipID: UUID, extend: Bool) {
        guard let selectedTrackID = trackID(for: clipID) else { return }
        let clipIDs = linkedSelectionIDs(for: clipID)

        if extend {
            let isEntireGroupSelected = clipIDs.allSatisfy { timelineViewState.selectedClipIDs.contains($0) }
            if isEntireGroupSelected {
                clipIDs.forEach { timelineViewState.selectedClipIDs.remove($0) }
            } else {
                clipIDs.forEach { timelineViewState.selectedClipIDs.insert($0) }
            }

            let selectedTrackIDs = Set(timelineViewState.selectedClipIDs.compactMap { self.trackID(for: $0) })
            timelineViewState.selectedTrackID = selectedTrackIDs.count == 1 ? selectedTrackIDs.first : selectedTrackID
        } else {
            timelineViewState.selectedClipIDs = Set(clipIDs)
            let selectedTrackIDs = Set(clipIDs.compactMap { self.trackID(for: $0) })
            timelineViewState.selectedTrackID = selectedTrackIDs.count == 1 ? selectedTrackIDs.first : selectedTrackID
        }
    }

    func moveSelection(primaryClipID: UUID, newStart: TimeInterval, targetTrackID: UUID) {
        guard timelineViewState.selectedClipIDs.contains(primaryClipID),
              timelineViewState.selectedClipIDs.count > 1,
              let primaryClip = clip(for: primaryClipID),
              let primaryTrack = track(for: primaryClipID) else {
            try? perform(.moveClip(clipID: primaryClipID, newStart: newStart, trackID: targetTrackID))
            return
        }

        let selectedClips = timeline.tracks
            .flatMap(\.clips)
            .filter { timelineViewState.selectedClipIDs.contains($0.id) }
        guard !selectedClips.isEmpty else { return }

        let delta = newStart - primaryClip.timelineRange.start
        let orderedClips = selectedClips.sorted { lhs, rhs in
            if delta >= 0 {
                if lhs.timelineRange.start != rhs.timelineRange.start {
                    return lhs.timelineRange.start > rhs.timelineRange.start
                }
                return lhs.timelineRange.end > rhs.timelineRange.end
            }
            if lhs.timelineRange.start != rhs.timelineRange.start {
                return lhs.timelineRange.start < rhs.timelineRange.start
            }
            return lhs.timelineRange.end < rhs.timelineRange.end
        }

        let intents: [EditorIntent] = orderedClips.compactMap { clip in
            guard let originalTrackID = trackID(for: clip.id) else { return nil }
            let clipTrackType = track(for: clip.id)?.type
            let destinationTrackID: UUID

            if clip.id == primaryClipID {
                destinationTrackID = targetTrackID
            } else if clip.linkGroupID != nil,
                      clip.linkGroupID == primaryClip.linkGroupID,
                      let clipTrackType,
                      clipTrackType != primaryTrack.type {
                destinationTrackID = pairedTrackID(
                    for: targetTrackID,
                    sourceType: primaryTrack.type,
                    targetType: clipTrackType
                )
            } else {
                destinationTrackID = originalTrackID
            }

            return .moveClip(
                clipID: clip.id,
                newStart: max(0, clip.timelineRange.start + delta),
                trackID: destinationTrackID
            )
        }

        guard !intents.isEmpty else { return }
        try? perform(intents.count == 1 ? intents[0] : .batch(intents))
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
            timelineViewState.selectClip(videoClip.id, in: videoTrackID)

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
            timelineViewState.selectClip(clip.id, in: trackID)

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
            timelineViewState.selectClip(clip.id, in: trackID)
        }
    }

    func insertAssetSegment(
        _ asset: MediaAsset,
        sourceRange requestedSourceRange: TimeRange,
        source: ActionSource = .user,
        preferredTrackID: UUID? = nil,
        startTime: TimeInterval? = nil,
        label: String? = nil
    ) async {
        let sourceRange = clampedSourceRange(for: asset, proposed: requestedSourceRange)
        let duration = max(sourceRange.duration, 1)
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
            let linkID = UUID()
            let videoClip = Clip(
                assetID: asset.id,
                timelineRange: TimeRange(start: clipStart, duration: duration),
                sourceRange: sourceRange,
                metadata: ClipMetadata(label: label ?? asset.name),
                linkGroupID: hasAudio ? linkID : nil
            )
            try? perform(.insertClip(clip: videoClip, trackID: videoTrackID), source: source)
            timelineViewState.selectClip(videoClip.id, in: videoTrackID)

            if let audioTrackID {
                let audioClip = Clip(
                    assetID: asset.id,
                    timelineRange: TimeRange(start: clipStart, duration: duration),
                    sourceRange: sourceRange,
                    metadata: ClipMetadata(label: label ?? asset.name),
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
                sourceRange: sourceRange,
                metadata: ClipMetadata(label: label ?? asset.name)
            )
            try? perform(.insertClip(clip: clip, trackID: trackID), source: source)
            timelineViewState.selectClip(clip.id, in: trackID)

        case .image:
            let trackID = resolveTrackID(for: .video, preferredTrackID: requestedTrack?.type == .video ? requestedTrack?.id : nil)
            let clipStart = startTime ?? trackEnd(for: trackID)
            let clip = Clip(
                assetID: asset.id,
                timelineRange: TimeRange(start: clipStart, duration: duration),
                sourceRange: sourceRange,
                metadata: ClipMetadata(label: label ?? asset.name)
            )
            try? perform(.insertClip(clip: clip, trackID: trackID), source: source)
            timelineViewState.selectClip(clip.id, in: trackID)
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
           preferredTrack.type == type,
           !preferredTrack.isLocked {
            return preferredTrackID
        }

        if let existing = timeline.tracks.last(where: { $0.type == type && !$0.isLocked }) {
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
            if candidateTrack.type == targetType, !candidateTrack.isLocked {
                return candidateTrack.id
            }
        }

        let sourceOrdinal = timeline.tracks
            .filter { $0.type == sourceType }
            .firstIndex(where: { $0.id == sourceTrackID }) ?? 0
        let targetTracks = timeline.tracks.filter { $0.type == targetType && !$0.isLocked }
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

    private func clampedSourceRange(for asset: MediaAsset, proposed: TimeRange) -> TimeRange {
        guard asset.duration > 0 else {
            return TimeRange(start: max(proposed.start, 0), duration: max(proposed.duration, 1))
        }

        let maxStart = max(asset.duration - 0.1, 0)
        let start = min(max(proposed.start, 0), maxStart)
        let remaining = max(asset.duration - start, 0.1)
        let duration = min(max(proposed.duration, 0.1), remaining)
        return TimeRange(start: start, duration: duration)
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
        let expandedIntent = expandLinkedIntent(intent)
        var command = try intentResolver.resolve(expandedIntent)
        try commandHistory.execute(&command, context: context, source: source)

        // Ripple: close gaps after delete/trim if enabled
        if timelineViewState.rippleEnabled {
            rippleCloseGaps(for: intent)
        }

        normalizeSelection()
        rebuildComposition()
        scheduleSave()
    }

    /// Close all gaps on all tracks by shifting clips left. Public for compound tools.
    func rippleCloseGaps() {
        for trackIndex in context.timelineState.timeline.tracks.indices {
            var clips = context.timelineState.timeline.tracks[trackIndex].clips
            clips.sort { $0.timelineRange.start < $1.timelineRange.start }
            var cursor: TimeInterval = 0
            for i in clips.indices {
                if clips[i].timelineRange.start > cursor {
                    let duration = clips[i].timelineRange.duration
                    clips[i].timelineRange = TimeRange(start: cursor, duration: duration)
                }
                cursor = clips[i].timelineRange.end
            }
            context.timelineState.timeline.tracks[trackIndex].clips = clips
        }
        rebuildComposition()
        scheduleSave()
    }

    /// After a delete or trim, shift subsequent clips left to close gaps (auto, when ripple mode on).
    private func rippleCloseGaps(for intent: EditorIntent) {
        switch intent {
        case .deleteClips, .trimClip:
            for trackIndex in context.timelineState.timeline.tracks.indices {
                var clips = context.timelineState.timeline.tracks[trackIndex].clips
                clips.sort { $0.timelineRange.start < $1.timelineRange.start }

                var cursor: TimeInterval = 0
                for i in clips.indices {
                    if clips[i].timelineRange.start > cursor {
                        // Gap detected — shift this clip left
                        let duration = clips[i].timelineRange.duration
                        clips[i].timelineRange = TimeRange(start: cursor, duration: duration)
                    }
                    cursor = clips[i].timelineRange.end
                }
                context.timelineState.timeline.tracks[trackIndex].clips = clips
            }
        default:
            break
        }
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
        normalizeSelection()
        rebuildComposition()
        scheduleSave()
    }

    func redo() throws {
        try commandHistory.redo(context: context)
        normalizeSelection()
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

            timelineViewState.clearSelection()
            normalizeSelection()
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

    private func clip(for clipID: UUID) -> Clip? {
        timeline.tracks.flatMap(\.clips).first(where: { $0.id == clipID })
    }

    private func intentTrackID(for intent: EditorIntent) -> UUID? {
        if case let .insertClip(_, trackID) = intent {
            return trackID
        }
        return nil
    }

    private func track(for clipID: UUID) -> Track? {
        timeline.tracks.first(where: { track in
            track.clips.contains(where: { $0.id == clipID })
        })
    }

    private func linkedSelectionIDs(for clipID: UUID) -> [UUID] {
        guard timelineViewState.linkedSelectionEnabled,
              let clip = clip(for: clipID),
              let linkGroupID = clip.linkGroupID else {
            return [clipID]
        }

        let linkedIDs = timeline.tracks
            .flatMap(\.clips)
            .filter { $0.linkGroupID == linkGroupID }
            .map(\.id)

        return linkedIDs.isEmpty ? [clipID] : linkedIDs
    }

    func trackID(for clipID: UUID) -> UUID? {
        timeline.tracks.first(where: { track in
            track.clips.contains(where: { $0.id == clipID })
        })?.id
    }

    func focusTimeline(at time: TimeInterval, clipID: UUID? = nil, trackID: UUID? = nil) {
        let maxTime = max(timeline.duration, playbackEngine.duration)
        let clampedTime = min(max(time, 0), maxTime)
        playbackEngine.seek(to: clampedTime)
        timelineViewState.playheadPosition = clampedTime

        if let clipID, let trackID {
            timelineViewState.selectClip(clipID, in: trackID)
        } else if let trackID {
            timelineViewState.selectTrack(trackID)
        }
    }

    func timelineLocation(forAssetID assetID: UUID, sourceTime: TimeInterval) -> (clipID: UUID, trackID: UUID, timelineTime: TimeInterval)? {
        let playhead = timelineViewState.playheadPosition
        let selectedIDs = timelineViewState.selectedClipIDs

        struct Candidate {
            let clipID: UUID
            let trackID: UUID
            let timelineTime: TimeInterval
            let priority: Int
            let distance: TimeInterval
            let trackIndex: Int
        }

        var bestCandidate: Candidate?

        for (trackIndex, track) in timeline.tracks.enumerated() {
            for clip in track.clips where clip.assetID == assetID && clip.sourceRange.contains(sourceTime) {
                let mappedTime = clip.timelineRange.start + (sourceTime - clip.sourceRange.start)
                let candidate = Candidate(
                    clipID: clip.id,
                    trackID: track.id,
                    timelineTime: min(max(mappedTime, clip.timelineRange.start), clip.timelineRange.end),
                    priority: selectedIDs.contains(clip.id) ? 0 : (clip.timelineRange.contains(playhead) ? 1 : 2),
                    distance: abs(mappedTime - playhead),
                    trackIndex: trackIndex
                )

                if let currentBest = bestCandidate {
                    if candidate.priority < currentBest.priority
                        || (candidate.priority == currentBest.priority && candidate.distance < currentBest.distance)
                        || (candidate.priority == currentBest.priority && candidate.distance == currentBest.distance && candidate.trackIndex < currentBest.trackIndex) {
                        bestCandidate = candidate
                    }
                } else {
                    bestCandidate = candidate
                }
            }
        }

        guard let bestCandidate else { return nil }
        return (bestCandidate.clipID, bestCandidate.trackID, bestCandidate.timelineTime)
    }

    func createSearchSequence(from results: [SearchResult], named query: String, source: ActionSource = .ai) async {
        guard !results.isEmpty else { return }

        let insertionIndex = timelineViewState.selectedTrackID.flatMap { id in
            timeline.tracks.firstIndex(where: { $0.id == id }).map { $0 + 1 }
        }
        let trackName = query.isEmpty ? "Search Sequence" : "\(query) sequence"
        let videoTrackID = createTrack(of: .video, insertionIndex: insertionIndex, name: trackName, source: source)
        var position: TimeInterval = 0

        for result in results {
            guard let asset = assets.first(where: { $0.id == result.assetID }) else { continue }
            let segmentStart = max(0, result.contextStartTime)
            let segmentDuration = max(result.contextEndTime - result.contextStartTime, 1)
            await insertAssetSegment(
                asset,
                sourceRange: TimeRange(start: segmentStart, duration: segmentDuration),
                source: source,
                preferredTrackID: videoTrackID,
                startTime: position,
                label: "\(result.assetName) • \(result.formattedTime)"
            )
            position += segmentDuration
        }

        focusTimeline(at: 0, trackID: videoTrackID)
    }

    private func normalizeSelection() {
        let validTrackIDs = Set(timeline.tracks.map(\.id))
        var clipToTrack: [UUID: UUID] = [:]
        for track in timeline.tracks {
            for clip in track.clips {
                clipToTrack[clip.id] = track.id
            }
        }

        let validClipIDs = Set(timelineViewState.selectedClipIDs.filter { clipToTrack[$0] != nil })
        if validClipIDs != timelineViewState.selectedClipIDs {
            timelineViewState.selectedClipIDs = validClipIDs
        }

        guard !validClipIDs.isEmpty else {
            if let selectedTrackID = timelineViewState.selectedTrackID, !validTrackIDs.contains(selectedTrackID) {
                timelineViewState.selectedTrackID = nil
            }
            return
        }

        let selectedTrackIDs = Set(validClipIDs.compactMap { clipToTrack[$0] })
        if selectedTrackIDs.count == 1 {
            timelineViewState.selectedTrackID = selectedTrackIDs.first
        } else if let selectedTrackID = timelineViewState.selectedTrackID, !selectedTrackIDs.contains(selectedTrackID) {
            timelineViewState.selectedTrackID = nil
        }
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
