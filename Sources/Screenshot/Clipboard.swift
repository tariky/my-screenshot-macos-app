import AppKit
import ScreenshotCore

enum Clipboard {
    /// Replaces the general pasteboard contents with `image` as PNG.
    static func write(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(ArrowRenderer.pngData(image), forType: .png)
    }
}
