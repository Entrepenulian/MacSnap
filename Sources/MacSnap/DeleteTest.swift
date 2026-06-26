import AppKit

/// End-to-end check of the trash button + dissolve: builds the real panel, fires the
/// same closure the button fires, plays the dissolve, and confirms the screenshot left
/// its folder and is now in the Trash. Uses a temp file (never the user's Desktop).
///   swift run macsnap --deletetest
final class DeleteTestController: NSObject, NSApplicationDelegate {
    private var stack: OverlayStack?
    private var controller: OverlayController?
    private var dir: URL!
    private var fileURL: URL!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("macsnap-del-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("Screenshot delete-test.png")
        writePNG(sampleImage(), to: fileURL)
        let existedBefore = fm.fileExists(atPath: fileURL.path)

        let stack = OverlayStack()
        self.stack = stack
        let c = OverlayController(fileURL: fileURL, store: FolderStore())
        self.controller = c
        stack.add(c)   // build + show the real panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.controller?.testInvokeDelete()        // === clicking the trash button ===
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self?.report(existedBefore) }
        }
    }

    private func report(_ existedBefore: Bool) {
        let fm = FileManager.default
        let goneFromFolder = !fm.fileExists(atPath: fileURL.path)
        var inTrash = false
        if let trash = try? fm.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            for item in (try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
            where item.lastPathComponent.hasPrefix("Screenshot delete-test") {
                inTrash = true
                try? fm.removeItem(at: item)
            }
        }
        try? fm.removeItem(at: dir)
        print("file existed before click:        \(existedBefore)")
        print("file gone from its folder after:  \(goneFromFolder)")
        print("file moved to Trash:              \(inTrash)")
        print(goneFromFolder && inTrash ? "\nDELETE OK" : "\nDELETE FAILED")
        NSApp.terminate(nil)
    }

    private func writePNG(_ img: NSImage, to url: URL) {
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: url) }
    }

    private func sampleImage() -> NSImage {
        let size = NSSize(width: 1400, height: 900)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(white: 0.97, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: size.height - 120, width: size.width, height: 120).fill()
        NSColor(white: 0.85, alpha: 1).setFill()
        for i in 0..<6 {
            NSRect(x: 80, y: size.height - 250 - CGFloat(i) * 90, width: size.width - 160, height: 50).fill()
        }
        img.unlockFocus()
        return img
    }
}
