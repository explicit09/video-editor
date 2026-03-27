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

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIToolDefinition: Codable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public struct AIResponse: Codable, Sendable {
    public let content: String
    public let toolCalls: [AIToolCall]

    public init(content: String, toolCalls: [AIToolCall] = []) {
        self.content = content
        self.toolCalls = toolCalls
    }
}

public struct AIToolCall: Codable, Sendable {
    public let name: String
    public let arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
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
