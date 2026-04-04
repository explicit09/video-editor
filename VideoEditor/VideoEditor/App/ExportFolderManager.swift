import AppKit
import UniformTypeIdentifiers

/// Manages security-scoped bookmarks for persistent folder access.
/// Handles both export destination and media source folders so the app
/// can read/write outside its sandbox without copying files.
@MainActor
final class ExportFolderManager {
    private static let exportBookmarkKey = "defaultExportFolderBookmark"
    private static let mediaBookmarksKey = "mediaSourceFolderBookmarks"

    // MARK: - Export Folder

    /// Resolved default export folder, or nil if not set.
    static var defaultFolder: URL? {
        resolveBookmark(key: exportBookmarkKey)
    }

    /// Prompt user to pick a default export folder via NSOpenPanel.
    @discardableResult
    static func pickDefaultFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose default export folder"
        panel.prompt = "Set as Default"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        saveBookmark(for: url, key: exportBookmarkKey)
        return url
    }

    /// Show NSSavePanel for a one-off export location.
    static func pickSaveLocation(filename: String, fileExtension: String = "mp4") -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(filename).\(fileExtension)"
        if let type = UTType(filenameExtension: fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.canCreateDirectories = true
        if let defaultDir = defaultFolder {
            panel.directoryURL = defaultDir
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Build an export URL using the default folder if set, otherwise tmp.
    static func exportURL(filename: String, ext: String = "mp4") -> URL {
        if let folder = defaultFolder {
            _ = folder.startAccessingSecurityScopedResource()
            return folder.appendingPathComponent("\(filename).\(ext)")
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("\(filename).\(ext)")
    }

    /// Stop accessing the security-scoped resource for the default folder.
    static func stopAccessing() {
        defaultFolder?.stopAccessingSecurityScopedResource()
    }

    /// Clear the saved default folder.
    static func clearDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: exportBookmarkKey)
    }

    // MARK: - Media Source Folders

    /// All bookmarked media source folders the app can read from without copying.
    static var mediaFolders: [URL] {
        guard let dataArray = UserDefaults.standard.array(forKey: mediaBookmarksKey) as? [Data] else { return [] }
        return dataArray.compactMap { data in
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                      relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
            if isStale { return nil }
            return url
        }
    }

    /// Prompt user to pick a media source folder. Bookmarks it for persistent access.
    @discardableResult
    static func addMediaFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a media source folder (files here won't be copied on import)"
        panel.prompt = "Add Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        addMediaFolderBookmark(for: url)
        return url
    }

    /// Check if a file path is inside a bookmarked media folder.
    /// If so, start accessing the security scope and return true.
    static func canAccessWithoutCopy(path: String) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        for folder in mediaFolders {
            if fileURL.path.hasPrefix(folder.path) {
                return folder.startAccessingSecurityScopedResource()
            }
        }
        return false
    }

    /// Stop accessing all media folder security scopes.
    static func stopAccessingMediaFolders() {
        for folder in mediaFolders {
            folder.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Private

    private static func resolveBookmark(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale { saveBookmark(for: url, key: key) }
        return url
    }

    private static func saveBookmark(for url: URL, key: String) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func addMediaFolderBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil) else { return }
        var existing = UserDefaults.standard.array(forKey: mediaBookmarksKey) as? [Data] ?? []
        // Don't add duplicates
        let resolved = mediaFolders.map(\.path)
        if !resolved.contains(url.path) {
            existing.append(data)
            UserDefaults.standard.set(existing, forKey: mediaBookmarksKey)
        }
    }
}
