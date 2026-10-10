import CoreGraphics
import Foundation

public enum ArrowRenderer {
    /// #FF3B30
    public static let color = CGColor(srgbRed: 1, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 1)

    /// Stroke width in image pixels: max(3, 0.5% of the shorter side).
    public static func lineWidth(for imageSize: CGSize) -> CGFloat {
        fatalError("TODO")
    }

    /// Draws one arrow (shaft + filled triangular head + soft dark shadow) into `context`.
    /// `start`/`end` are in the context's current user space; the caller is responsible for
    /// any flipping so that the points land where intended. Used by both `render` and the
    /// editor's live canvas so they look identical.
    public static func draw(_ arrow: Arrow, lineWidth: CGFloat, in context: CGContext) {
        fatalError("TODO")
    }

    /// Returns a new image with the same pixel size as `base`, with `arrows` drawn on top.
    /// Arrow points are top-left-origin image pixels (see `Arrow`).
    public static func render(base: CGImage, arrows: [Arrow]) -> CGImage {
        fatalError("TODO")
    }

    /// PNG encoding of `image`.
    public static func pngData(_ image: CGImage) -> Data {
        fatalError("TODO")
    }
}
