import SwiftUI

struct ContentView: View {
    var body: some View {
        HSplitView {
            MediaBrowserPanel()
                .frame(minWidth: 200, idealWidth: 250)

            VSplitView {
                PreviewPanel()
                    .frame(minHeight: 200)

                TimelinePanel()
                    .frame(minHeight: 150)
            }

            InspectorPanel()
                .frame(minWidth: 200, idealWidth: 250)
        }
        .frame(minWidth: 1200, minHeight: 700)
    }
}
