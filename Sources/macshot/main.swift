import AppKit

// macshot — a menu-bar agent that catches new screenshots and lets you file
// them into a Desktop folder from a floating glass panel.
//
// Runs as an .accessory app: no Dock icon, just a menu-bar item + the overlay.

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--dragtest") {
    // Verify the dragged item carries an image type that other apps will accept.
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("macshot-drag-\(UUID().uuidString)")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("Screenshot drag.png")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", url.path]
    try? p.run(); p.waitUntilExit()
    let provider = NSItemProvider(contentsOf: url)
    let types = provider?.registeredTypeIdentifiers ?? []
    let droppable = types.contains { $0.contains("png") || $0.contains("image") }

    // The panel must NOT be draggable as a window — so an incomplete drag snaps back.
    _ = NSApplication.shared
    let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let staysPut = !panel.isMovableByWindowBackground

    print("drag item created:          \(provider != nil)")
    print("registered types:           \(types)")
    print("droppable into image apps:  \(droppable)")
    print("panel stays put (snaps back): \(staysPut)")
    print(droppable && staysPut ? "\nDRAG OK" : "\nDRAG ISSUE")
    try? fm.removeItem(at: dir)
    exit(droppable && staysPut ? 0 : 1)
}

if let i = CommandLine.arguments.firstIndex(of: "--render") {
    _ = NSApplication.shared
    let out = (i + 1 < CommandLine.arguments.count) ? CommandLine.arguments[i + 1] : "/tmp/macshot.png"
    MainActor.assumeIsolated { RenderTest.run(out) }
    exit(0)
}

let app = NSApplication.shared
let delegate: NSApplicationDelegate
if CommandLine.arguments.contains("--demo") { delegate = DemoController() }
else if CommandLine.arguments.contains("--latencytest") { delegate = LatencyController() }
else if CommandLine.arguments.contains("--deletetest") { delegate = DeleteTestController() }
else if CommandLine.arguments.contains("--pintest") { delegate = PinTestController() }
else { delegate = AppController() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
