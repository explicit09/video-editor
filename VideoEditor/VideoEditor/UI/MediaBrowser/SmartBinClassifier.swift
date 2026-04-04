import Foundation
import EditorCore

/// Classifies assets into Smart Bins based on metadata, analysis, and filename heuristics.
struct SmartBinClassifier {

    struct SmartBin: Identifiable {
        let id: String
        let label: String
        let icon: String
        let assetIDs: [UUID]

        var count: Int { assetIDs.count }
    }

    /// Generate Smart Bins from the current asset list.
    static func classify(_ assets: [MediaAsset]) -> [SmartBin] {
        var bins: [SmartBin] = []

        // Type-based bins
        let videos = assets.filter { $0.type == .video }
        let audio = assets.filter { $0.type == .audio }
        let images = assets.filter { $0.type == .image }

        if !videos.isEmpty { bins.append(SmartBin(id: "all-video", label: "All Video", icon: "film", assetIDs: videos.map(\.id))) }
        if !audio.isEmpty { bins.append(SmartBin(id: "all-audio", label: "All Audio", icon: "waveform", assetIDs: audio.map(\.id))) }
        if !images.isEmpty { bins.append(SmartBin(id: "all-images", label: "Images", icon: "photo", assetIDs: images.map(\.id))) }

        // Duration-based bins
        let shortClips = assets.filter { $0.type == .video && $0.duration > 0 && $0.duration <= 30 }
        let longForm = assets.filter { $0.type == .video && $0.duration > 300 }
        if !shortClips.isEmpty { bins.append(SmartBin(id: "short", label: "Short Clips", icon: "bolt", assetIDs: shortClips.map(\.id))) }
        if !longForm.isEmpty { bins.append(SmartBin(id: "long", label: "Long Form", icon: "clock", assetIDs: longForm.map(\.id))) }

        // Analysis-based bins
        let transcribed = assets.filter { $0.analysis?.transcript != nil && !($0.analysis?.transcript?.isEmpty ?? true) }
        let analyzed = assets.filter { $0.analysis?.silenceRanges != nil || $0.analysis?.shotBoundaries != nil }
        if !transcribed.isEmpty { bins.append(SmartBin(id: "transcribed", label: "Transcribed", icon: "text.alignleft", assetIDs: transcribed.map(\.id))) }
        if !analyzed.isEmpty { bins.append(SmartBin(id: "analyzed", label: "AI Analyzed", icon: "sparkles", assetIDs: analyzed.map(\.id))) }

        // Filename heuristic bins
        let interviewKeywords = ["interview", "talking", "podcast", "conversation", "chat"]
        let brollKeywords = ["broll", "b-roll", "cutaway", "insert", "overlay"]
        let musicKeywords = ["music", "beat", "track", "song", "soundtrack", "bgm", "lo-fi", "lofi"]

        let interviews = assets.filter { asset in
            interviewKeywords.contains(where: { asset.name.localizedCaseInsensitiveContains($0) })
        }
        let broll = assets.filter { asset in
            brollKeywords.contains(where: { asset.name.localizedCaseInsensitiveContains($0) })
        }
        let music = assets.filter { asset in
            musicKeywords.contains(where: { asset.name.localizedCaseInsensitiveContains($0) })
        }

        if !interviews.isEmpty { bins.append(SmartBin(id: "interviews", label: "Interviews", icon: "person.2", assetIDs: interviews.map(\.id))) }
        if !broll.isEmpty { bins.append(SmartBin(id: "broll", label: "B-Roll", icon: "rectangle.stack", assetIDs: broll.map(\.id))) }
        if !music.isEmpty { bins.append(SmartBin(id: "music", label: "Music", icon: "music.note", assetIDs: music.map(\.id))) }

        // Scene label bins (from AI analysis if available)
        var labelGroups: [String: [UUID]] = [:]
        for asset in assets {
            guard let scenes = asset.analysis?.sceneDescriptions else { continue }
            for scene in scenes {
                guard let label = scene.label, !label.isEmpty else { continue }
                labelGroups[label, default: []].append(asset.id)
            }
        }
        for (label, ids) in labelGroups.sorted(by: { $0.key < $1.key }) {
            let uniqueIDs = Array(Set(ids))
            bins.append(SmartBin(id: "scene-\(label)", label: label, icon: "eye", assetIDs: uniqueIDs))
        }

        return bins
    }
}
