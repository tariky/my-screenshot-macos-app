import CoreGraphics
import CoreText
import Foundation

extension ArrowRenderer {
    /// Default text size for an image, in image pixels: 2.0 × lineWidth(for:) (≈44 px ≈ 22 pt on a Retina capture).
    public static func fontSize(for imageSize: CGSize) -> CGFloat {
        2 * lineWidth(for: imageSize)
    }

    /// The bold system font used for labels (CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)).
    /// Exposed so the editor's live NSTextField can use the identical font.
    public static func labelFont(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// Size of the laid-out text (multi-line: split on "\n", each line its own CTLine,
    /// line height = ascent+descent+leading of the font), INCLUDING the outline margin,
    /// so origin + size covers everything drawn except the shadow.
    public static func textSize(_ label: TextLabel) -> CGSize {
        guard let layout = TextLayout(label) else { return .zero }
        return layout.size
    }

    /// Draws `label` into `context`, whose user space is TOP-LEFT origin, y down
    /// (a flipped NSView context, or render()'s flipped bitmap context): a red fill with a white
    /// outline outside the glyphs and one soft shadow for the whole label, matching the arrows.
    /// Empty / whitespace-only text draws nothing.
    public static func draw(_ label: TextLabel, in context: CGContext) {
        guard !label.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let layout = TextLayout(label) else { return }
        let fs = label.fontSize

        // Glyph outlines in top-left (y-down) user space. Glyphs without outlines (colour emoji)
        // are collected and drawn as bitmaps after the vector text.
        let shape = CGMutablePath()
        var bitmapRuns: [(font: CTFont, glyphs: [CGGlyph], positions: [CGPoint], baseline: CGPoint)] = []
        for (i, line) in layout.lines.enumerated() {
            let baseline = layout.baseline(ofLine: i)
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                let font = runFont(run) ?? layout.font
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                var missing: [Int] = []
                for g in 0..<count {
                    // CoreText is y-up: flip each glyph about its baseline.
                    var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                              tx: baseline.x + positions[g].x, ty: baseline.y - positions[g].y)
                    if let p = CTFontCreatePathForGlyph(font, glyphs[g], &t) {
                        shape.addPath(p)
                    } else if glyphs[g] != 0 {
                        missing.append(g)
                    }
                }
                if !missing.isEmpty {
                    bitmapRuns.append((font, missing.map { glyphs[$0] }, missing.map { positions[$0] }, baseline))
                }
            }
        }
        guard !shape.isEmpty || !bitmapRuns.isEmpty else { return }

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShadow(
            offset: CGSize(width: 0, height: -fs * 0.08),
            blur: fs * 0.35,
            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.4))
        // One layer so outline + fill cast a single shadow.
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        if !shape.isEmpty {
            // Outline: stroke at twice the visible width first; the fill then covers the inner half.
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.addPath(shape)
            context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.setLineWidth(2 * layout.margin)
            context.strokePath()

            context.addPath(shape)
            context.setFillColor(color)
            context.fillPath()
        }

        for run in bitmapRuns {
            context.saveGState()
            context.translateBy(x: run.baseline.x, y: run.baseline.y)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            CTFontDrawGlyphs(run.font, run.glyphs, run.positions, run.glyphs.count, context)
            context.restoreGState()
        }

        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func runFont(_ run: CTRun) -> CTFont? {
        let attrs = CTRunGetAttributes(run) as NSDictionary
        guard let value = attrs[kCTFontAttributeName as String] else { return nil }
        return (value as! CTFont)
    }
}

/// Line layout shared by `textSize` and `draw`, in top-left (y-down) image pixels.
private struct TextLayout {
    let font: CTFont
    let lines: [CTLine]
    let origin: CGPoint
    /// Visible white outline width; the layout box is padded by this on every side.
    let margin: CGFloat
    let ascent: CGFloat
    let lineHeight: CGFloat
    let size: CGSize

    init?(_ label: TextLabel) {
        let fs = label.fontSize
        guard fs > 0, fs.isFinite, label.origin.x.isFinite, label.origin.y.isFinite else { return nil }
        font = ArrowRenderer.labelFont(size: fs)
        origin = label.origin
        // Stroke width max(2, 0.16 × fontSize); half of it shows outside the fill.
        margin = max(2, 0.16 * fs) / 2
        ascent = CTFontGetAscent(font)
        lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)

        let attrs = [kCTFontAttributeName: font] as CFDictionary
        lines = label.text.split(separator: "\n", omittingEmptySubsequences: false).map { sub in
            let str = String(sub).replacingOccurrences(of: "\r", with: "")
            return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, str as CFString, attrs))
        }

        var width: CGFloat = 0
        for line in lines {
            let typographic = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            width = max(width, typographic, ink.isNull ? 0 : ink.maxX)
        }
        size = CGSize(width: width + 2 * margin,
                      height: CGFloat(max(1, lines.count)) * lineHeight + 2 * margin)
    }

    /// Left end of line `i`'s baseline: line 1's ascent top sits at origin.y + margin.
    func baseline(ofLine i: Int) -> CGPoint {
        CGPoint(x: origin.x + margin, y: origin.y + margin + ascent + CGFloat(i) * lineHeight)
    }
}
