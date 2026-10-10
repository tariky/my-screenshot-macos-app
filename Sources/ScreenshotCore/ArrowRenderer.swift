import CoreGraphics
import Foundation
import ImageIO

public enum ArrowRenderer {
    /// #FF3B30
    public static let color = CGColor(srgbRed: 1, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 1)

    /// Arrowhead length / width as multiples of the line width.
    private static let headLengthFactor: CGFloat = 4.5
    private static let headWidthFactor: CGFloat = 3.5
    /// The head never takes more than this fraction of the arrow's length.
    private static let maxHeadFraction: CGFloat = 0.6

    /// Stroke width in image pixels: max(3, 0.5% of the shorter side).
    public static func lineWidth(for imageSize: CGSize) -> CGFloat {
        let shorter = min(imageSize.width, imageSize.height)
        guard shorter.isFinite else { return 3 }
        return max(3, 0.005 * shorter)
    }

    /// Draws one arrow (shaft + filled triangular head + soft dark shadow) into `context`.
    /// `start`/`end` are in the context's current user space; the caller is responsible for
    /// any flipping so that the points land where intended. Used by both `render` and the
    /// editor's live canvas so they look identical.
    public static func draw(_ arrow: Arrow, lineWidth: CGFloat, in context: CGContext) {
        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001, lineWidth > 0, length.isFinite, lineWidth.isFinite else { return }

        // Unit direction (start → end) and its perpendicular.
        let ux = dx / length, uy = dy / length
        let px = -uy, py = ux

        // Head size, clamped for very short arrows (keeps proportions).
        var headLength = headLengthFactor * lineWidth
        var headWidth = headWidthFactor * lineWidth
        let maxHead = length * maxHeadFraction
        if headLength > maxHead {
            let k = maxHead / headLength
            headLength *= k
            headWidth *= k
        }

        let tip = arrow.end
        let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
        let halfW = headWidth / 2
        let left = CGPoint(x: base.x + px * halfW, y: base.y + py * halfW)
        let right = CGPoint(x: base.x - px * halfW, y: base.y - py * halfW)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -lineWidth * 0.3),
            blur: lineWidth,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        context.setStrokeColor(color)
        context.setFillColor(color)

        // Shaft: stops at the head base so the tip stays sharp; the round cap there is
        // hidden inside the head.
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: arrow.start)
        context.addLine(to: base)
        context.strokePath()

        // Head.
        context.beginPath()
        context.move(to: tip)
        context.addLine(to: left)
        context.addLine(to: right)
        context.closePath()
        context.fillPath()

        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// Returns a new image with the same pixel size as `base`, with `arrows` drawn on top.
    /// Arrow points are top-left-origin image pixels (see `Arrow`).
    public static func render(base: CGImage, arrows: [Arrow]) -> CGImage {
        let w = base.width, h = base.height
        guard w > 0, h > 0,
              let space = outputColorSpace(for: base),
              let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return base }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.interpolationQuality = .none
        ctx.draw(base, in: rect)

        if !arrows.isEmpty {
            ctx.interpolationQuality = .high
            ctx.setShouldAntialias(true)
            // Flip so top-left-origin arrow points land where intended.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            let lw = lineWidth(for: CGSize(width: w, height: h))
            for arrow in arrows {
                draw(arrow, lineWidth: lw, in: ctx)
            }
        }

        return ctx.makeImage() ?? base
    }

    /// Keep the screenshot's own RGB space (usually Display P3) so wide-gamut colours survive;
    /// fall back to sRGB for anything a bitmap context can't use as-is.
    private static func outputColorSpace(for image: CGImage) -> CGColorSpace? {
        if let space = image.colorSpace, space.model == .rgb, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
    }

    /// PNG encoding of `image`.
    public static func pngData(_ image: CGImage) -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return Data() }
        return data as Data
    }
}
