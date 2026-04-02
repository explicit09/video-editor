import Foundation
import EditorCore

enum WaveformLoadState: Equatable {
    case loading
    case ready([Float])
    case noAudio
    case failed
}

enum WaveformLoadStateResolver {
    static func resolve(
        for asset: MediaAsset,
        hasAudioTrack: Bool?,
        extractionInFlight: Bool
    ) -> WaveformLoadState? {
        switch asset.type {
        case .image:
            return nil
        case .audio:
            if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
                return .ready(profile)
            }
            return extractionInFlight ? .loading : .failed
        case .video:
            if let profile = asset.analysis?.loudnessProfile, !profile.isEmpty {
                return .ready(profile)
            }
            if let hasAudioTrack {
                return hasAudioTrack ? (extractionInFlight ? .loading : .failed) : .noAudio
            }
            return .loading
        }
    }
}

struct TimelineTrackDisplayState: Equatable {
    var trackHeights: [UUID: Double]
    var collapsedTrackIDs: Set<UUID>
}

enum TimelineTrackDisplayStatePruner {
    static func prune(
        _ state: TimelineTrackDisplayState,
        validTrackIDs: Set<UUID>
    ) -> TimelineTrackDisplayState {
        TimelineTrackDisplayState(
            trackHeights: state.trackHeights.filter { validTrackIDs.contains($0.key) },
            collapsedTrackIDs: state.collapsedTrackIDs.intersection(validTrackIDs)
        )
    }
}

enum EditorShortcutGuard {
    static func shouldHandleGlobalShortcut(isTextInputFocused: Bool) -> Bool {
        !isTextInputFocused
    }
}

struct TranscriptCoverageAssessment: Equatable {
    let wordCount: Int
    let assetDuration: TimeInterval
    let firstStart: TimeInterval?
    let lastEnd: TimeInterval?
    let speakingSpan: TimeInterval
    let spokenWordDuration: TimeInterval

    var isSparseForStructuralAnalysis: Bool {
        guard wordCount > 0 else { return true }

        let minimumSpan = min(max(assetDuration * 0.2, 4), 12)
        let minimumSpokenDuration = min(max(assetDuration * 0.08, 2), 8)

        return wordCount < 40
            || speakingSpan < minimumSpan
            || spokenWordDuration < minimumSpokenDuration
    }
}

enum TranscriptAnalysisSupport {
    static func buildTimestampedTranscript(
        from words: [TranscriptWord],
        pauseThreshold: TimeInterval = 0.8
    ) -> String {
        guard !words.isEmpty else { return "" }

        var transcript = ""
        var sentenceWords: [String] = []
        var sentenceStart: TimeInterval = words.first?.start ?? 0

        for (index, word) in words.enumerated() {
            if sentenceWords.isEmpty {
                sentenceStart = word.start
            }

            sentenceWords.append(word.word)

            let isSentenceEnd = word.word.hasSuffix(".") || word.word.hasSuffix("?") || word.word.hasSuffix("!")
            let hasLongPause = index + 1 < words.count && (words[index + 1].start - word.end) > pauseThreshold
            let isLast = index == words.count - 1

            if isSentenceEnd || hasLongPause || isLast {
                transcript += "[\(formatTimestamp(sentenceStart))] \(sentenceWords.joined(separator: " "))\n"
                sentenceWords = []
            }
        }

        return transcript
    }

    static func assessCoverage(
        words: [TranscriptWord],
        assetDuration: TimeInterval
    ) -> TranscriptCoverageAssessment {
        let sortedWords = words.sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return lhs.end < rhs.end
            }
            return lhs.start < rhs.start
        }

        let firstStart = sortedWords.first?.start
        let lastEnd = sortedWords.last?.end
        let speakingSpan = max(0, (lastEnd ?? 0) - (firstStart ?? 0))
        let spokenWordDuration = sortedWords.reduce(0) { partialResult, word in
            partialResult + max(0, word.end - word.start)
        }

        return TranscriptCoverageAssessment(
            wordCount: sortedWords.count,
            assetDuration: assetDuration,
            firstStart: firstStart,
            lastEnd: lastEnd,
            speakingSpan: speakingSpan,
            spokenWordDuration: spokenWordDuration
        )
    }

    static func formatTimestamp(_ time: TimeInterval) -> String {
        let rounded = max(0, Int(time.rounded(.down)))
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        let seconds = rounded % 60

        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

enum EditorTimelineDefaults {
    static let stillImageDuration: TimeInterval = 5
}

enum TimelineInsertionStartResolver {
    static func resolve(
        explicitStart: TimeInterval?,
        primaryTrackEnd: TimeInterval,
        companionTrackEnd: TimeInterval?
    ) -> TimeInterval {
        if let explicitStart {
            return explicitStart
        }
        return max(primaryTrackEnd, companionTrackEnd ?? 0)
    }
}

struct SilenceRemovalExecutionResult: Equatable {
    let processedClipCount: Int
    let removedSilenceCount: Int
    let insertedClipCount: Int
    let deletedClipCount: Int
    let prunedFragmentCount: Int
}

enum SilenceKeepRangeBuilder {
    static let minimumRetainedSegmentDuration: TimeInterval = 0.15

    static func keepRanges(
        for clipSourceRange: TimeRange,
        silenceRanges: [TimeRange],
        minimumSilenceDuration: TimeInterval,
        edgeTolerance: TimeInterval = 0.01,
        minimumRetainedSegmentDuration: TimeInterval = minimumRetainedSegmentDuration
    ) -> [TimeRange] {
        let removals = silenceRanges
            .compactMap { silence -> TimeRange? in
                let overlapStart = max(silence.start, clipSourceRange.start)
                let overlapEnd = min(silence.end, clipSourceRange.end)
                guard overlapEnd - overlapStart >= minimumSilenceDuration else { return nil }
                return TimeRange(start: overlapStart, end: overlapEnd)
            }
            .sorted { $0.start < $1.start }

        guard !removals.isEmpty else { return [clipSourceRange] }

        var keepRanges: [TimeRange] = []
        var cursor = clipSourceRange.start

        for removal in removals {
            if removal.start > cursor + edgeTolerance {
                keepRanges.append(TimeRange(start: cursor, end: removal.start))
            }
            cursor = max(cursor, removal.end)
        }

        if cursor < clipSourceRange.end - edgeTolerance {
            keepRanges.append(TimeRange(start: cursor, end: clipSourceRange.end))
        }

        let minimumKeepDuration = max(
            minimumRetainedSegmentDuration,
            TimelineFragmentPruner.minimumRenderableDuration
        )
        return keepRanges.filter { $0.duration >= minimumKeepDuration }
    }
}

@MainActor
enum SilenceRemovalExecutor {
    static func remove(
        minimumDuration: TimeInterval,
        from targetClips: [Clip],
        appState: AppState,
        source: ActionSource
    ) -> SilenceRemovalExecutionResult {
        guard !targetClips.isEmpty else {
            return SilenceRemovalExecutionResult(
                processedClipCount: 0,
                removedSilenceCount: 0,
                insertedClipCount: 0,
                deletedClipCount: 0,
                prunedFragmentCount: 0
            )
        }

        let timeline = appState.timeline
        let trackIDsByClipID = Dictionary(uniqueKeysWithValues: timeline.tracks.flatMap { track in
            track.clips.map { ($0.id, track.id) }
        })

        var processedClipIDs = Set<UUID>()
        var processedClipCount = 0
        var removedSilenceCount = 0
        var insertedClipCount = 0
        var deletedClipCount = 0

        for clip in targetClips {
            guard processedClipIDs.insert(clip.id).inserted else { continue }
            guard let asset = appState.assets.first(where: { $0.id == clip.assetID }),
                  let silenceRanges = asset.analysis?.silenceRanges,
                  !silenceRanges.isEmpty else { continue }

            let linkedClips: [Clip]
            if let linkGroupID = clip.linkGroupID {
                linkedClips = appState.timeline.tracks.flatMap(\.clips).filter { $0.linkGroupID == linkGroupID }
            } else {
                linkedClips = [clip]
            }
            linkedClips.forEach { processedClipIDs.insert($0.id) }

            let keepRanges = SilenceKeepRangeBuilder.keepRanges(
                for: clip.sourceRange,
                silenceRanges: silenceRanges,
                minimumSilenceDuration: minimumDuration
            )

            let clipRemovals = silenceRanges.filter { silence in
                let overlapStart = max(silence.start, clip.sourceRange.start)
                let overlapEnd = min(silence.end, clip.sourceRange.end)
                return overlapEnd - overlapStart >= minimumDuration
            }
            guard !clipRemovals.isEmpty else { continue }

            removedSilenceCount += clipRemovals.count
            processedClipCount += 1

            let clipIDsToDelete = linkedClips.map(\.id)
            deletedClipCount += clipIDsToDelete.count
            try? appState.perform(.deleteClips(clipIDs: clipIDsToDelete), source: source)

            var timelineCursor = clip.timelineRange.start
            for keepRange in keepRanges {
                let linkGroupID = linkedClips.count > 1 ? UUID() : nil
                let referenceSpeed = max(clip.speed, 0.1)
                let segmentDuration = keepRange.duration / referenceSpeed

                for originalClip in linkedClips {
                    guard let trackID = trackIDsByClipID[originalClip.id] else { continue }
                    let newClip = Clip(
                        assetID: originalClip.assetID,
                        timelineRange: TimeRange(start: timelineCursor, duration: segmentDuration),
                        sourceRange: keepRange,
                        transform: originalClip.transform,
                        cropRect: originalClip.cropRect,
                        opacity: originalClip.opacity,
                        volume: originalClip.volume,
                        effects: originalClip.effects,
                        keyframes: originalClip.keyframes,
                        metadata: originalClip.metadata,
                        speed: originalClip.speed,
                        transitionIn: originalClip.transitionIn,
                        linkGroupID: linkGroupID,
                        blendMode: originalClip.blendMode
                    )
                    try? appState.perform(.insertClip(clip: newClip, trackID: trackID), source: source)
                    insertedClipCount += 1
                }

                timelineCursor += segmentDuration
            }
        }

        let prunedFragmentCount = appState.pruneNonRenderableClips()

        return SilenceRemovalExecutionResult(
            processedClipCount: processedClipCount,
            removedSilenceCount: removedSilenceCount,
            insertedClipCount: insertedClipCount,
            deletedClipCount: deletedClipCount,
            prunedFragmentCount: prunedFragmentCount
        )
    }
}

struct TimelineFragmentPruneResult {
    let timeline: Timeline
    let removedClipIDs: Set<UUID>
}

enum TimelineFragmentPruner {
    static let minimumRenderableDuration: TimeInterval = 0.02

    static func prune(
        _ timeline: Timeline,
        minimumDuration: TimeInterval = minimumRenderableDuration
    ) -> TimelineFragmentPruneResult {
        var sanitized = timeline
        var removedClipIDs: Set<UUID> = []

        for trackIndex in sanitized.tracks.indices {
            sanitized.tracks[trackIndex].clips.removeAll { clip in
                let tooShort = clip.timelineRange.duration < minimumDuration || clip.sourceRange.duration < minimumDuration
                if tooShort {
                    removedClipIDs.insert(clip.id)
                }
                return tooShort
            }

            sanitized.tracks[trackIndex].clips.sort {
                if $0.timelineRange.start != $1.timelineRange.start {
                    return $0.timelineRange.start < $1.timelineRange.start
                }
                return $0.timelineRange.end < $1.timelineRange.end
            }
        }

        return TimelineFragmentPruneResult(
            timeline: sanitized,
            removedClipIDs: removedClipIDs
        )
    }
}

struct MCPScreenshotWindowCandidate: Equatable {
    let windowNumber: Int
    let isMain: Bool
    let isKey: Bool
    let isVisible: Bool
    let isMiniaturized: Bool
}

enum MCPScreenshotWindowResolver {
    static func selectWindowNumber(
        from candidates: [MCPScreenshotWindowCandidate]
    ) -> Int? {
        candidates.first(where: { $0.isMain && $0.isVisible && !$0.isMiniaturized })?.windowNumber
        ?? candidates.first(where: { $0.isKey && $0.isVisible && !$0.isMiniaturized })?.windowNumber
        ?? candidates.first(where: { $0.isVisible && !$0.isMiniaturized })?.windowNumber
        ?? candidates.first(where: { !$0.isMiniaturized })?.windowNumber
        ?? candidates.first?.windowNumber
    }
}
