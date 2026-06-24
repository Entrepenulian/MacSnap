import AppKit
import ApplicationServices

/// Finds the on-screen frame of a browser's *page content* (the AXWebArea) via the
/// Accessibility API, so "Screenshot site" can capture just the rendered page — no
/// tabs, address bar, or window chrome. Works across Safari/Chrome/Arc/Edge/etc.
enum WebCapture {
    static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.canary",
        "company.thebrowser.Browser",            // Arc
        "com.microsoft.edgemac", "com.brave.Browser",
        "org.mozilla.firefox", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
    ]

    /// Accessibility permission is required to read another app's UI. Optionally prompt.
    static func axTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// A running browser, preferring the active one.
    static func frontmostBrowser() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && browserIDs.contains($0.bundleIdentifier ?? "")
        }
        return apps.first(where: { $0.isActive }) ?? apps.first
    }

    /// The VISIBLE page-content frame (top-left origin, screen points) of `app`'s focused
    /// window — the web area clipped to the window, so it's the viewport you actually see
    /// (no tabs/toolbar), not the full scrollable document (which runs off-screen).
    static func webAreaFrame(of app: NSRunningApplication) -> CGRect? {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = focusedWindow(axApp), let web = findWebArea(window),
              let webFrame = frame(of: web) else { return nil }
        if let winFrame = frame(of: window) {
            let visible = webFrame.intersection(winFrame)
            if visible.width > 1, visible.height > 1 { return visible.integral }
        }
        return webFrame.integral
    }

    /// The VISIBLE page viewport — chrome excluded — with NO Accessibility PROMPT.
    /// Uses the precise AX web-area only if Accessibility is *already* granted (read-only
    /// check, never prompts); otherwise computes it from the window bounds (permission-free)
    /// minus the browser's top chrome. So "Screenshot site" needs only Screen Recording.
    static func viewportFrame(of app: NSRunningApplication) -> CGRect? {
        if AXIsProcessTrusted(), let ax = webAreaFrame(of: app) { return ax }   // precise, no prompt
        guard let win = frontmostWindowBounds(of: app) else { return nil }
        let inset = chromeInset(for: app.bundleIdentifier ?? "")
        var r = win
        r.origin.y += inset; r.size.height -= inset
        return r.height > 1 ? r.integral : win.integral
    }

    /// The browser's frontmost on-screen window bounds (top-left origin, points).
    /// Reads only window metadata — needs NO permission.
    static func frontmostWindowBounds(of app: NSRunningApplication) -> CGRect? {
        let pid = app.processIdentifier
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var best: CGRect?
        var bestArea: CGFloat = 0
        for w in info {
            guard let owner = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, owner == pid,
                  (w[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let bd = w[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bd as! CFDictionary) else { continue }
            let area = rect.width * rect.height
            if area > bestArea { bestArea = area; best = rect }
        }
        return best
    }

    /// Top browser-chrome height (points) to skip when Accessibility isn't available.
    private static func chromeInset(for bundleID: String) -> CGFloat {
        // Erring on the SMALL side: a sliver of toolbar is far better than clipping the page
        // (the user was explicit — "it can't clip at the top"). Granting Accessibility makes
        // this exact regardless of toolbar config.
        switch bundleID {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview": return 90   // measured: tab bar + address bar
        case "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac": return 72
        case "company.thebrowser.Browser": return 44   // Arc
        default: return 56
        }
    }

    // MARK: traversal

    private static func focusedWindow(_ axApp: AXUIElement) -> AXUIElement? {
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let w = element(axApp, attr) { return w }
        }
        return elements(axApp, kAXWindowsAttribute)?.first
    }

    private static func findWebArea(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
        if depth > 16 { return nil }
        if role(el) == "AXWebArea" { return el }
        for child in elements(el, kAXChildrenAttribute) ?? [] {
            if let found = findWebArea(child, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func frame(of el: AXUIElement) -> CGRect? {
        guard let posVal = raw(el, kAXPositionAttribute), let sizeVal = raw(el, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: point, size: size)
    }

    // MARK: AX helpers

    private static func role(_ el: AXUIElement) -> String? { raw(el, kAXRoleAttribute) as? String }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = raw(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement]? {
        raw(el, attr) as? [AXUIElement]
    }

    private static func raw(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &ref) == .success else { return nil }
        return ref
    }
}
