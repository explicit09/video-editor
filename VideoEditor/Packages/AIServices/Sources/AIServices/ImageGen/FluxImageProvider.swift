import Foundation

// MARK: - Errors

public enum FluxImageError: Error {
    case missingAPIKey
    case apiError(status: Int, body: String)
    case invalidResponse
    case generationFailed(String)
    case timeout
}

// MARK: - Provider

/// Black Forest Labs FLUX 2 Pro image generation provider.
/// Uses the BFL API (api.bfl.ai): submit a generation task, poll polling_url for result.
/// Supports multi-reference images for face/identity preservation.
public actor FluxImageProvider: ImageGenProvider {

    public let name = "flux"

    private let apiKey: String
    private let session: URLSession
    private let model: String

    /// - Parameters:
    ///   - apiKey: BFL API key
    ///   - model: "flux-2-pro-preview" (default) or "flux-kontext-pro"
    public init(apiKey: String, model: String = "flux-2-pro-preview") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
    }

    public static func fromEnvironment(model: String = "flux-2-pro-preview") throws -> FluxImageProvider {
        guard let key = ProcessInfo.processInfo.environment["BFL_API_KEY"], !key.isEmpty else {
            throw FluxImageError.missingAPIKey
        }
        return FluxImageProvider(apiKey: key, model: model)
    }

    // MARK: - ImageGenProvider

    public func generateImage(
        prompt: String,
        referenceImages: [Data],
        size: ImageGenSize
    ) async throws -> Data {
        let components = size.rawValue.split(separator: "x")
        let width = Int(components[0]) ?? 1536
        let height = Int(components[1]) ?? 1024

        // Step 1: Submit generation task — returns id + polling_url
        let submission: (id: String, pollingUrl: String)
        if referenceImages.isEmpty {
            submission = try await submitTextToImage(prompt: prompt, width: width, height: height)
        } else {
            submission = try await submitImageEdit(prompt: prompt, referenceImages: referenceImages, width: width, height: height)
        }

        // Step 2: Poll the polling_url for result
        return try await pollForResult(pollingUrl: submission.pollingUrl)
    }

    // MARK: - Text-to-Image

    private func submitTextToImage(prompt: String, width: Int, height: Int) async throws -> (id: String, pollingUrl: String) {
        let url = URL(string: "https://api.bfl.ai/v1/\(model)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-key")

        let body: [String: Any] = [
            "prompt": prompt,
            "width": width,
            "height": height,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FluxImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw FluxImageError.apiError(status: httpResponse.statusCode, body: String(responseBody.prefix(500)))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let taskId = json["id"] as? String,
            let pollingUrl = json["polling_url"] as? String
        else {
            throw FluxImageError.invalidResponse
        }

        return (id: taskId, pollingUrl: pollingUrl)
    }

    // MARK: - Image Edit (with reference images)

    private func submitImageEdit(prompt: String, referenceImages: [Data], width: Int, height: Int) async throws -> (id: String, pollingUrl: String) {
        let url = URL(string: "https://api.bfl.ai/v1/\(model)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-key")

        // Build face preservation prompt prefix
        let imageCount = referenceImages.count
        var preservationPrefix = "Place the person from image 1"
        if imageCount > 1 {
            preservationPrefix += " and the person from image 2"
        }
        preservationPrefix += " in this scene while preserving their exact facial features, eye color, and expression. Do not alter their appearance. "

        let enhancedPrompt = preservationPrefix + prompt

        var body: [String: Any] = [
            "prompt": enhancedPrompt,
            "input_image": referenceImages[0].base64EncodedString(),
            "width": width,
            "height": height,
            "output_format": "png",
        ]

        // FLUX.2 Pro supports input_image, input_image_2, ... up to input_image_8
        for i in 1..<min(referenceImages.count, 8) {
            body["input_image_\(i + 1)"] = referenceImages[i].base64EncodedString()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FluxImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw FluxImageError.apiError(status: httpResponse.statusCode, body: String(responseBody.prefix(500)))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let taskId = json["id"] as? String,
            let pollingUrl = json["polling_url"] as? String
        else {
            throw FluxImageError.invalidResponse
        }

        return (id: taskId, pollingUrl: pollingUrl)
    }

    // MARK: - Poll for Result

    private func pollForResult(pollingUrl: String) async throws -> Data {
        guard let pollUrl = URL(string: pollingUrl) else {
            throw FluxImageError.invalidResponse
        }

        let maxAttempts = 120  // 120 attempts * 0.5s = 60s max
        var attempts = 0

        while attempts < maxAttempts {
            var request = URLRequest(url: pollUrl)
            request.setValue("application/json", forHTTPHeaderField: "accept")
            request.setValue(apiKey, forHTTPHeaderField: "x-key")

            let (data, _) = try await session.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw FluxImageError.invalidResponse
            }

            switch status {
            case "Ready":
                guard let result = json["result"] as? [String: Any],
                      let imageUrlString = result["sample"] as? String,
                      let imageUrl = URL(string: imageUrlString) else {
                    throw FluxImageError.invalidResponse
                }
                // Download the image (signed URL valid for 10 min)
                let (imageData, _) = try await session.data(from: imageUrl)
                return imageData

            case "Pending", "Processing":
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds per docs
                attempts += 1
                continue

            case "Error", "Failed":
                let errorMsg = (json["result"] as? [String: Any])?["error"] as? String ?? "Unknown error"
                throw FluxImageError.generationFailed(errorMsg)

            default:
                try await Task.sleep(nanoseconds: 500_000_000)
                attempts += 1
                continue
            }
        }

        throw FluxImageError.timeout
    }
}
