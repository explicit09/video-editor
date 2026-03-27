import SwiftUI

struct MediaBrowserPanel: View {
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Text("Media Browser")
                .foregroundStyle(.secondary)
        }
    }
}
