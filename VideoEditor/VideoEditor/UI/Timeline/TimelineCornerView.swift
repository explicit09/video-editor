import SwiftUI

struct TimelineCornerView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CinematicTheme.primary.opacity(0.92))

            VStack(alignment: .leading, spacing: 1) {
                Text("TRACKS")
                    .font(.cinLabel)
                    .tracking(1.2)
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.7))

                Text("TIMELINE")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(CinematicTheme.onSurfaceVariant.opacity(0.48))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: [
                    CinematicTheme.surfaceContainerHighest,
                    CinematicTheme.surfaceContainerHigh,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .bottomTrailing) {
            Rectangle()
                .fill(CinematicTheme.outlineVariant.opacity(0.26))
                .frame(height: 1)
        }
    }
}
