import AppKit

struct Folder: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    var count: Int
    var isRoot: Bool = false      // the Desktop itself (the always-present baseline)
}

/// macshot does NOT enumerate the whole Desktop. It only knows about the Desktop
/// itself plus the folders you've created through it (persisted in UserDefaults).
final class FolderStore {
    let desktop: URL
    private let defaultsKey: String
    private let recentsKey: String

    init(root: URL? = nil, defaultsKey: String = "macshotFolders") {
        self.desktop = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        self.defaultsKey = defaultsKey
        self.recentsKey = defaultsKey + "Recents"
    }

    /// The Desktop root — the one target that's always available by default.
    func desktopFolder() -> Folder {
        Folder(id: desktop.path, name: "Desktop", url: desktop, count: 0, isRoot: true)
    }

    /// Folders you've created through macshot, pruned to those that still exist.
    func savedFolders() -> [Folder] {
        let fm = FileManager.default
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        var seen = Set<String>()
        var folders: [Folder] = []
        for p in paths where !seen.contains(p) {
            seen.insert(p)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = URL(fileURLWithPath: p)
            let count = (try? fm.contentsOfDirectory(atPath: p).count) ?? 0
            folders.append(Folder(id: p, name: url.lastPathComponent, url: url, count: count))
        }
        let kept = folders.map { $0.url.path }
        if kept.count != paths.count { UserDefaults.standard.set(kept, forKey: defaultsKey) }
        return folders
    }

    /// Remember a folder (most-recent first) so it shows up next time.
    func remember(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(paths, forKey: defaultsKey)
    }

    /// Record a save target (including the Desktop root) for the quick-save pills.
    func rememberSave(_ folder: Folder) {
        var paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        paths.removeAll { $0 == folder.url.path }
        paths.insert(folder.url.path, at: 0)
        if paths.count > 12 { paths = Array(paths.prefix(12)) }
        UserDefaults.standard.set(paths, forKey: recentsKey)
    }

    /// The folders you most recently saved into (newest first), for the quick-save pills.
    func recentFolders(max: Int = 3) -> [Folder] {
        let fm = FileManager.default
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        var out: [Folder] = []
        for p in paths {
            if p == desktop.path {
                out.append(desktopFolder())
            } else {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
                let url = URL(fileURLWithPath: p)
                let count = (try? fm.contentsOfDirectory(atPath: p).count) ?? 0
                out.append(Folder(id: p, name: url.lastPathComponent, url: url, count: count))
            }
            if out.count >= max { break }
        }
        return out
    }

    @discardableResult
    func createFolder(named name: String) throws -> URL {
        let url = desktop.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        remember(url)
        return url
    }

    /// Move `file` into `folder`, renaming to `baseName` (keeping the extension).
    /// Resolves name collisions by appending " 2", " 3", …
    @discardableResult
    func move(_ file: URL, into folder: URL, baseName: String?) throws -> URL {
        let fm = FileManager.default
        let ext = file.pathExtension
        let trimmed = baseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = trimmed.isEmpty ? file.deletingPathExtension().lastPathComponent : trimmed

        var dest = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
        return dest
    }
}
