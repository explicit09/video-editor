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
        model: String = "claude-sonnet-4-6",
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120  // 2 minutes for tool-use responses
        self.session = URLSession(configuration: config)
    }

    /// Convenience: load API key from environment.
    public static func fromEnvironment(model: String = "claude-sonnet-4-6") -> ClaudeProvider? {
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

        // Build messages using JSONSerialization for full control over structure
        var jsonMessages: [[String: Any]] = []
        var pendingToolResults: [[String: Any]] = []

        for msg in messages {
            if msg.isToolResult, let toolID = msg.toolResultID {
                pendingToolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolID,
                    "content": msg.content,
                ])
            } else {
                // Flush pending tool results as one user message
                if !pendingToolResults.isEmpty {
                    jsonMessages.append(["role": "user", "content": pendingToolResults])
                    pendingToolResults = []
                }

                if msg.role == "assistant", let rawJSON = msg.toolResultID, rawJSON.hasPrefix("["),
                   let data = rawJSON.data(using: .utf8),
                   let contentArray = try? JSONSerialization.jsonObject(with: data) {
                    // Assistant message with raw tool_use content blocks
                    jsonMessages.append(["role": "assistant", "content": contentArray])
                } else {
                    jsonMessages.append(["role": msg.role, "content": msg.content])
                }
            }
        }
        if !pendingToolResults.isEmpty {
            jsonMessages.append(["role": "user", "content": pendingToolResults])
        }

        // Build tools array with prompt caching on the last tool
        var jsonTools: [[String: Any]]?
        if !tools.isEmpty {
            jsonTools = tools.enumerated().map { (index, tool) -> [String: Any] in
                let schemaData = try? JSONEncoder().encode(tool.parameters)
                let schema = schemaData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
                var toolDict: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": schema,
                ]
                // Cache the entire tools block via the last tool
                if index == tools.count - 1 {
                    toolDict["cache_control"] = ["type": "ephemeral"]
                }
                return toolDict
            }
        }

        // System prompt as cacheable content block
        let systemContent: [[String: Any]] = [
            [
                "type": "text",
                "text": systemPrompt,
                "cache_control": ["type": "ephemeral"],
            ]
        ]

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": jsonMessages,
            "system": systemContent,
        ]
        if let jsonTools { body["tools"] = jsonTools }

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        request.httpBody = bodyData

        // Debug: log request size
        let sizeKB = bodyData.count / 1024
        print("[Claude] Request size: \(sizeKB)KB, messages: \(jsonMessages.count)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("[Claude] Error \(httpResponse.statusCode): \(errorBody.prefix(500))")
            throw ClaudeError.apiError(status: httpResponse.statusCode, body: errorBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return convertResponse(claudeResponse, rawData: data)
    }

    // MARK: - System prompt

    private var systemPrompt: String {
        """
        You are an AI editing assistant inside a video editor. You can see the full editor state \
        and execute operations using tools.

        Principles:
        - Complete the user's intent fully. If a task requires multiple steps, chain all \
        necessary tool calls in one response. Never stop halfway.
        - Use the editor context to make decisions. Check what assets, tracks, and clips \
        already exist before acting. Don't create duplicates or use placeholder values \
        when real data is available.
        - Be brief. Act first, explain only what's necessary.
        - Only confirm before destructive operations (bulk deletes, removing tracks with content).

        Rules:
        - Reference assets, tracks, and clips by their UUIDs from the editor context.
        - Times are in seconds.
        - Use real asset durations from the context, not arbitrary values.
        - Place new clips at the end of existing content on a track unless told otherwise.

        Split + Delete workflow:
        - After split_clip, read the tool result carefully — it tells you the IDs and \
        time ranges of both resulting clips.
        - Use those exact IDs when calling delete_clips. Never guess clip IDs after a split.
        - When removing a section: split at the section END first, then split at the \
        section START, then delete only the middle clip (the section to remove).
        - The delete_clips tool result tells you how many clips remain. Verify this is correct.
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

    private func convertResponse(_ response: ClaudeResponse, rawData: Data) -> AIResponse {
        var text = ""
        var toolCalls: [AIToolCall] = []

        for block in response.content {
            switch block {
            case .text(let t):
                text += t.text
            case .toolUse(let t):
                if let data = try? JSONSerialization.data(withJSONObject: t.input),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    toolCalls.append(AIToolCall(id: t.id, name: t.name, arguments: jsonStr))
                }
            }
        }

        // Extract raw content array for multi-turn (needed to echo assistant message back)
        var rawContentJSON: String?
        if !toolCalls.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
           let contentArray = json["content"],
           let contentData = try? JSONSerialization.data(withJSONObject: contentArray) {
            rawContentJSON = String(data: contentData, encoding: .utf8)
        }

        return AIResponse(content: text, toolCalls: toolCalls, stopReason: response.stop_reason, rawContentJSON: rawContentJSON)
    }
}

// MARK: - Claude API types

private struct ClaudeRequestPayload: Encodable {
    let model: String
    let max_tokens: Int
    let messages: [ClaudeMessagePayload]
    let tools: [ClaudeTool]?
    let system: String?
}

private struct ClaudeMessagePayload: Encodable {
    let role: String
    let content: ClaudeContent

    enum ClaudeContent: Encodable {
        case text(String)
        case blocks([ClaudeContentBlock])
        case rawJSON(String) // Pre-encoded JSON for assistant tool_use messages

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let s):
                try container.encode(s)
            case .blocks(let blocks):
                try container.encode(blocks)
            case .rawJSON(let json):
                // Write pre-encoded JSON directly into the output
                if let data = json.data(using: .utf8) {
                    let wrapper = RawJSON(data: data)
                    try container.encode(wrapper)
                } else {
                    try container.encode(json)
                }
            }
        }
    }

    enum ClaudeContentBlock: Encodable {
        case toolResult(ClaudeToolResult)

        func encode(to encoder: Encoder) throws {
            switch self {
            case .toolResult(let result):
                try result.encode(to: encoder)
            }
        }
    }
}

private struct ClaudeToolResult: Encodable {
    let type = "tool_result"
    let tool_use_id: String
    let content: String
}

/// Wrapper that writes pre-encoded JSON data directly.
private struct RawJSON: Encodable {
    let data: Data

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        // This is a hack but necessary — we need to inject pre-encoded JSON
        // Foundation's JSONEncoder doesn't support raw JSON injection natively
        try container.encode(Array(data))
    }
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
