import Foundation

// MARK: - Errors

public enum OpenAIImageError: Error {
    case missingAPIKey
    case apiError(status: Int, body: String)
    case invalidResponse
}

// MARK: - Provider

public actor OpenAIImageProvider: ImageGenProvider {

    public let name = "openai"

    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    public static func fromEnvironment() throws -> OpenAIImageProvider {
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            throw OpenAIImageError.missingAPIKey
        }
        return OpenAIImageProvider(apiKey: key)
    }

    // MARK: - ImageGenProvider

    public func generateImage(
        prompt: String,
        referenceImages: [Data],
        size: ImageGenSize
    ) async throws -> Data {
        if referenceImages.isEmpty {
            return try await generateFromText(prompt: prompt, size: size)
        } else {
            return try await editWithReferences(prompt: prompt, referenceImages: referenceImages, size: size)
        }
    }

    /// Text-to-image via /v1/images/generations (no reference images).
    private func generateFromText(prompt: String, size: ImageGenSize) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-image-1.5",
            "prompt": prompt,
            "n": 1,
            "size": size.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await executeAndParse(request: request)
    }

    /// Image editing via /v1/images/edits (with reference images).
    private func editWithReferences(prompt: String, referenceImages: [Data], size: ImageGenSize) async throws -> Data {
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        appendFormField(&body, boundary: boundary, name: "model", value: "gpt-image-1.5")
        appendFormField(&body, boundary: boundary, name: "prompt", value: prompt)
        appendFormField(&body, boundary: boundary, name: "n", value: "1")
        appendFormField(&body, boundary: boundary, name: "size", value: size.rawValue)

        for (index, imageData) in referenceImages.enumerated() {
            appendFormFile(
                &body,
                boundary: boundary,
                fieldName: "image[]",
                fileName: "ref_\(index).png",
                contentType: "image/png",
                fileData: imageData
            )
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        return try await executeAndParse(request: request)
    }

    private func executeAndParse(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIImageError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIImageError.apiError(status: httpResponse.statusCode, body: String(responseBody.prefix(500)))
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataArray = json["data"] as? [[String: Any]],
            let first = dataArray.first,
            let b64String = first["b64_json"] as? String,
            let imageData = Data(base64Encoded: b64String)
        else {
            throw OpenAIImageError.invalidResponse
        }

        return imageData
    }

    // MARK: - Multipart Helpers

    private func appendFormField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    private func appendFormFile(
        _ body: inout Data,
        boundary: String,
        fieldName: String,
        fileName: String,
        contentType: String,
        fileData: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }
}
