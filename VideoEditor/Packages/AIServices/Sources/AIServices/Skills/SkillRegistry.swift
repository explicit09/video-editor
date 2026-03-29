import Foundation

/// A loaded editing skill with its metadata and content.
public struct EditingSkill: Sendable {
    public let name: String
    public let description: String
    public let keywords: [String]
    public let tools: [String]
    public let model: String
    public let contextLevel: String
    public let content: String  // Full markdown content (after frontmatter)

    /// Check if a user message matches this skill's keywords.
    public func matches(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return keywords.contains { lowered.contains($0) }
    }

    /// Score how well a message matches (number of keyword hits).
    public func matchScore(_ message: String) -> Int {
        let lowered = message.lowercased()
        return keywords.filter { lowered.contains($0) }.count
    }
}

/// Loads and matches editing skills from SKILL.md files.
/// Skills provide domain knowledge for specific editing workflows.
public final class SkillRegistry: @unchecked Sendable {

    private var skills: [EditingSkill] = []

    public init() {}

    /// Load skills from a directory containing skill subdirectories.
    /// Expected structure: skillsDir/skill-name/SKILL.md
    public func loadSkills(from skillsDir: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return }

        for dir in contents {
            let skillFile = dir.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillFile.path),
                  let raw = try? String(contentsOf: skillFile, encoding: .utf8) else { continue }

            if let skill = parseSkillFile(raw) {
                skills.append(skill)
            }
        }
    }

    /// Find the best matching skill for a user message.
    /// Returns nil if no skill matches.
    public func match(_ message: String) -> EditingSkill? {
        let scored = skills.compactMap { skill -> (EditingSkill, Int)? in
            let score = skill.matchScore(message)
            return score > 0 ? (skill, score) : nil
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }

    /// All loaded skill names for display.
    public var availableSkills: [String] {
        skills.map(\.name)
    }

    /// Get a skill by name.
    public func skill(named name: String) -> EditingSkill? {
        skills.first { $0.name == name }
    }

    // MARK: - Parsing

    /// Parse a SKILL.md file into an EditingSkill.
    private func parseSkillFile(_ raw: String) -> EditingSkill? {
        // Split frontmatter from content
        guard raw.hasPrefix("---") else { return nil }
        let parts = raw.dropFirst(3).split(separator: "---", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let frontmatter = String(parts[0])
        let content = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse YAML frontmatter (simple key: value parsing)
        var meta: [String: String] = [:]
        var listValues: [String: [String]] = [:]
        var currentListKey: String?

        for line in frontmatter.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                if let key = currentListKey {
                    let value = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    listValues[key, default: []].append(value)
                }
            } else if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if value.isEmpty {
                    currentListKey = key
                } else {
                    meta[key] = value
                    currentListKey = nil
                }
            }
        }

        guard let name = meta["name"] else { return nil }

        let keywords = (meta["keywords"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        return EditingSkill(
            name: name,
            description: meta["description"] ?? "",
            keywords: keywords,
            tools: listValues["tools"] ?? [],
            model: meta["model"] ?? "standard",
            contextLevel: meta["context-level"] ?? "standard",
            content: content
        )
    }
}
