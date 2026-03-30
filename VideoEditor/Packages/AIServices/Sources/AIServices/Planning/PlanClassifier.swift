import Foundation

/// Code-based classifier: does this user request need a plan before execution?
/// Zero-cost — no LLM call. Runs before IntentRouter.
public struct PlanClassifier: Sendable {

    public init() {}

    /// Returns true if the request should generate an editing plan for user approval.
    public func needsPlan(_ message: String, hasClipsOnTimeline: Bool, hasPendingPlan: Bool) -> Bool {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Never plan when user is responding to an existing plan
        if hasPendingPlan {
            return false
        }

        // Skip plan for approvals/rejections (these execute or cancel a plan)
        if isApproval(lower) || isRejection(lower) {
            return false
        }

        // Skip plan for simple single-tool operations
        if isSimpleProperty(lower) || isSimpleStructural(lower) {
            return false
        }

        // Skip plan for questions and greetings
        if isQuestion(lower) || isGreeting(lower) {
            return false
        }

        // Require plan for explicit plan requests
        if isExplicitPlanRequest(lower) {
            return true
        }

        // Require plan for multi-step workflow keywords
        if isMultiStepRequest(lower) {
            return true
        }

        // Require plan for open-ended requests when timeline has content
        if hasClipsOnTimeline && isOpenEnded(lower) {
            return true
        }

        // Default: no plan (simple or unclear requests execute directly)
        return false
    }

    /// Check if the message is approving a plan.
    public func isApproval(_ message: String) -> Bool {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let approvals = [
            "yes", "go", "approve", "do it", "start", "execute",
            "looks good", "go ahead", "proceed", "ok", "okay",
            "yep", "yeah", "sure", "let's go", "run it",
        ]
        return approvals.contains(lower) || approvals.contains(where: { lower.hasPrefix($0) })
    }

    /// Check if the message is rejecting a plan.
    public func isRejection(_ message: String) -> Bool {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let rejections = [
            "no", "cancel", "stop", "nevermind", "never mind",
            "don't", "nah", "nope", "forget it",
        ]
        return rejections.contains(lower) || rejections.contains(where: { lower.hasPrefix($0) })
    }
}

// MARK: - Private Classification

extension PlanClassifier {

    private func isSimpleProperty(_ text: String) -> Bool {
        let keywords = [
            "volume", "opacity", "speed", "mute", "unmute",
            "louder", "quieter", "softer", "faster", "slower",
            "fade", "transparent", "lock", "unlock",
        ]
        return keywords.contains(where: { text.contains($0) }) && !isMultiStepRequest(text)
    }

    private func isSimpleStructural(_ text: String) -> Bool {
        let keywords = [
            "split at", "trim to", "delete clip", "delete this",
            "add marker", "rename", "duplicate",
        ]
        return keywords.contains(where: { text.contains($0) })
    }

    private func isQuestion(_ text: String) -> Bool {
        let keywords = [
            "how many", "what tracks", "what clips", "how long",
            "what is", "show me", "tell me about",
        ]
        return keywords.contains(where: { text.contains($0) })
    }

    private func isGreeting(_ text: String) -> Bool {
        let greetings = ["hello", "hi", "hey", "thanks", "thank you"]
        return greetings.contains(text) || greetings.contains(where: { text.hasPrefix($0) })
    }

    private func isExplicitPlanRequest(_ text: String) -> Bool {
        let keywords = [
            "what should", "how would you", "make a plan",
            "what's the plan", "plan this", "what do you suggest",
            "how should we", "what steps",
        ]
        return keywords.contains(where: { text.contains($0) })
    }

    private func isMultiStepRequest(_ text: String) -> Bool {
        let keywords = [
            "edit this", "clean up", "create episode", "extract episode",
            "make this into", "auto cut", "auto-cut", "autocut",
            "podcast", "viral", "highlights", "optimize",
            "remove fillers", "remove silence", "tighten",
            "polish", "professional", "broadcast",
            "full edit", "complete edit", "production",
        ]
        return keywords.contains(where: { text.contains($0) })
    }

    private func isOpenEnded(_ text: String) -> Bool {
        let keywords = [
            "edit", "fix", "improve", "make it better",
            "clean", "process", "work on", "handle",
        ]
        return keywords.contains(where: { text.contains($0) })
    }
}
