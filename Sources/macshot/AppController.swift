import AppKit

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = ScreenshotWatcher()
    private let folders = FolderStore()
    private let stack = OverlayStack()
    private weak var thumbnailToggle: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        // Replace the macOS floating thumbnail so macshot owns the moment —
        // but only flip it (and nudge SystemUIServer) if it isn't already off.
        if nativeThumbnailEnabled() { setNativeThumbnail(enabled: false) }
        refreshToggle()

        watcher.onNewScreenshot = { [weak self] url in self?.present(url) }
        watcher.start()
        checkDesktopAccess()
    }

    /// Read the screenshot folder once on launch. On macOS this triggers the
    /// "access your Desktop" permission prompt now, so the first real screenshot
    /// isn't missed while the prompt is up. If it's denied, point the user to Settings.
    private func checkDesktopAccess() {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: watcher.directory.path)
        } catch {
            let alert = NSAlert()
            alert.messageText = "macshot needs access to your Desktop"
            alert.informativeText = "To file screenshots into Desktop folders, allow macshot under System Settings → Privacy & Security → Files and Folders."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher.stop()
    }

    // MARK: menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "camera.viewfinder",
                              accessibilityDescription: "macshot")
            img?.isTemplate = true
            button.image = img
        }

        let menu = NSMenu()
        menu.addItem(header("macshot — watching \(watcher.directoryName)"))
        menu.addItem(.separator())
        menu.addItem(item("Catch the latest screenshot", #selector(testLatest), key: "t"))
        menu.addItem(item("Open screenshot folder", #selector(openFolder)))

        let toggle = item("Use macshot instead of macOS thumbnail", #selector(toggleThumbnail))
        thumbnailToggle = toggle
        menu.addItem(toggle)

        menu.addItem(.separator())
        menu.addItem(item("Quit macshot", #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: actions

    private func present(_ url: URL) {
        stack.add(OverlayController(fileURL: url, store: folders))
    }

    @objc private func testLatest() {
        // Files a copy-free dry run on the newest image in the folder, for testing
        // the panel without taking a fresh screenshot.
        let items = (try? FileManager.default.contentsOfDirectory(
            at: watcher.directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        let newest = items
            .filter { ["png", "jpg", "jpeg", "heic", "tiff"].contains($0.pathExtension.lowercased()) }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
        if let newest { present(newest) }
        else { NSSound.beep() }
    }

    @objc private func openFolder() { NSWorkspace.shared.open(watcher.directory) }

    @objc private func toggleThumbnail() {
        setNativeThumbnail(enabled: !nativeThumbnailEnabled())
        refreshToggle()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: native thumbnail preference

    private func nativeThumbnailEnabled() -> Bool {
        // Unset defaults to true (macOS shows the thumbnail by default).
        guard let v = CFPreferencesCopyAppValue(
            "show-thumbnail" as CFString, "com.apple.screencapture" as CFString) as? NSNumber
        else { return true }
        return v.boolValue
    }

    private func setNativeThumbnail(enabled: Bool) {
        // The screenshot agent re-reads this preference on the next capture, so a
        // synchronized write is enough — no need to restart SystemUIServer (which is
        // the wrong service for this and visibly flickers the menu bar).
        CFPreferencesSetAppValue(
            "show-thumbnail" as CFString, enabled as CFNumber,
            "com.apple.screencapture" as CFString)
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
    }

    private func refreshToggle() {
        // "on" = macshot is in control (native thumbnail disabled).
        thumbnailToggle?.state = nativeThumbnailEnabled() ? .off : .on
    }
}
