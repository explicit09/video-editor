import Foundation

/// Tracks all projects and the currently active one.
/// Persisted as `projects.json` in the VideoEditor app support directory.
struct ProjectIndex: Codable {
    var activeProject: String
    var projects: [ProjectEntry]

    struct ProjectEntry: Codable {
        var name: String
        var created: Date
        var modified: Date
    }
}

/// Manages the project index file and project directory operations.
@MainActor
final class ProjectIndexManager {
    private let baseURL: URL
    private let indexURL: URL
    private(set) var index: ProjectIndex

    /// Base directory: ~/Library/Containers/.../Application Support/VideoEditor/
    init(baseURL: URL) {
        self.baseURL = baseURL
        self.indexURL = baseURL.appendingPathComponent("projects.json")

        // Load existing index or create default
        if let data = try? Data(contentsOf: baseURL.appendingPathComponent("projects.json")),
           let loaded = try? JSONDecoder.iso8601.decode(ProjectIndex.self, from: data) {
            self.index = loaded
        } else {
            self.index = ProjectIndex(activeProject: "Untitled", projects: [])
        }
    }

    // MARK: - Queries

    var activeProjectName: String { index.activeProject }

    func projectExists(_ name: String) -> Bool {
        index.projects.contains { $0.name == name }
    }

    func bundleURL(for name: String) -> URL {
        baseURL.appendingPathComponent("\(name).veditor")
    }

    var activeBundleURL: URL {
        bundleURL(for: index.activeProject)
    }

    // MARK: - Mutations

    func addProject(name: String) {
        guard !projectExists(name) else { return }
        let entry = ProjectIndex.ProjectEntry(
            name: name,
            created: Date(),
            modified: Date()
        )
        index.projects.append(entry)
        save()
    }

    func setActive(_ name: String) {
        index.activeProject = name
        save()
    }

    func markModified(_ name: String) {
        guard let idx = index.projects.firstIndex(where: { $0.name == name }) else { return }
        index.projects[idx].modified = Date()
        save()
    }

    func removeProject(_ name: String) {
        index.projects.removeAll { $0.name == name }
        save()
    }

    func renameProject(from oldName: String, to newName: String) {
        guard let idx = index.projects.firstIndex(where: { $0.name == oldName }) else { return }
        index.projects[idx].name = newName
        if index.activeProject == oldName {
            index.activeProject = newName
        }
        save()
    }

    /// Migrate legacy DefaultProject.veditor into the index if it exists but isn't tracked.
    func migrateLegacyIfNeeded() {
        let legacyURL = baseURL.appendingPathComponent("DefaultProject.veditor")
        let fm = FileManager.default
        if fm.fileExists(atPath: legacyURL.path) && !projectExists("DefaultProject") {
            let entry = ProjectIndex.ProjectEntry(
                name: "DefaultProject",
                created: (try? fm.attributesOfItem(atPath: legacyURL.path)[.creationDate] as? Date) ?? Date(),
                modified: Date()
            )
            index.projects.append(entry)
            if index.projects.count == 1 || index.activeProject == "Untitled" {
                index.activeProject = "DefaultProject"
            }
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

// MARK: - Helpers

extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Sanitize a project name for use as a directory name.
func sanitizedProjectName(_ name: String) -> String {
    var sanitized = name
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: "\\", with: "-")
        .replacingOccurrences(of: ":", with: "-")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // No leading dots
    while sanitized.hasPrefix(".") {
        sanitized = String(sanitized.dropFirst())
    }

    // Fallback
    if sanitized.isEmpty {
        sanitized = "Untitled"
    }

    return sanitized
}
