import SwiftUI
import EditorCore

// MARK: - Overlay Monitor Controls

/// On-canvas manipulation handles for PiP overlay clips in the program monitor.
/// Renders a selection frame with corner handles for drag-to-move and drag-to-scale.
struct OverlayMonitorControls: View {
    let clip: Clip
    let onMove: (CGSize) -> Void
    let onScale: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            let frame = OverlayGeometry.displayFrame(for: clip, canvasSize: proxy.size)
            ZStack(alignment: .topLeading) {
                // Selection border
                Rectangle()
                    .stroke(UtilityTheme.accent, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)

                // Corner scale handles
                OverlayCornerHandles(frame: frame, onScale: onScale)
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onMove(value.translation)
                    }
            )
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Corner Handles

/// Four corner drag handles for resizing an overlay clip.
private struct OverlayCornerHandles: View {
    let frame: CGRect
    let onScale: (CGSize) -> Void

    private let handleSize: CGFloat = 12

    var body: some View {
        // Top-left
        cornerHandle(at: .zero)
        // Top-right
        cornerHandle(at: CGPoint(x: frame.width - handleSize, y: 0))
        // Bottom-left
        cornerHandle(at: CGPoint(x: 0, y: frame.height - handleSize))
        // Bottom-right
        cornerHandle(at: CGPoint(x: frame.width - handleSize, y: frame.height - handleSize))
    }

    private func cornerHandle(at offset: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(UtilityTheme.accent)
            .frame(width: handleSize, height: handleSize)
            .offset(x: offset.x, y: offset.y)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onScale(value.translation)
                    }
            )
    }
}
