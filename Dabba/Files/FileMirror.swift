#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import Foundation

/// Keeps a readable Markdown copy of every session in a folder the user picks
/// once (suggested: Documents/Dabba). One-way: Dabba writes, it doesn't read
/// back. The sandbox only allows this folder because the user chose it, so
/// the choice is remembered as a security-scoped bookmark.
@MainActor
enum FileMirror {
    private static let bookmarkKey = "filesFolderBookmark"
    private static let askedKey = "filesFolderAsked"

    /// The chosen folder, if any.
    static var folder: URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { remember(url) }
        return url
    }

    /// Asks for the folder the first time only.
    static func askOnceIfNeeded() {
        guard folder == nil, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        chooseFolder()
    }

    /// File ▸ Choose Files Folder…
    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Where should Dabba keep your files?"
        panel.message = "Each session is saved here as a plain Markdown file you own."
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        remember(url)
    }

    private static func remember(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope],
                                               includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Writes (or renames and rewrites) the session's file. Silent on failure:
    /// the database copy is always there.
    static func write(_ session: Session) {
        guard let folder, folder.startAccessingSecurityScopedResource() else { return }
        defer { folder.stopAccessingSecurityScopedResource() }
        let name = SessionMarkdown.fileName(for: session)
        let target = folder.appendingPathComponent(name)
        if !session.fileName.isEmpty, session.fileName != name {
            let old = folder.appendingPathComponent(session.fileName)
            if FileManager.default.fileExists(atPath: old.path),
               !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.moveItem(at: old, to: target)
            }
        }
        try? SessionMarkdown.markdown(for: session).write(to: target, atomically: true, encoding: .utf8)
        if session.fileName != name { session.fileName = name }
    }

    /// File ▸ Export… : a one-off copy wherever you choose.
    static func export(_ session: Session) {
        let panel = NSSavePanel()
        panel.title = "Export Session"
        panel.nameFieldStringValue = SessionMarkdown.fileName(for: session)
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SessionMarkdown.markdown(for: session).write(to: url, atomically: true, encoding: .utf8)
    }
}

extension Notification.Name {
    /// File ▸ Export… (⌘⇧E)
    static let exportSession = Notification.Name("dabba.exportSession")
}
#endif
