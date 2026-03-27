import SwiftUI

struct TimelinePanel: View {
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Text("Timeline")
                .foregroundStyle(.secondary)
        }
    }
}
