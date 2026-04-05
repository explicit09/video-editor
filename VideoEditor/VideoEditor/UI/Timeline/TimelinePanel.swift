import Foundation
import SwiftUI
import AppKit
import EditorCore

struct TimelinePanel: View {
    let tool: EditorTool
    @Environment(AppState.self) private var appState
    @State private var thumbnails: [UUID: CGImage] = [:]
    @State private var pinchBaseZoom: Double?

    /// Re-run media loading when the timeline changes, when assets become available,
    /// or when background analysis writes a waveform profile onto an existing asset.
    private var mediaLoadKey: [String] {
        let assetsByID = Dictionary(uniqueKeysWithValues: appState.assets.map { ($0.id, $0) })

        return appState.timeline.tracks
            .flatMap(\.clips)
            .map { clip in
                guard let asset = assetsByID[clip.assetID] else {
                    return "\(clip.assetID.uuidString):missing"
                }

                let waveformCount = asset.analysis?.loudnessProfile?.count ?? 0
                return "\(clip.assetID.uuidString):present:\(waveformCount)"
            }
    }

    var body: some View {
        TimelineShellView(
            tool: tool,
            timeline: appState.timeline,
            viewState: appState.timelineViewState,
            thumbnails: thumbnails,
            waveformStates: appState.media.waveformStates
        )
        .background(CinematicTheme.surfaceContainer)
        .task(id: mediaLoadKey) {
            await loadVisibleMedia()
        }
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    if pinchBaseZoom == nil {
                        pinchBaseZoom = appState.timelineViewState.zoom
                    }
                    appState.timelineViewState.setZoom((pinchBaseZoom ?? appState.timelineViewState.zoom) * value.magnification)
                }
                .onEnded { _ in
                    pinchBaseZoom = nil
                }
        )
        .focusable()
        .onKeyPress(.space) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            appState.playbackEngine.togglePlayPause()
            return .handled
        }
        .onKeyPress(.delete) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            deleteSelectedClips()
            return .handled
        }
        .onKeyPress(KeyEquivalent("\u{7F}")) {
            guard EditorShortcutGuard.shouldHandleGlobalShortcut(isTextInputFocused: textInputIsFocused) else {
                return .ignored
            }
            guard !appState.timelineViewState.selectedClipIDs.isEmpty else { return .ignored }
            deleteSelectedClips()
            return .handled
        }
    }

    private var textInputIsFocused: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }

    private func loadVisibleMedia() async {
        for track in appState.timeline.tracks {
            for clip in track.clips {
                let assetID = clip.assetID
                guard let asset = appState.assets.first(where: { $0.id == assetID }) else { continue }

                if thumbnails[assetID] == nil {
                    let thumb = await appState.media.thumbnail(for: assetID)
                    if let thumb { thumbnails[assetID] = thumb }
                }

                await appState.media.refreshWaveformState(for: asset.id)
            }
        }
    }

    private func deleteSelectedClips() {
        let selected = Array(appState.timelineViewState.selectedClipIDs)
        guard !selected.isEmpty else { return }
        try? appState.perform(.deleteClips(clipIDs: selected))
        appState.timelineViewState.clearSelection()
    }
}
