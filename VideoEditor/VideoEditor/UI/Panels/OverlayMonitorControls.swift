import SwiftUI
import EditorCore

// MARK: - Overlay Monitor Controls

/// On-canvas manipulation handles for PiP overlay clips in the program monitor.
/// Uses a Canvas-based approach: a single overlay that only intercepts events
/// within the PiP frame rect, letting everything else pass through to the player.
struct OverlayMonitorControls: View {
    let clip: Clip
    let onTransformUpdate: (Transform2D) -> Void

    @GestureState private var dragStart: Transform2D?
    @State private var currentFrame: CGRect = .zero

    var body: some View {
        GeometryReader { proxy in
            let frame = OverlayGeometry.displayFrame(for: clip, canvasSize: proxy.size)

            // Single draggable surface positioned at the PiP location.
            // Color.white.opacity(0.001) is visible enough for hit testing
            // but invisible to the user.
            Color.white.opacity(0.001)
                .frame(width: max(frame.width, 24), height: max(frame.height, 24))
                .overlay {
                    ZStack {
                        Rectangle()
                            .stroke(UtilityTheme.accent, lineWidth: 2)

                        // Corner handles
                        handleDot(x: 0, y: 0, size: frame)
                        handleDot(x: frame.width, y: 0, size: frame)
                        handleDot(x: 0, y: frame.height, size: frame)
                        handleDot(x: frame.width, y: frame.height, size: frame)
                    }
                }
                .position(x: frame.midX, y: frame.midY)
                .gesture(
                    DragGesture()
                        .updating($dragStart) { _, state, _ in
                            if state == nil { state = clip.transform }
                        }
                        .onChanged { value in
                            let base = dragStart ?? clip.transform
                            let updated = OverlayGeometry.transformByTranslating(
                                base,
                                delta: value.translation,
                                canvasSize: proxy.size
                            )
                            onTransformUpdate(updated)
                        }
                )
        }
    }

    private func handleDot(x: CGFloat, y: CGFloat, size: CGRect) -> some View {
        Circle()
            .fill(UtilityTheme.accent)
            .frame(width: 10, height: 10)
            .position(x: x, y: y)
    }
}
