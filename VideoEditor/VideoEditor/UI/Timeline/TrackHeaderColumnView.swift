import SwiftUI
import EditorCore

struct TrackHeaderColumnView: View {
    let tracks: [Track]
    let viewState: TimelineViewState
    let layoutState: TrackLayoutState
    let coordinator: TimelineScrollCoordinator

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: CinematicSpacing.clipGap) {
                ForEach(tracks) { track in
                    TrackHeaderRowView(
                        track: track,
                        viewState: viewState,
                        layoutState: layoutState
                    )
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .offset(y: -coordinator.verticalOffset)
        }
        .clipped()
        .background(CinematicTheme.surfaceContainer)
    }
}
