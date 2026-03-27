import SwiftUI

struct InspectorPanel: View {
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Text("Inspector")
                .foregroundStyle(.secondary)
        }
    }
}
