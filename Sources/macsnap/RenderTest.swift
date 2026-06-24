import SwiftUI
import AppKit

/// Renders the panel offscreen to PNGs so the look can be verified without the
/// live floating window.  swift run macsnap --render /tmp/macsnap.png
enum RenderTest {
    @MainActor
    static func run(_ outBase: String) {
        RenderEnv.solid = true
        let img = sampleImage(width: 1512, height: 982)
        let folders = [
            Folder(id: "1", name: "Receipts", url: URL(fileURLWithPath: "/"), count: 12),
            Folder(id: "2", name: "Design", url: URL(fileURLWithPath: "/"), count: 48),
            Folder(id: "3", name: "Screenshots", url: URL(fileURLWithPath: "/"), count: 204),
            Folder(id: "4", name: "Invoices", url: URL(fileURLWithPath: "/"), count: 7),
        ]
        let desk = Color(white: 0.07)

        let rest = ShotModel(image: img, fileName: "Screenshot", ext: "png", folders: folders)
        rest.hovering = false
        write(ShotView(model: rest).padding(24).background(desk), outBase, "-rest")

        let hover = ShotModel(image: img, fileName: "Screenshot", ext: "png", folders: folders)
        hover.hovering = true
        write(ShotView(model: hover).padding(24).background(desk), outBase, "-hover")

        let recents = [
            Folder(id: "r1", name: "Creyya Screenshots", url: URL(fileURLWithPath: "/"), count: 0),   // long → truncates
            Folder(id: "r2", name: "Design", url: URL(fileURLWithPath: "/"), count: 0),
            Folder(id: "r3", name: "Invoices", url: URL(fileURLWithPath: "/"), count: 0),
        ]
        let quick = ShotModel(image: img, fileName: "Screenshot", ext: "png", folders: folders, recentFolders: recents)
        quick.mode = .quickSave
        write(ShotView(model: quick).padding(24).background(desk), outBase, "-quicksave")

        let picker = ShotModel(image: img, fileName: "Screenshot 2026-06-20", ext: "png", folders: folders)
        picker.mode = .picker; picker.selection = 0
        write(ShotView(model: picker).padding(24).background(desk), outBase, "-picker")

        // Gallery layout (glass + async thumbnails won't render offscreen, but the
        // structure — gallery on top, settings footer at the bottom — does).
        let gallery = GalleryModel()
        gallery.pins = (0..<5).map { URL(fileURLWithPath: "/tmp/macsnap-render-pin-\($0).png") }
        write(GalleryView(model: gallery).background(Color(white: 0.12)).padding(24).background(desk), outBase, "-gallery")

        print("rendered \(outBase) (-rest / -hover / -picker / -gallery)")
    }

    @MainActor
    private static func write(_ view: some View, _ base: String, _ suffix: String) {
        let path = base.replacingOccurrences(of: ".png", with: "\(suffix).png")
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed: \(path)"); return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func sampleImage(width: Int, height: Int) -> NSImage {
        let size = NSSize(width: width, height: height)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(white: 0.97, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.85, alpha: 1).setFill()
        NSRect(x: 0, y: CGFloat(height) - 130, width: CGFloat(width), height: 130).fill()
        NSColor(white: 0.86, alpha: 1).setFill()
        for i in 0..<6 {
            NSRect(x: 90, y: CGFloat(height) - 260 - CGFloat(i) * 95, width: CGFloat(width) - 180, height: 54).fill()
        }
        img.unlockFocus()
        return img
    }
}
