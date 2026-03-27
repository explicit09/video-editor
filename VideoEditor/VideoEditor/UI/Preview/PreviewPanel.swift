import SwiftUI

struct PreviewPanel: View {
    var body: some View {
        ZStack {
            Color.black
            Text("Preview")
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
