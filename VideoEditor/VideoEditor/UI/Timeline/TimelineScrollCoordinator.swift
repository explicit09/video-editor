import Foundation
import Observation

@MainActor @Observable
final class TimelineScrollCoordinator {
    var horizontalOffset: Double = 0
    var verticalOffset: Double = 0
    var pendingRequest: TimelineScrollRequest?

    func update(horizontal: Double, vertical: Double) {
        horizontalOffset = horizontal
        verticalOffset = vertical
    }

    func requestScroll(_ request: TimelineScrollRequest?) {
        pendingRequest = request
    }
}
