import Foundation

// MARK: - Editing Plan

/// A structured plan of editing steps generated before execution.
/// Shown to the user for approval, then executed step by step.
public struct EditingPlan: Codable, Sendable {
    public let summary: String
    public let steps: [PlanStep]
    public var status: Status

    public init(summary: String, steps: [PlanStep], status: Status = .proposed) {
        self.summary = summary
        self.steps = steps
        self.status = status
    }

    public enum Status: String, Codable, Sendable {
        case proposed   // Shown to user, awaiting approval
        case approved   // User said yes
        case executing  // Currently running
        case completed  // All steps done
        case cancelled  // User rejected
    }

    /// Format the plan as readable text for the chatbot.
    public var displayText: String {
        var lines: [String] = []
        lines.append("**\(summary)**\n")
        for step in steps {
            let model = step.modelTier == .fast ? "⚡" : "🧠"
            lines.append("\(step.id). \(model) **\(step.description)**")
            if !step.tools.isEmpty {
                lines.append("   Tools: \(step.tools.joined(separator: ", "))")
            }
        }
        lines.append("\nSay **go** to start, or tell me what to change.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Plan Step

public struct PlanStep: Codable, Sendable {
    public let id: Int
    public let description: String
    public let tools: [String]
    public let modelTier: ModelTier
    public let category: StepCategory

    public init(id: Int, description: String, tools: [String], modelTier: ModelTier, category: StepCategory) {
        self.id = id
        self.description = description
        self.tools = tools
        self.modelTier = modelTier
        self.category = category
    }

    public enum StepCategory: String, Codable, Sendable {
        case analyze   // Read state, transcript, energy — no mutations
        case edit      // Structural changes (split, trim, delete, move)
        case property  // Property changes (volume, speed, opacity)
        case verify    // Verification (verify_playback, get_state)
        case overlay   // Overlay configuration
    }
}

// MARK: - Model Tier

public enum ModelTier: String, Codable, Sendable {
    case fast = "claude-haiku-4-5-20251001"
    case standard = "claude-sonnet-4-6"
}
