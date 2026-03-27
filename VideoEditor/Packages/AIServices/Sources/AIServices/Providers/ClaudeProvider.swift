import Foundation

/// Claude API provider (Anthropic). First concrete AIProvider implementation.
public final class ClaudeProvider: AIProvider, @unchecked Sendable {
    public let name = "Claude"

    private let apiKey: String
    private let model: String
    private let baseURL: URL
    private let session: URLSession

    public init(
        apiKey: String,
        model: String = "claude-sonnet-4-20250514",
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.session = URLSession(configuration: .default)
    }

    /// Convenience: load API key from environment.
    public static func fromEnvironment(model: String = "claude-sonnet-4-20250514") -> ClaudeProvider? {
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else { return nil }
        return ClaudeProvider(apiKey: key, model: model)
    }

    // MARK: - AIProvider

    public func complete(messages: [AIMessage], tools: [AIToolDefinition]) async throws -> AIResponse {
        let url = baseURL.appendingPathComponent("/v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = ClaudeRequest(
            model: model,
            max_tokens: 4096,
            messages: messages.map { ClaudeMessage(role: $0.role, content: $0.content) },
            tools: tools.isEmpty ? nil : tools.map(convertTool),
            system: systemPrompt
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeError.apiError(status: httpResponse.statusCode, body: body)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return convertResponse(claudeResponse)
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        """
        You are an AI assistant integrated into a video editor. You can see the current state \
        of the editor (timeline, tracks, clips, assets) and execute editing operations using tools.

        When the user asks you to edit, use the available tools to make changes. \
        Explain what you're doing briefly. If you need more information, ask.

        Important rules:
        - All clip/track/asset references use UUIDs. Use the exact IDs from the editor context.
        - Times are in seconds.
        - You can chain multiple tool calls to accomplish complex edits.
        - If an operation might be destructive, confirm with the user first.
        """
    }

    // MARK: - Convert to Claude API format

    private func convertTool(_ tool: AIToolDefinition) -> ClaudeTool {
        ClaudeTool(
            name: tool.name,
            description: tool.description,
            input_schema: tool.parameters
        )
    }

    private func convertResponse(_ response: ClaudeResponse) -> AIResponse {
        var text = ""
        var toolCalls: [AIToolCall] = []

        for block in response.content {
            switch block {
            case .text(let t):
                text += t.text
            case .toolUse(let t):
                // Encode the input dict back to JSON string
                if let data = try? JSONSerialization.data(withJSONObject: t.input),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    toolCalls.append(AIToolCall(id: t.id, name: t.name, arguments: jsonStr))
                }
            }
        }

        return AIResponse(content: text, toolCalls: toolCalls)
    }
}

// MARK: - Claude API types

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]?
    let system: String?
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeTool: Encodable {
    let name: String
    let description: String
    let input_schema: AIToolDefinition.ParameterSchema
}

private struct ClaudeResponse: Decodable {
    let id: String
    let content: [ContentBlock]
    let stop_reason: String?

    enum ContentBlock: Decodable {
        case text(TextBlock)
        case toolUse(ToolUseBlock)

        struct TextBlock: Decodable {
            let text: String
        }

        struct ToolUseBlock: Decodable {
            let id: String
            let name: String
            let input: [String: Any]

            enum CodingKeys: String, CodingKey {
                case id, name, input
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                // Decode input as raw dictionary
                let inputData = try container.decode(AnyCodable.self, forKey: .input)
                input = inputData.value as? [String: Any] ?? [:]
            }
        }

        enum CodingKeys: String, CodingKey {
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "text":
                self = .text(try TextBlock(from: decoder))
            case "tool_use":
                self = .toolUse(try ToolUseBlock(from: decoder))
            default:
                self = .text(TextBlock(text: ""))
            }
        }
    }
}

// MARK: - AnyCodable helper

private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }
}

// MARK: - ClaudeError

public enum ClaudeError: Error, LocalizedError {
    case invalidResponse
    case apiError(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Claude API"
        case .apiError(let status, let body): "Claude API error (\(status)): \(body)"
        }
    }
}
