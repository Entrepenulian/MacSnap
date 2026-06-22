import WebKit
import AppKit

/// Renders a web page in an offscreen WKWebView and snapshots the FULL page to a PNG.
/// This needs NO Screen Recording and NO Accessibility permission — it draws the page
/// itself rather than capturing the screen — and it grabs the whole scrollable page,
/// not just the visible viewport. Perfect for "screenshot my localhost site."
final class WebShot: NSObject, WKNavigationDelegate {
    private static var live: WebShot?      // retain across the async load
    private let dest: URL
    private let width: CGFloat
    private var webView: WKWebView!
    private var done: ((Bool) -> Void)?
    private var finished = false

    static func capture(url: URL, to dest: URL, width: CGFloat = 1440, completion: @escaping (Bool) -> Void) {
        let shot = WebShot(dest: dest, width: width)
        live = shot
        shot.run(url: url) { ok in completion(ok); live = nil }
    }

    private init(dest: URL, width: CGFloat) { self.dest = dest; self.width = width; super.init() }

    private func run(url: URL, _ completion: @escaping (Bool) -> Void) {
        done = completion
        let cfg = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900), configuration: cfg)
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.finish(false) }   // safety timeout
    }

    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        // Let it lay out, measure the full document height, resize, then snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self else { return }
            wv.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight)") { result, _ in
                let raw = (result as? NSNumber)?.doubleValue ?? 900
                let h = CGFloat(min(max(raw, 200), 16000))
                wv.frame = NSRect(x: 0, y: 0, width: self.width, height: h)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    let snap = WKSnapshotConfiguration()
                    snap.rect = wv.bounds
                    snap.afterScreenUpdates = true
                    wv.takeSnapshot(with: snap) { image, _ in
                        guard let image, let png = image.pngData() else { self.finish(false); return }
                        try? png.write(to: self.dest)
                        self.finish(true)
                    }
                }
            }
        }
    }

    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError error: Error) { finish(false) }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) { finish(false) }

    private func finish(_ ok: Bool) {
        guard !finished else { return }; finished = true
        done?(ok)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
