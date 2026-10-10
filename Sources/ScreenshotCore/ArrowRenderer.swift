import CoreGraphics
import Foundation
import ImageIO

public enum ArrowRenderer {
    /// #FF3B30
    public static let color = CGColor(srgbRed: 1, green: 0x3B / 255.0, blue: 0x30 / 255.0, alpha: 1)

    // Skitch-style geometry, as multiples of the neck width (the `lineWidth` argument).
    /// Tip → barb corners, along the arrow.
    private static let headLengthFactor: CGFloat = 3.0
    /// Full width across the barb corners.
    private static let headWidthFactor: CGFloat = 3.2
    /// Where the shaft joins the head, as a fraction of head length back from the tip.
    /// Less than 1 so the head's back edge notches in toward the tip (swept-back barbs).
    private static let neckFraction: CGFloat = 0.8
    /// Shaft width at the (rounded) tail.
    private static let tailWidthFactor: CGFloat = 0.35
    /// The head never takes more than this fraction of the arrow's length.
    private static let maxHeadFraction: CGFloat = 0.6

    /// Shaft width at the neck (right behind the head), in image pixels:
    /// clamp(0.35% of (width + height), 10, 40) — ≈17 px on a typical Retina capture.
    public static func lineWidth(for imageSize: CGSize) -> CGFloat {
        let sum = imageSize.width + imageSize.height
        guard sum.isFinite else { return 10 }
        return min(40, max(10, 0.0035 * sum))
    }

    /// Draws one Skitch-style arrow into `context`: a single filled shape — a shaft tapering from
    /// a rounded tail to `lineWidth` at the neck, then a bold head with swept-back barbs and its
    /// tip at `end` — with a white outline and a soft dark shadow.
    /// `start`/`end` are in the context's current user space; the caller is responsible for
    /// any flipping so that the points land where intended. Used by both `render` and the
    /// editor's live canvas so they look identical.
    public static func draw(_ arrow: Arrow, lineWidth: CGFloat, in context: CGContext) {
        guard let path = arrowPath(arrow, lineWidth: lineWidth) else { return }
        let neckWidth = path.neckWidth

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShadow(
            offset: CGSize(width: 0, height: -neckWidth * 0.2),
            blur: neckWidth * 0.8,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4))
        // One layer so outline + fill cast a single shadow.
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        context.setLineJoin(.round)
        context.setLineCap(.round)

        // Outline: stroke at twice the visible width first; the fill then covers the inner half.
        context.addPath(path.shape)
        context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.setLineWidth(2 * max(1.5, 0.14 * neckWidth))
        context.strokePath()

        context.addPath(path.shape)
        context.setFillColor(color)
        context.fillPath()

        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The closed outline of one arrow plus its effective neck width (smaller than `lineWidth`
    /// for short arrows, whose head is scaled down). Nil for zero-length / invalid input.
    private static func arrowPath(_ arrow: Arrow, lineWidth: CGFloat) -> (shape: CGPath, neckWidth: CGFloat)? {
        let dx = arrow.end.x - arrow.start.x
        let dy = arrow.end.y - arrow.start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001, lineWidth > 0, length.isFinite, lineWidth.isFinite else { return nil }

        // Unit direction (start → end) and its perpendicular.
        let ux = dx / length, uy = dy / length
        let px = -uy, py = ux

        // Short arrows: shrink the whole cross-section so the head stays ≤ 60% of the length.
        let scale = min(1, length * maxHeadFraction / (headLengthFactor * lineWidth))
        let neckWidth = lineWidth * scale
        let headLength = headLengthFactor * neckWidth
        let halfHead = headWidthFactor * neckWidth / 2
        let halfNeck = neckWidth / 2
        let tailRadius = tailWidthFactor * neckWidth / 2

        let tip = arrow.end
        let start = arrow.start
        // Point `back` units behind the tip along the axis, `side` units off it.
        func atHead(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - ux * back + px * side, y: tip.y - uy * back + py * side)
        }
        func atTail(back: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: start.x - ux * back + px * side, y: start.y - uy * back + py * side)
        }

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: atHead(back: headLength, side: halfHead))                 // left barb
        path.addLine(to: atHead(back: headLength * neckFraction, side: halfNeck))  // left neck
        path.addLine(to: atTail(back: 0, side: tailRadius))                        // left tail
        // Semicircular tail cap (built from tangent arcs, so it works in flipped spaces too).
        path.addArc(tangent1End: atTail(back: tailRadius, side: tailRadius),
                    tangent2End: atTail(back: tailRadius, side: 0), radius: tailRadius)
        path.addArc(tangent1End: atTail(back: tailRadius, side: -tailRadius),
                    tangent2End: atTail(back: 0, side: -tailRadius), radius: tailRadius)
        path.addLine(to: atHead(back: headLength * neckFraction, side: -halfNeck)) // right neck
        path.addLine(to: atHead(back: headLength, side: -halfHead))                // right barb
        path.closeSubpath()
        return (path, neckWidth)
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
