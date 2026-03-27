import Foundation
import EditorCore

/// Serializes the current editor state into a structured representation
/// that AI models can consume. Context is tiered to minimize token usage.
public struct AIContextBuilder: Sendable {

    public enum ContextLevel: Sendable {
        /// Track names/IDs, clip count. For structural edits ("add track").
        case minimal
        /// Tracks + clip positions, asset names, selection. For most editing.
        case standard
        /// Everything + transcripts, analysis. For content-aware edits.
        case full
    }

    public init() {}

    @MainActor
    public func buildContext(
        timeline: Timeline,
        assets: [MediaAsset],
        playheadPosition: TimeInterval,
        selectedClipIDs: Set<UUID>,
        recentActions: [ActionEvent],
        level: ContextLevel = .standard
    ) -> AIContext {
        let trackSummaries = timeline.tracks.map { track in
            AIContext.TrackSummary(
                id: track.id.uuidString,
                name: track.name,
                type: track.type.rawValue,
                clipCount: track.clips.count,
                isMuted: track.isMuted,
                isLocked: track.isLocked,
                clips: level == .minimal ? nil : track.clips.map {
                    buildClipSummary($0, assets: assets, isSelected: selectedClipIDs.contains($0.id), includeTranscript: level == .full)
                }
            )
        }

        let assetSummaries = level == .minimal ? nil : assets.map { asset in
            AIContext.AssetSummary(
                id: asset.id.uuidString,
                name: asset.name,
                type: asset.type.rawValue,
                duration: asset.duration,
                hasProxy: asset.proxyURL != nil,
                hasTranscript: asset.analysis?.transcript != nil,
                silenceRangeCount: asset.analysis?.silenceRanges?.count ?? 0
            )
        }

        let actionSummaries = level == .full ? recentActions.map { action in
            AIContext.ActionSummary(
                commandName: action.commandName,
                source: action.source.rawValue,
                clipIDs: action.clipIDs.map(\.uuidString),
                trackIDs: action.trackIDs.map(\.uuidString),
                parameters: action.parameters
            )
        } : nil

        return AIContext(
            timeline: AIContext.TimelineSummary(
                trackCount: timeline.tracks.count,
                duration: timeline.duration,
                markerCount: timeline.markers.count,
                tracks: trackSummaries
            ),
            assets: assetSummaries,
            playheadPosition: playheadPosition,
            selectedClipIDs: selectedClipIDs.map(\.uuidString),
            recentActions: actionSummaries
        )
    }

    private func buildClipSummary(_ clip: Clip, assets: [MediaAsset], isSelected: Bool, includeTranscript: Bool) -> AIContext.ClipSummary {
        let assetName = assets.first(where: { $0.id == clip.assetID })?.name

        return AIContext.ClipSummary(
            id: clip.id.uuidString,
            assetID: clip.assetID.uuidString,
            assetName: assetName,
            startTime: clip.timelineRange.start,
            endTime: clip.timelineRange.end,
            duration: clip.timelineRange.duration,
            sourceStart: clip.sourceRange.start,
            sourceEnd: clip.sourceRange.end,
            isSelected: isSelected,
            label: clip.metadata.label,
            transcript: includeTranscript ? clip.metadata.transcriptSegment?.text : nil,
            sceneType: clip.metadata.sceneType,
            tags: clip.metadata.tags,
            opacity: clip.opacity,
            volume: clip.volume,
            effectCount: clip.effects.count
        )
    }
}

// MARK: - AIContext

public struct AIContext: Codable, Sendable {
    public let timeline: TimelineSummary
    public let assets: [AssetSummary]?
    public let playheadPosition: TimeInterval
    public let selectedClipIDs: [String]
    public let recentActions: [ActionSummary]?

    public func toJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    public struct TimelineSummary: Codable, Sendable {
        public let trackCount: Int
        public let duration: TimeInterval
        public let markerCount: Int
        public let tracks: [TrackSummary]
    }

    public struct TrackSummary: Codable, Sendable {
        public let id: String
        public let name: String
        public let type: String
        public let clipCount: Int
        public let isMuted: Bool
        public let isLocked: Bool
        public let clips: [ClipSummary]?
    }

    public struct ClipSummary: Codable, Sendable {
        public let id: String
        public let assetID: String
        public let assetName: String?
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let duration: TimeInterval
        public let sourceStart: TimeInterval
        public let sourceEnd: TimeInterval
        public let isSelected: Bool
        public let label: String?
        public let transcript: String?
        public let sceneType: String?
        public let tags: [String]
        public let opacity: Double
        public let volume: Double
        public let effectCount: Int
    }

    public struct AssetSummary: Codable, Sendable {
        public let id: String
        public let name: String
        public let type: String
        public let duration: TimeInterval
        public let hasProxy: Bool
        public let hasTranscript: Bool
        public let silenceRangeCount: Int
    }

    public struct ActionSummary: Codable, Sendable {
        public let commandName: String
        public let source: String
        public let clipIDs: [String]
        public let trackIDs: [String]
        public let parameters: [String: String]
    }
}
