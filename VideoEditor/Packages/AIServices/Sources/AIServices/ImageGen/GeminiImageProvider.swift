import Foundation

// MARK: - Errors

public enum GeminiImageError: Error {
    case missingAPIKey
    case apiError(status: Int, body: String)
    case invalidResponse
    case noImageInResponse
}

// MARK: - Provider

public actor GeminiImageProvider: ImageGenProvider {

    public let name = "gemini"

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    public static func fromEnvironment() throws -> GeminiImageProvider {
        guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? ProcessInfo.processInfo.environment["GOOGLE_AI_API_KEY"], !key.isEmpty else {
            throw GeminiImageError.missingAPIKey
        }
        return GeminiImageProvider(apiKey: key)
    }

    // MARK: - ImageGenProvider

    public func generateImage(
        prompt: String,
        referenceImages: [Data],
        size: ImageGenSize
    ) async throws -> Data {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw GeminiImageError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build parts array
        var parts: [[String: Any]] = [
            ["text": prompt]
        ]

        for imageData in referenceImages {
            let b64 = imageData.base64EncodedString()
            parts.append([
                "inline_data": [
                    "mime_type": "image/png",
                    "data": b64
                ]
            ])
        }

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ],
            "generationConfig": [
                "responseModalities": ["TEXT", "IMAGE"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw GeminiImageError.apiError(status: httpResponse.statusCode, body: responseBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiImageError.invalidResponse
        }

        // Navigate: candidates[0].content.parts -> find part with inlineData containing image
        guard
            let candidates = json["candidates"] as? [[String: Any]],
            let firstCandidate = candidates.first,
            let content = firstCandidate["content"] as? [String: Any],
            let responseParts = content["parts"] as? [[String: Any]]
        else {
            throw GeminiImageError.invalidResponse
        }

        for part in responseParts {
            guard let inlineData = part["inlineData"] as? [String: Any],
                  let mimeType = inlineData["mimeType"] as? String,
                  mimeType.hasPrefix("image/"),
                  let b64String = inlineData["data"] as? String,
                  let imageData = Data(base64Encoded: b64String)
            else {
                continue
            }
            return imageData
        }

        throw GeminiImageError.noImageInResponse
    }
}
