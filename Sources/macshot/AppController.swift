import AppKit
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = ScreenshotWatcher()
    private let folders = FolderStore()
    private let pins = PinStore()
    private let stack = OverlayStack()
    private var galleryPanel: GalleryPanel?
    private var lastAutoClose = Date.distantPast
    private let galleryModel = GalleryModel()
    private var macshotEnabled = true   // on = macshot panel shows + native thumbnail off

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()

        // Restore the user's choice. First run: macshot takes over. Otherwise respect
        // whatever they last set, and keep the system pref in sync with it.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "macshotEnabled") == nil {
            macshotEnabled = true
            defaults.set(true, forKey: "macshotEnabled")
        } else {
            macshotEnabled = defaults.bool(forKey: "macshotEnabled")
        }
        setNativeThumbnail(enabled: !macshotEnabled)
        galleryModel.macshotEnabled = macshotEnabled

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
            let img = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "macshot")
            img?.isTemplate = true
            button.image = img
            button.action = #selector(togglePanel)
            button.target = self
        }

        galleryModel.onCatchLatest   = { [weak self] in self?.closePanel(); self?.testLatest() }
        galleryModel.onOpenFolder    = { [weak self] in self?.closePanel(); self?.openFolder() }
        galleryModel.onToggleMacshot = { [weak self] in self?.toggleThumbnail() }
        galleryModel.onQuit          = { NSApp.terminate(nil) }
        galleryModel.onUnpin         = { [weak self] url in self?.pins.unpin(url); self?.refreshGallery() }
        galleryModel.onOpenPin       = { url in NSWorkspace.shared.open(url) }
    }

    // The menu-bar dropdown is a borderless panel pinned flush under the menu bar —
    // no popover arrow, no gap. A normal menu-bar app, not a floating bubble.
    @objc private func togglePanel() {
        if galleryPanel != nil { closePanel(); return }
        if Date().timeIntervalSince(lastAutoClose) < 0.25 { return }   // same click that just closed us
        showPanel()
    }

    private func showPanel() {
        refreshGallery()
        let hosting = NSHostingView(rootView: GalleryView(model: galleryModel))
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 10 || size.height < 10 { size = NSSize(width: 300, height: 360) }

        let panel = GalleryPanel(contentSize: size)
        panel.contentView = hosting

        if let button = statusItem.button, let win = button.window,
           let screen = win.screen ?? NSScreen.main {
            let btn = win.convertToScreen(button.convert(button.bounds, to: nil))
            let margin: CGFloat = 8
            var x = btn.midX - size.width / 2
            x = min(max(x, screen.frame.minX + margin), screen.frame.maxX - size.width - margin)
            let y = screen.visibleFrame.maxY - size.height        // top flush under the menu bar
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }

        panel.alphaValue = 0
        galleryPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        NotificationCenter.default.addObserver(self, selector: #selector(panelResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
    }

    @objc private func panelResignedKey() { closePanel() }

    private func closePanel() {
        guard let panel = galleryPanel else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        panel.orderOut(nil)
        galleryPanel = nil
        lastAutoClose = Date()
    }

    private func refreshGallery() {
        galleryModel.pins = pins.pins()
        galleryModel.macshotEnabled = macshotEnabled
    }

    // MARK: actions

    private func present(_ url: URL) {
        guard macshotEnabled else { return }   // user chose native screenshots — stay out of the way
        stack.add(OverlayController(fileURL: url, store: folders, pins: pins))
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
        macshotEnabled.toggle()
        UserDefaults.standard.set(macshotEnabled, forKey: "macshotEnabled")
        setNativeThumbnail(enabled: !macshotEnabled)
        galleryModel.macshotEnabled = macshotEnabled
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: native thumbnail preference

    private func setNativeThumbnail(enabled: Bool) {
        // The screenshot agent re-reads this preference on the next capture, so a
        // synchronized write is enough — no need to restart SystemUIServer (which is
        // the wrong service for this and visibly flickers the menu bar).
        CFPreferencesSetAppValue(
            "show-thumbnail" as CFString, enabled as CFNumber,
            "com.apple.screencapture" as CFString)
        CFPreferencesAppSynchronize("com.apple.screencapture" as CFString)
    }
}

/// The menu-bar gallery dropdown: a transparent, borderless panel that sits flush
/// under the menu bar (no popover arrow). The rounded glass comes from the SwiftUI
/// content; the panel just hosts it and casts the shadow.
final class GalleryPanel: NSPanel {
    init(contentSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
}
