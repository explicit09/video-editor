import Foundation
import EditorCore

// MARK: - AIProvider (provider-agnostic)

public protocol AIProvider: Sendable {
    var name: String { get }
    func complete(messages: [AIMessage], tools: [AIToolDefinition]) async throws -> AIResponse
}

// MARK: - AITool (tools resolve to EditorIntents)

public protocol AITool: Sendable {
    var definition: AIToolDefinition { get }
    func resolve(arguments: [String: Any], context: EditingContext) async throws -> [EditorIntent]
}

// MARK: - AnalysisTask

public protocol AnalysisTask: Sendable {
    var type: AnalysisType { get }
    var costTier: CostTier { get }
    func run(asset: MediaAsset, progress: @escaping @Sendable (Double) -> Void) async throws -> AnalysisResult
}

// MARK: - Supporting types

public enum AnalysisType: String, Codable, Sendable {
    case transcription
    case shotDetection
    case silenceDetection
    case speakerDiarization
    case sceneDescription
    case loudnessProfile
}

public enum CostTier: String, Codable, Sendable {
    case local
    case frequent
    case expensive
}

public struct AIMessage: Codable, Sendable {
    public let role: String
    public let content: String
    /// For tool result messages — the tool use ID this is responding to
    public let toolResultID: String?
    /// Whether this is a tool result message
    public let isToolResult: Bool

    public init(role: String, content: String, toolResultID: String? = nil, isToolResult: Bool = false) {
        self.role = role
        self.content = content
        self.toolResultID = toolResultID
        self.isToolResult = isToolResult
    }
}

public struct AIResponse: Codable, Sendable {
    public let content: String
    public let toolCalls: [AIToolCall]
    public let stopReason: String?

    public init(content: String, toolCalls: [AIToolCall] = [], stopReason: String? = nil) {
        self.content = content
        self.toolCalls = toolCalls
        self.stopReason = stopReason
    }
}

// AIToolDefinition is now in Tools/AIToolRegistry.swift with full JSON schema support

public struct AIToolCall: Codable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String = UUID().uuidString, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// Parse arguments JSON string into dictionary.
    public func parsedArguments() -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return dict
    }
}

public struct AnalysisResult: Sendable {
    public let type: AnalysisType
    public let analysis: MediaAnalysis

    public init(type: AnalysisType, analysis: MediaAnalysis) {
        self.type = type
        self.analysis = analysis
    }
}
