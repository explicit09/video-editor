import Foundation
import AVFoundation

/// Batch export: queue multiple export jobs with different presets.
/// Each job runs sequentially through ExportEngine.
@MainActor @Observable
public final class BatchExporter {
    public private(set) var jobs: [ExportJob] = []
    public private(set) var currentJobIndex: Int?
    public private(set) var isRunning = false

    public struct ExportJob: Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let outputURL: URL
        public let preset: String
        public let fileType: AVFileType
        public var status: JobStatus

        public enum JobStatus: Sendable {
            case pending
            case exporting(progress: Float)
            case completed
            case failed(String)
        }

        public init(name: String, outputURL: URL, preset: String = AVAssetExportPresetHighestQuality, fileType: AVFileType = .mp4) {
            self.id = UUID()
            self.name = name
            self.outputURL = outputURL
            self.preset = preset
            self.fileType = fileType
            self.status = .pending
        }
    }

    public init() {}

    /// Add a job to the queue.
    public func addJob(_ job: ExportJob) {
        jobs.append(job)
    }

    /// Add multiple preset exports for the same timeline.
    public func addPresetBatch(baseName: String, outputDir: URL, presets: [(name: String, preset: String, ext: String, fileType: AVFileType)]) {
        for p in presets {
            let url = outputDir.appendingPathComponent("\(baseName)_\(p.name).\(p.ext)")
            addJob(ExportJob(name: p.name, outputURL: url, preset: p.preset, fileType: p.fileType))
        }
    }

    /// Run all pending jobs sequentially.
    public func runAll(timeline: Timeline, assets: [MediaAsset]) async {
        isRunning = true

        for i in jobs.indices {
            guard case .pending = jobs[i].status else { continue }
            currentJobIndex = i
            jobs[i].status = .exporting(progress: 0)

            let engine = ExportEngine()
            await engine.export(
                timeline: timeline,
                assets: assets,
                to: jobs[i].outputURL,
                preset: jobs[i].preset,
                fileType: jobs[i].fileType
            )

            switch engine.state {
            case .completed:
                jobs[i].status = .completed
            case .failed(let msg):
                jobs[i].status = .failed(msg)
            default:
                jobs[i].status = .failed("Unknown error")
            }
        }

        currentJobIndex = nil
        isRunning = false
    }

    /// Cancel all remaining jobs.
    public func cancelAll() {
        for i in jobs.indices {
            if case .pending = jobs[i].status {
                jobs[i].status = .failed("Cancelled")
            }
        }
        isRunning = false
    }

    /// Clear completed/failed jobs.
    public func clearCompleted() {
        jobs.removeAll { job in
            if case .completed = job.status { return true }
            if case .failed = job.status { return true }
            return false
        }
    }

    /// Standard batch presets
    public static let socialMediaBatch: [(name: String, preset: String, ext: String, fileType: AVFileType)] = [
        ("YouTube_4K", AVAssetExportPreset3840x2160, "mp4", .mp4),
        ("YouTube_1080p", AVAssetExportPreset1920x1080, "mp4", .mp4),
        ("Instagram_Square", AVAssetExportPreset1920x1080, "mp4", .mp4),
    ]
}
