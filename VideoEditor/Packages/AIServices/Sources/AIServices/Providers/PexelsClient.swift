import Foundation

/// Client for the Pexels free stock video API.
/// API docs: https://www.pexels.com/api/documentation/#videos-search
public actor PexelsClient {
    private let apiKey: String
    private let session = URLSession.shared
    private let baseURL = "https://api.pexels.com/videos"

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public struct VideoResult: Sendable {
        public let id: Int
        public let url: String          // Pexels page URL
        public let duration: Int         // seconds
        public let width: Int
        public let height: Int
        public let videoFiles: [VideoFile]
        public let thumbnailURL: String?
    }

    public struct VideoFile: Sendable {
        public let id: Int
        public let quality: String       // "hd", "sd"
        public let fileType: String      // "video/mp4"
        public let width: Int
        public let height: Int
        public let link: String          // Direct download URL
    }

    /// Search for videos matching a query.
    public func search(query: String, perPage: Int = 5, orientation: String? = nil) async throws -> [VideoResult] {
        var components = URLComponents(string: "\(baseURL)/search")!
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: String(perPage)),
        ]
        if let orientation { queryItems.append(URLQueryItem(name: "orientation", value: orientation)) }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PexelsError.apiError("Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videos = json["videos"] as? [[String: Any]] else {
            return []
        }

        return videos.compactMap { parseVideo($0) }
    }

    /// Download a video file to a local URL.
    public func download(fileURL: String, to destination: URL) async throws {
        guard let url = URL(string: fileURL) else { throw PexelsError.invalidURL }
        let (tempURL, _) = try await session.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    private func parseVideo(_ json: [String: Any]) -> VideoResult? {
        guard let id = json["id"] as? Int,
              let url = json["url"] as? String,
              let duration = json["duration"] as? Int,
              let width = json["width"] as? Int,
              let height = json["height"] as? Int,
              let files = json["video_files"] as? [[String: Any]] else { return nil }

        let videoFiles = files.compactMap { file -> VideoFile? in
            guard let fid = file["id"] as? Int,
                  let quality = file["quality"] as? String,
                  let fileType = file["file_type"] as? String,
                  let w = file["width"] as? Int?,
                  let h = file["height"] as? Int?,
                  let link = file["link"] as? String else { return nil }
            return VideoFile(id: fid, quality: quality, fileType: fileType, width: w ?? 0, height: h ?? 0, link: link)
        }

        let thumbURL = json["image"] as? String
        return VideoResult(id: id, url: url, duration: duration, width: width, height: height, videoFiles: videoFiles, thumbnailURL: thumbURL)
    }

    public enum PexelsError: Error, LocalizedError {
        case apiError(String)
        case invalidURL
        case noResults
        public var errorDescription: String? {
            switch self {
            case .apiError(let msg): return "Pexels API: \(msg)"
            case .invalidURL: return "Invalid URL"
            case .noResults: return "No results found"
            }
        }
    }
}
