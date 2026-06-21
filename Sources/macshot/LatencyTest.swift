import AppKit

/// Measures real end-to-end latency: an actual `screencapture` PNG → macshot panel
/// VISIBLE on screen, isolating macOS's own capture/write time from macshot's pipeline.
///   swift run macshot --latencytest
final class LatencyController: NSObject, NSApplicationDelegate {
    private var watcher: ScreenshotWatcher!
    private var stack: OverlayStack!
    private var store: FolderStore!
    private var dir: URL!
    private var t0 = Date()
    private var baselineMs = 0.0
    private var detectMs = -1.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("macshot-lat-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Baseline: macOS's own capture + write time (no macshot involved).
        let b0 = Date()
        capture(to: dir.appendingPathComponent("baseline.png"), wait: true)
        baselineMs = Date().timeIntervalSince(b0) * 1000

        store = FolderStore()
        stack = OverlayStack()
        watcher = ScreenshotWatcher(directory: dir)
        watcher.onNewScreenshot = { [weak self] url in self?.present(url) }
        watcher.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.t0 = Date()
            self.capture(to: self.dir.appendingPathComponent("Screenshot latency.png"), wait: false)
        }

        // Safety timeout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.finish(shown: -1) }
    }

    private func present(_ url: URL) {
        if detectMs < 0 { detectMs = Date().timeIntervalSince(t0) * 1000 }
        let controller = OverlayController(fileURL: url, store: store)
        controller.onShown = { [weak self] in
            guard let self else { return }
            self.finish(shown: Date().timeIntervalSince(self.t0) * 1000)
        }
        stack.add(controller)
    }

    private var done = false
    private func finish(shown visibleMs: Double) {
        guard !done else { return }
        done = true
        try? FileManager.default.removeItem(at: dir)
        print(String(format: "macOS capture+write (baseline):  %.0fms", baselineMs))
        print(String(format: "screenshot → macshot detects:    %.0fms", max(0, detectMs)))
        print(String(format: "screenshot → panel VISIBLE:      %.0fms total", max(0, visibleMs)))
        print(String(format: "macshot pipeline (detect→visible): ~%.0fms", max(0, visibleMs - detectMs)))
        print(visibleMs >= 0 ? "\nLATENCY OK" : "\nLATENCY TIMEOUT")
        NSApp.terminate(nil)
    }

    private func capture(to url: URL, wait: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", url.path]
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}
