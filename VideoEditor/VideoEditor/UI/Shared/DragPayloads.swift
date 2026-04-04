import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    static let timelineAssetDragPayload = UTType(exportedAs: "com.videoeditor.timeline-asset")
}

struct TimelineAssetDragPayload: Codable, Transferable {
    let assetID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .timelineAssetDragPayload)
    }
}
