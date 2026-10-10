import CoreGraphics
import CoreText
import Foundation
import ImageIO
import ScreenshotCore

// MARK: - Tiny assert helper

var passed = 0
var failed = 0

func check(_ condition: @autoclosure () -> Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if condition() {
        passed += 1
        print("PASS  \(name)")
    } else {
        failed += 1
        let d = detail()
        print("FAIL  \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

func approx(_ a: CGFloat, _ b: CGFloat, _ eps: CGFloat = 1e-6) -> Bool { abs(a - b) <= eps }
func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
func approx(_ a: CGPoint, _ b: CGPoint, _ eps: CGFloat = 1e-6) -> Bool {
    approx(a.x, b.x, eps) && approx(a.y, b.y, eps)
}

// MARK: - Image helpers

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let rgbaInfo = CGImageAlphaInfo.premultipliedLast.rawValue

/// Builds an RGBA image from a per-pixel closure; (x, y) with y = 0 at the TOP row.
func makeImage(width: Int, height: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (r, g, b, a) = pixel(x, y)
            let i = (y * width + x) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = a
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: srgb, bitmapInfo: CGBitmapInfo(rawValue: rgbaInfo),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

/// Raw RGBA bytes of `image` exactly as stored by its data provider, tightly packed, row 0 = top.
/// Requires 8-bit RGBA (alpha last) layout.
func rawRGBA(_ image: CGImage) -> [UInt8]? {
    guard image.bitsPerComponent == 8, image.bitsPerPixel == 32,
          let data = image.dataProvider?.data else { return nil }
    let alpha = image.alphaInfo
    guard alpha == .premultipliedLast || alpha == .last || alpha == .noneSkipLast else { return nil }
    let ptr = CFDataGetBytePtr(data)!
    var out = [UInt8](repeating: 0, count: image.width * image.height * 4)
    for y in 0..<image.height {
        for x in 0..<(image.width * 4) {
            out[y * image.width * 4 + x] = ptr[y * image.bytesPerRow + x]
        }
    }
    return out
}

func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * width + x) * 4
    return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]), Int(bytes[i + 3]))
}

func isRedish(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 200 && p.g < 100 && p.b < 100 }
func isWhite(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r == 255 && p.g == 255 && p.b == 255 && p.a == 255 }

// MARK: - Visual sample (`CoreChecks --sample out.png`): Retina-sized striped base + a few arrows.

if let i = CommandLine.arguments.firstIndex(of: "--sample"), i + 1 < CommandLine.arguments.count {
    let w = 2700, h = 1700
    let stripes: [(UInt8, UInt8, UInt8)] = [(255, 255, 255), (48, 48, 52), (230, 120, 100), (40, 90, 200)]
    let base = makeImage(width: w, height: h) { x, _ in let c = stripes[x * stripes.count / w]; return (c.0, c.1, c.2, 255) }
    let arrows = [
        Arrow(start: CGPoint(x: 150, y: 250), end: CGPoint(x: 1250, y: 250)),
        Arrow(start: CGPoint(x: 2550, y: 1550), end: CGPoint(x: 1500, y: 700)),
        Arrow(start: CGPoint(x: 400, y: 1500), end: CGPoint(x: 900, y: 650)),
        Arrow(start: CGPoint(x: 1450, y: 400), end: CGPoint(x: 1450, y: 1300)),
        Arrow(start: CGPoint(x: 2100, y: 250), end: CGPoint(x: 2160, y: 300)),
        Arrow(start: CGPoint(x: 900, y: 1450), end: CGPoint(x: 1050, y: 1450)),
    ]
    let fs = ArrowRenderer.fontSize(for: CGSize(width: w, height: h))
    let labels = [
        TextLabel(origin: CGPoint(x: 120, y: 330), text: "Click here", fontSize: fs),
        TextLabel(origin: CGPoint(x: 120, y: 900), text: "Two lines:\nwhite / dark", fontSize: fs),
        TextLabel(origin: CGPoint(x: 720, y: 330), text: "On dark", fontSize: fs),
        TextLabel(origin: CGPoint(x: 1050, y: 1100), text: "Multi-line\nlabel, gypq", fontSize: fs),
        TextLabel(origin: CGPoint(x: 1400, y: 180), text: "Salmon ✓", fontSize: fs),
        TextLabel(origin: CGPoint(x: 2060, y: 380), text: "Blue 123", fontSize: fs),
        TextLabel(origin: CGPoint(x: 2060, y: 900), text: "Big", fontSize: fs * 2),
        TextLabel(origin: CGPoint(x: 1600, y: 1450), text: "small 18px", fontSize: 18),
        TextLabel(origin: CGPoint(x: 2100, y: 1430), text: "Nice 👍", fontSize: fs),
    ]
    let annotations = arrows.map(Annotation.arrow) + labels.map(Annotation.text)
    let png = ArrowRenderer.pngData(ArrowRenderer.render(base: base, annotations: annotations))
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
    exit(0)
}

// MARK: - lineWidth

check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 200, height: 100)), 12), "lineWidth: small image → 12 (floor)")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 2000, height: 1000)), 13.5), "lineWidth: 2000×1000 → 13.5")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 2700, height: 2200)), 22.05), "lineWidth: 2700×2200 → 22.05")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 20000, height: 20000)), 48), "lineWidth: 20000×20000 → 48 (cap)")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 0, height: 0)), 12), "lineWidth: zero size → 12")

// MARK: - render

do {
    // Noisy base so identity is meaningful.
    let w = 37, h = 23
    let base = makeImage(width: w, height: h) { x, y in
        (UInt8((x * 7 + y * 3) % 256), UInt8((x * 13) % 256), UInt8((y * 29) % 256), 255)
    }
    let out = ArrowRenderer.render(base: base, arrows: [])
    check(out.width == w && out.height == h, "render: zero arrows keeps size", "\(out.width)×\(out.height)")
    let a = rawRGBA(base), b = rawRGBA(out)
    check(b != nil, "render: output is 8-bit RGBA", "bpc=\(out.bitsPerComponent) bpp=\(out.bitsPerPixel) alpha=\(out.alphaInfo.rawValue)")
    check(a != nil && a == b, "render: zero arrows → byte-identical pixels")
}

do {
    let w = 200, h = 100
    let white = makeImage(width: w, height: h) { _, _ in (255, 255, 255, 255) }
    let out = ArrowRenderer.render(base: white, arrows: [Arrow(start: CGPoint(x: 20, y: 50), end: CGPoint(x: 180, y: 50))])
    check(out.width == w && out.height == h, "render: with arrow keeps size", "\(out.width)×\(out.height)")
    if let px = rawRGBA(out) {
        let mid = pixel(px, width: w, x: 100, y: 50)
        check(isRedish(mid), "render: shaft midpoint is red", "\(mid)")
        let corner = pixel(px, width: w, x: 2, y: 2)
        check(isWhite(corner), "render: far corner unchanged", "\(corner)")
        let farCorner = pixel(px, width: w, x: w - 2, y: h - 2)
        check(isWhite(farCorner), "render: opposite corner unchanged", "\(farCorner)")
        // Pixel just before the tip, inside the head, should be red (sharp filled head).
        let nearTip = pixel(px, width: w, x: 176, y: 50)
        check(isRedish(nearTip), "render: head is filled near tip", "\(nearTip)")
        // Head is wider than the shaft: a point off-axis just behind the tip is red.
        let lw = ArrowRenderer.lineWidth(for: CGSize(width: w, height: h))
        let headSide = pixel(px, width: w, x: 160, y: 50 + Int(lw * 0.8))
        check(isRedish(headSide), "render: head wider than shaft", "\(headSide) lw=\(lw)")
        // Beyond the tip stays (essentially) untouched.
        let beyond = pixel(px, width: w, x: 190, y: 50)
        check(beyond.r > 200 && beyond.g > 200 && beyond.b > 200, "render: beyond tip not red", "\(beyond)")
    } else {
        check(false, "render: readable output bytes")
    }
}

do {
    // Top-left convention: arrow near y = 10 must color rows near the TOP of the buffer.
    let w = 100, h = 100
    let white = makeImage(width: w, height: h) { _, _ in (255, 255, 255, 255) }
    let out = ArrowRenderer.render(base: white, arrows: [Arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 10))])
    if let px = rawRGBA(out) {
        let top = pixel(px, width: w, x: 40, y: 10)
        check(isRedish(top), "render: top-left origin — row 10 from top is red", "\(top)")
        let bottom = pixel(px, width: w, x: 40, y: h - 1 - 10)
        check(isWhite(bottom), "render: top-left origin — row 10 from bottom untouched", "\(bottom)")
    } else {
        check(false, "render: readable output bytes (top-left)")
    }
}

do {
    // Very short and degenerate arrows must not crash.
    let white = makeImage(width: 50, height: 50) { _, _ in (255, 255, 255, 255) }
    let out = ArrowRenderer.render(base: white, arrows: [
        Arrow(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 12, y: 11)),
        Arrow(start: CGPoint(x: 30, y: 30), end: CGPoint(x: 30, y: 30)),
    ])
    check(out.width == 50 && out.height == 50, "render: short/degenerate arrows don't crash")
}

// MARK: - Arrow shape (draw into a flipped, top-left-origin context like the canvas does)

/// Draws `arrows` with `draw(_:lineWidth:in:)` over a solid `fill`; returns RGBA bytes, row 0 = top.
func drawArrows(width: Int, height: Int, fill: (CGFloat, CGFloat, CGFloat), lineWidth: CGFloat, _ arrows: [Arrow]) -> [UInt8] {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: srgb, bitmapInfo: rgbaInfo)!
    ctx.setFillColor(CGColor(srgbRed: fill.0, green: fill.1, blue: fill.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    for a in arrows { ArrowRenderer.draw(a, lineWidth: lineWidth, in: ctx) }
    let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: ptr, count: width * height * 4))
}

/// Number of red pixels in column `x`.
func redSpan(_ px: [UInt8], width: Int, height: Int, x: Int) -> Int {
    (0..<height).filter { isRedish(pixel(px, width: width, x: x, y: $0)) }.count
}

func isWhiteish(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r > 200 && p.g > 200 && p.b > 200 }
func isDark(_ p: (r: Int, g: Int, b: Int, a: Int)) -> Bool { p.r < 40 && p.g < 40 && p.b < 40 }

do {
    // Horizontal arrow, neck width 20 → head length 52 (barbs at x=488), neck at x≈498,
    // head width 56, tail width 11 at x=60.
    let w = 600, h = 300, lw: CGFloat = 20
    let arrow = Arrow(start: CGPoint(x: 60, y: 150), end: CGPoint(x: 540, y: 150))
    let px = drawArrows(width: w, height: h, fill: (0, 0, 0), lineWidth: lw, [arrow])

    let mid = pixel(px, width: w, x: 300, y: 150)
    check(isRedish(mid), "shape: shaft midpoint is red", "\(mid)")
    check(isRedish(pixel(px, width: w, x: 532, y: 150)), "shape: head filled near tip", "\(pixel(px, width: w, x: 532, y: 150))")

    // Shaft half-width at x=470 ≈ 9.7; outline ≈ 2.8 beyond that.
    let above = pixel(px, width: w, x: 470, y: 150 - 12), below = pixel(px, width: w, x: 470, y: 150 + 11)
    check(isWhiteish(above) && isWhiteish(below), "shape: white outline just outside shaft near neck", "above=\(above) below=\(below)")
    let outside = pixel(px, width: w, x: 470, y: 150 - 20)
    check(isDark(outside), "shape: well outside shaft is untouched base", "\(outside)")

    let neckSpan = redSpan(px, width: w, height: h, x: 470)
    let headSpan = redSpan(px, width: w, height: h, x: 500)
    let tailSpan = redSpan(px, width: w, height: h, x: 80)
    check(neckSpan >= 17 && neckSpan <= 22, "shape: shaft ≈ lineWidth near neck", "neck=\(neckSpan)")
    check(headSpan > 2 * neckSpan, "shape: head much wider than neck", "head=\(headSpan) neck=\(neckSpan)")
    check(tailSpan > 0 && tailSpan < neckSpan * 3 / 4, "shape: tail tapers (narrower than neck)", "tail=\(tailSpan) neck=\(neckSpan)")

    // Swept-back barbs: behind the neck, the barb tips are red but the notch between barb and
    // shaft is not.
    let barb = pixel(px, width: w, x: 491, y: 150 - 25)
    let notch = pixel(px, width: w, x: 491, y: 150 - 16)
    check(isRedish(barb), "shape: barb extends behind the neck", "\(barb)")
    check(!isRedish(notch), "shape: concave notch between barb and shaft", "\(notch)")

    // Nothing past the tip beyond the outline (shadow is invisible on black).
    let beyond = (0..<h).map { pixel(px, width: w, x: 546, y: $0) }
    check(beyond.allSatisfy(isDark), "shape: nothing drawn beyond the tip", "\(beyond.first { !isDark($0) }.map { "\($0)" } ?? "")")
    // Nothing behind the rounded tail either.
    check((0..<h).allSatisfy { isDark(pixel(px, width: w, x: 48, y: $0)) }, "shape: nothing drawn behind the tail")
}

do {
    // On a blue base the outline must read white, distinct from the base.
    let w = 600, h = 300
    let px = drawArrows(width: w, height: h, fill: (0, 0.3, 1), lineWidth: 20,
                        [Arrow(start: CGPoint(x: 60, y: 150), end: CGPoint(x: 540, y: 150))])
    let edge = pixel(px, width: w, x: 470, y: 150 - 12)
    check(isWhiteish(edge), "shape: outline white on blue base", "\(edge)")
}

do {
    // Diagonal arrow: shaft midpoint red, a point well off-axis untouched.
    let w = 400, h = 400
    let px = drawArrows(width: w, height: h, fill: (0, 0, 0), lineWidth: 16,
                        [Arrow(start: CGPoint(x: 350, y: 350), end: CGPoint(x: 50, y: 50))])
    check(isRedish(pixel(px, width: w, x: 200, y: 200)), "shape: diagonal shaft midpoint red", "\(pixel(px, width: w, x: 200, y: 200))")
    check(isRedish(pixel(px, width: w, x: 60, y: 60)), "shape: diagonal head near tip red", "\(pixel(px, width: w, x: 60, y: 60))")
    check(isDark(pixel(px, width: w, x: 300, y: 100)), "shape: diagonal off-axis untouched")
    check(isDark(pixel(px, width: w, x: 40, y: 40)), "shape: diagonal beyond tip untouched", "\(pixel(px, width: w, x: 40, y: 40))")
}

do {
    // Short arrow (length 40 < 1.6 × head length 60): head shrinks to ≤ 60% of the length.
    let w = 200, h = 200
    let px = drawArrows(width: w, height: h, fill: (0, 0, 0), lineWidth: 20,
                        [Arrow(start: CGPoint(x: 80, y: 100), end: CGPoint(x: 120, y: 100))])
    check(isRedish(pixel(px, width: w, x: 115, y: 100)), "short: head near tip red")
    check(isRedish(pixel(px, width: w, x: 86, y: 100)), "short: shaft still visible near tail")
    let tallest = (0..<w).map { redSpan(px, width: w, height: h, x: $0) }.max() ?? 0
    check(tallest > 15 && tallest <= 28, "short: head scaled down (width ≤ 0.6 × 40 × 3.2/3)", "tallest=\(tallest)")
    check((0..<h).allSatisfy { isDark(pixel(px, width: w, x: 126, y: $0)) }, "short: nothing beyond the tip")
}

do {
    // Zero-length arrow draws nothing at all.
    let empty = drawArrows(width: 60, height: 60, fill: (0, 0, 0), lineWidth: 20, [])
    let zero = drawArrows(width: 60, height: 60, fill: (0, 0, 0), lineWidth: 20,
                          [Arrow(start: CGPoint(x: 30, y: 30), end: CGPoint(x: 30, y: 30))])
    check(empty == zero, "shape: zero-length arrow draws nothing")
}

// MARK: - Text labels

check(approx(ArrowRenderer.fontSize(for: CGSize(width: 200, height: 100)), 24), "fontSize: small image → 2 × 12 = 24")
check(approx(ArrowRenderer.fontSize(for: CGSize(width: 2700, height: 2200)), 44.1), "fontSize: 2700×2200 → 2 × 22.05",
      "\(ArrowRenderer.fontSize(for: CGSize(width: 2700, height: 2200)))")
check(approx(ArrowRenderer.fontSize(for: CGSize(width: 20000, height: 20000)), 96), "fontSize: huge image → 2 × 48 = 96")

do {
    let f = ArrowRenderer.labelFont(size: 37)
    check(approx(CTFontGetSize(f), 37), "labelFont: requested size", "\(CTFontGetSize(f))")
    check(CTFontGetSymbolicTraits(f).contains(.traitBold), "labelFont: bold")
}

do {
    let l = TextLabel(origin: CGPoint(x: 3, y: 4), text: "Hi", fontSize: 20)
    check(l.origin == CGPoint(x: 3, y: 4) && l.text == "Hi" && l.fontSize == 20, "TextLabel: init stores fields")
    check(Annotation.text(l) == .text(l) && Annotation.text(l) != .arrow(Arrow(start: .zero, end: .zero)), "Annotation: Equatable")
}

do {
    let fs: CGFloat = 40
    let font = ArrowRenderer.labelFont(size: fs)
    let lineH = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    func size(_ t: String) -> CGSize { ArrowRenderer.textSize(TextLabel(origin: .zero, text: t, fontSize: fs)) }
    let one = size("Hello"), longer = size("Hello, world"), two = size("Hello\nworld"), empty = size("")
    check(longer.width > one.width && approx(longer.height, one.height), "textSize: grows with text length", "\(one) \(longer)")
    check(two.height > 1.7 * one.height && two.height <= 2 * one.height + 0.001, "textSize: two lines ≈ 2× one line", "\(one) \(two)")
    check(one.height > lineH, "textSize: height includes outline margin", "h=\(one.height) line=\(lineH)")
    let attr = CFAttributedStringCreate(nil, "Hello" as CFString,
                                        [kCTFontAttributeName: font] as CFDictionary)!
    let raw = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attr), nil, nil, nil))
    check(one.width > raw, "textSize: width includes outline margin", "w=\(one.width) raw=\(raw)")
    check(empty.width < fs * 0.5, "textSize: empty text has (near) zero width", "\(empty)")
    let wide = size("ab\nabcdefgh\nabc")
    check(approx(wide.width, size("abcdefgh").width, 0.001), "textSize: width = widest line", "\(wide) vs \(size("abcdefgh"))")
    check(size("x").width == ArrowRenderer.textSize(TextLabel(origin: CGPoint(x: 500, y: 9), text: "x", fontSize: fs)).width,
          "textSize: independent of origin")
}

/// Draws `labels` with `draw(_:in:)` into a flipped (top-left origin) context over `fill`; RGBA bytes, row 0 = top.
func drawLabels(width: Int, height: Int, fill: (CGFloat, CGFloat, CGFloat), _ labels: [TextLabel]) -> [UInt8] {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: srgb, bitmapInfo: rgbaInfo)!
    ctx.setFillColor(CGColor(srgbRed: fill.0, green: fill.1, blue: fill.2, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    for l in labels { ArrowRenderer.draw(l, in: ctx) }
    let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: ptr, count: width * height * 4))
}

do {
    // Black base: red fill + white outline inside origin+textSize; nothing outside it.
    let w = 400, h = 300
    let label = TextLabel(origin: CGPoint(x: 30, y: 12), text: "Text", fontSize: 60)
    let sz = ArrowRenderer.textSize(label)
    let px = drawLabels(width: w, height: h, fill: (0, 0, 0), [label])
    let box = CGRect(origin: label.origin, size: sz).insetBy(dx: -2, dy: -2)
    var red = 0, white = 0, outside = 0, firstOutside = ""
    for y in 0..<h { for x in 0..<w {
        let p = pixel(px, width: w, x: x, y: y)
        let inBox = box.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
        if isRedish(p) && inBox { red += 1 }
        if isWhiteish(p) && inBox { white += 1 }
        if !inBox && !isDark(p) { outside += 1; if firstOutside.isEmpty { firstOutside = "(\(x),\(y)) \(p)" } }
    } }
    check(red > 300, "text: red glyph pixels inside the box", "red=\(red)")
    check(white > 100, "text: white outline pixels", "white=\(white)")
    check(outside == 0, "text: nothing drawn outside origin+textSize", "outside=\(outside) first=\(firstOutside) size=\(sz)")
    // Top-left convention: small origin.y → ink near the TOP rows only.
    let inkRows = (0..<h).filter { y in (0..<w).contains { !isDark(pixel(px, width: w, x: $0, y: y)) } }
    check((inkRows.min() ?? 999) < 30 && (inkRows.max() ?? 999) < h / 2, "text: top-left origin — drawn at the top",
          "rows \(inkRows.min() ?? -1)…\(inkRows.max() ?? -1)")
    // Left edge sits at origin.x + small margin.
    let inkCols = (0..<w).filter { x in (0..<h).contains { !isDark(pixel(px, width: w, x: x, y: $0)) } }
    check((inkCols.min() ?? 0) >= 28 && (inkCols.min() ?? 999) <= 40, "text: left edge near origin.x", "col \(inkCols.min() ?? -1)")
}

do {
    // Not upside-down: in a "T" the bar (row with most red) is in the upper part of the glyph.
    let w = 200, h = 200
    let px = drawLabels(width: w, height: h, fill: (0, 0, 0), [TextLabel(origin: CGPoint(x: 20, y: 20), text: "T", fontSize: 120)])
    let counts = (0..<h).map { y in (0..<w).filter { isRedish(pixel(px, width: w, x: $0, y: y)) }.count }
    let rows = counts.indices.filter { counts[$0] > 0 }
    let top = rows.first ?? 0, bottom = rows.last ?? 0
    let bar = counts.indices.max { counts[$0] < counts[$1] } ?? 0
    check(bottom - top > 50, "text T: glyph has height", "\(top)…\(bottom)")
    check(bar < top + (bottom - top) / 3, "text T: bar at the top (not upside-down)", "bar=\(bar) glyph \(top)…\(bottom)")
}

do {
    // On a white base the outline merges with the base, the fill is red; shadow stays near the text.
    let w = 400, h = 200
    let label = TextLabel(origin: CGPoint(x: 20, y: 20), text: "Shadow", fontSize: 50)
    let sz = ArrowRenderer.textSize(label)
    let px = drawLabels(width: w, height: h, fill: (1, 1, 1), [label])
    let blur = 0.35 * label.fontSize
    let allowed = CGRect(x: label.origin.x - blur, y: label.origin.y - blur,
                         width: sz.width + 2 * blur, height: sz.height + 2.5 * blur)
    var far = 0, shadowed = 0
    for y in 0..<h { for x in 0..<w {
        let p = pixel(px, width: w, x: x, y: y)
        if !allowed.contains(CGPoint(x: x, y: y)) && !isWhite(p) { far += 1 }
        if p.r < 250 && !isRedish(p) { shadowed += 1 }
    } }
    check(far == 0, "text: shadow stays within ~1 blur of the box", "far=\(far)")
    check(shadowed > 50, "text: soft shadow visible on white", "shadowed=\(shadowed)")
}

do {
    // Multi-line: second line below the first.
    let w = 300, h = 300, fs: CGFloat = 50
    let one = drawLabels(width: w, height: h, fill: (0, 0, 0), [TextLabel(origin: CGPoint(x: 10, y: 10), text: "AB", fontSize: fs)])
    let two = drawLabels(width: w, height: h, fill: (0, 0, 0), [TextLabel(origin: CGPoint(x: 10, y: 10), text: "AB\nCD", fontSize: fs)])
    func lastRedRow(_ px: [UInt8]) -> Int { (0..<h).last { y in (0..<w).contains { isRedish(pixel(px, width: w, x: $0, y: y)) } } ?? 0 }
    let lineH = ArrowRenderer.textSize(TextLabel(origin: .zero, text: "AB\nCD", fontSize: fs)).height
        - ArrowRenderer.textSize(TextLabel(origin: .zero, text: "AB", fontSize: fs)).height
    let d = CGFloat(lastRedRow(two) - lastRedRow(one))
    check(abs(d - lineH) <= 3, "text: second line one line-height lower", "Δ=\(d) lineH=\(lineH)")
}

do {
    let blank = drawLabels(width: 120, height: 80, fill: (0, 0, 0), [])
    let ws = drawLabels(width: 120, height: 80, fill: (0, 0, 0), [
        TextLabel(origin: CGPoint(x: 10, y: 10), text: "", fontSize: 30),
        TextLabel(origin: CGPoint(x: 10, y: 10), text: "   ", fontSize: 30),
        TextLabel(origin: CGPoint(x: 10, y: 10), text: " \n\t\n ", fontSize: 30),
        TextLabel(origin: CGPoint(x: 10, y: 10), text: "X", fontSize: 0),
        TextLabel(origin: CGPoint(x: 10, y: 10), text: "X", fontSize: .nan),
    ])
    check(blank == ws, "text: empty / whitespace-only / zero-size draws nothing")
}

do {
    // render(base:annotations:)
    let w = 37, h = 23
    let base = makeImage(width: w, height: h) { x, y in
        (UInt8((x * 7 + y * 3) % 256), UInt8((x * 13) % 256), UInt8((y * 29) % 256), 255)
    }
    let out = ArrowRenderer.render(base: base, annotations: [])
    check(out.width == w && out.height == h, "annotations: [] keeps size")
    check(rawRGBA(base) != nil && rawRGBA(base) == rawRGBA(out), "annotations: [] → byte-identical pixels")
}

do {
    let w = 500, h = 300
    let black = makeImage(width: w, height: h) { _, _ in (0, 0, 0, 255) }
    let arrow = Arrow(start: CGPoint(x: 300, y: 250), end: CGPoint(x: 480, y: 250))
    let label = TextLabel(origin: CGPoint(x: 20, y: 10), text: "Hi", fontSize: 60)
    let out = ArrowRenderer.render(base: black, annotations: [.arrow(arrow), .text(label)])
    check(out.width == w && out.height == h, "annotations: mixed keeps size")
    if let px = rawRGBA(out) {
        check(isRedish(pixel(px, width: w, x: 390, y: 250)), "annotations: arrow drawn", "\(pixel(px, width: w, x: 390, y: 250))")
        let sz = ArrowRenderer.textSize(label)
        var red = 0
        for y in 0..<Int(sz.height + 10) { for x in 20..<Int(20 + sz.width) where isRedish(pixel(px, width: w, x: x, y: y)) { red += 1 } }
        check(red > 200, "annotations: text drawn at the top-left (flipped bitmap)", "red=\(red)")
        let bottomLeft = (h / 2..<h).allSatisfy { y in (0..<250).allSatisfy { isDark(pixel(px, width: w, x: $0, y: y)) } }
        check(bottomLeft, "annotations: text not mirrored to the bottom")
    } else {
        check(false, "annotations: readable output bytes")
    }

    let arrows = [arrow, Arrow(start: CGPoint(x: 50, y: 280), end: CGPoint(x: 200, y: 150))]
    let viaArrows = rawRGBA(ArrowRenderer.render(base: black, arrows: arrows))
    let viaAnn = rawRGBA(ArrowRenderer.render(base: black, annotations: arrows.map(Annotation.arrow)))
    check(viaArrows != nil && viaArrows == viaAnn, "annotations: render(arrows:) == render(annotations:) byte-for-byte")
}

// MARK: - pngData

do {
    let img = makeImage(width: 31, height: 17) { x, y in (UInt8(x * 8), UInt8(y * 15), 128, 255) }
    let png = ArrowRenderer.pngData(img)
    let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    check(png.count > 8 && Array(png.prefix(8)) == sig, "pngData: PNG signature")
    if let src = CGImageSourceCreateWithData(png as CFData, nil),
       let decoded = CGImageSourceCreateImageAtIndex(src, 0, nil) {
        check(decoded.width == 31 && decoded.height == 17, "pngData: decodes to same size", "\(decoded.width)×\(decoded.height)")
    } else {
        check(false, "pngData: decodes")
    }
}

// MARK: - ImageFit

do {
    // Image larger than view → scale down; wider aspect → letterbox top/bottom.
    let fit = ImageFit(imageSize: CGSize(width: 2000, height: 1000), viewSize: CGSize(width: 800, height: 600))
    check(approx(fit.scale, 0.4), "ImageFit: larger image scales down", "\(fit.scale)")
    check(approx(fit.imageRect.size.width, 800) && approx(fit.imageRect.size.height, 400), "ImageFit: fitted size", "\(fit.imageRect)")
    check(approx(fit.imageRect.origin.x, 0) && approx(fit.imageRect.origin.y, 100), "ImageFit: letterbox centered vertically", "\(fit.imageRect)")

    // Taller aspect → pillarbox left/right.
    let tall = ImageFit(imageSize: CGSize(width: 100, height: 200), viewSize: CGSize(width: 400, height: 200))
    check(approx(tall.scale, 1), "ImageFit: tall image scale", "\(tall.scale)")
    check(approx(tall.imageRect.origin.x, 150) && approx(tall.imageRect.origin.y, 0), "ImageFit: pillarbox centered horizontally", "\(tall.imageRect)")

    // Smaller image scales up.
    let small = ImageFit(imageSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 400, height: 400))
    check(approx(small.scale, 4), "ImageFit: smaller image scales up", "\(small.scale)")

    // Mapping.
    check(approx(fit.toView(CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 100)), "ImageFit: toView origin", "\(fit.toView(.zero))")
    check(approx(fit.toView(CGPoint(x: 2000, y: 1000)), CGPoint(x: 800, y: 500)), "ImageFit: toView far corner")
    check(approx(fit.toImage(CGPoint(x: 400, y: 300)), CGPoint(x: 1000, y: 500)), "ImageFit: toImage view center → image center")
    let p = CGPoint(x: 123.25, y: 777.5)
    check(approx(fit.toImage(fit.toView(p)), p, 1e-9), "ImageFit: round-trip image→view→image")
    let q = CGPoint(x: 10, y: 50) // in letterbox area → outside image, not clamped
    check(approx(fit.toView(fit.toImage(q)), q, 1e-9), "ImageFit: round-trip view→image→view")
    check(fit.toImage(q).y < 0, "ImageFit: toImage not clamped", "\(fit.toImage(q))")

    // Zero sizes don't crash or produce NaN.
    for (i, v) in [
        ImageFit(imageSize: .zero, viewSize: CGSize(width: 100, height: 100)),
        ImageFit(imageSize: CGSize(width: 100, height: 100), viewSize: .zero),
        ImageFit(imageSize: .zero, viewSize: .zero),
        ImageFit(imageSize: CGSize(width: 100, height: 0), viewSize: CGSize(width: 50, height: 50)),
    ].enumerated() {
        let a = v.toImage(CGPoint(x: 5, y: 5)), b = v.toView(CGPoint(x: 5, y: 5))
        let r = v.imageRect
        let finite = v.scale.isFinite && v.scale > 0 && a.x.isFinite && a.y.isFinite && b.x.isFinite && b.y.isFinite
            && r.origin.x.isFinite && r.origin.y.isFinite && r.width.isFinite && r.height.isFinite
        check(finite, "ImageFit: zero size #\(i) safe", "scale=\(v.scale) rect=\(r) a=\(a) b=\(b)")
    }
}

// MARK: - ArrowRules

check(ArrowRules.isTooShort(from: .zero, to: CGPoint(x: 4.9, y: 0)), "ArrowRules: 4.9 is too short")
check(!ArrowRules.isTooShort(from: .zero, to: CGPoint(x: 5, y: 0)), "ArrowRules: 5 is not too short")
check(!ArrowRules.isTooShort(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 4, y: 5)), "ArrowRules: 3-4-5 diagonal not too short")
check(ArrowRules.isTooShort(from: CGPoint(x: 1, y: 1), to: CGPoint(x: 4, y: 4.9)), "ArrowRules: diagonal 4.92 too short")

// MARK: - Countdown

do {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    var c = Countdown(startedAt: t0)
    check(approx(c.duration, 5), "Countdown: default duration 5")
    check(!c.isPaused, "Countdown: not paused at start")
    check(approx(c.remaining(at: at(0)), 5), "Countdown: remaining at start = 5")
    check(approx(c.remaining(at: at(2)), 3), "Countdown: remaining after 2s = 3", "\(c.remaining(at: at(2)))")
    check(!c.isExpired(at: at(4.99)), "Countdown: not expired at 4.99s")
    check(c.isExpired(at: at(5)), "Countdown: expired at 5s")
    check(approx(c.remaining(at: at(9)), 0), "Countdown: remaining clamped at 0")
    check(approx(c.remaining(at: at(-3)), 5), "Countdown: remaining clamped at duration before start")
    check(approx(c.fraction(at: at(0)), 1), "Countdown: fraction 1 at start")
    check(approx(c.fraction(at: at(2.5)), 0.5), "Countdown: fraction 0.5 midway")
    check(approx(c.fraction(at: at(7)), 0), "Countdown: fraction 0 after expiry")

    c.pause(at: at(1))
    check(c.isPaused, "Countdown: paused after pause")
    check(approx(c.remaining(at: at(10)), 4), "Countdown: paused at 1s → 4 left at 10s", "\(c.remaining(at: at(10)))")
    check(!c.isExpired(at: at(10)), "Countdown: paused → not expired at 10s")
    c.pause(at: at(3)) // double pause harmless
    check(approx(c.remaining(at: at(10)), 4), "Countdown: double pause harmless", "\(c.remaining(at: at(10)))")
    check(approx(c.fraction(at: at(10)), 0.8), "Countdown: fraction frozen while paused")

    c.resume(at: at(10))
    check(!c.isPaused, "Countdown: not paused after resume")
    check(approx(c.remaining(at: at(12)), 2), "Countdown: resume at 10s → 2 left at 12s", "\(c.remaining(at: at(12)))")
    c.resume(at: at(11)) // double resume harmless
    check(approx(c.remaining(at: at(12)), 2), "Countdown: double resume harmless", "\(c.remaining(at: at(12)))")
    check(!c.isExpired(at: at(13.9)), "Countdown: not expired at 13.9s")
    check(c.isExpired(at: at(14)), "Countdown: expired at 14s after pause/resume")

    // Second pause/resume cycle.
    c.pause(at: at(12))
    c.resume(at: at(20))
    check(approx(c.remaining(at: at(21)), 1), "Countdown: second pause/resume cycle", "\(c.remaining(at: at(21)))")

    // Resume without prior pause is a no-op.
    var d = Countdown(duration: 3, startedAt: t0)
    d.resume(at: at(1))
    check(approx(d.remaining(at: at(1)), 2), "Countdown: resume while running is no-op")

    let z = Countdown(duration: 0, startedAt: t0)
    check(approx(z.fraction(at: at(0)), 0), "Countdown: duration 0 → fraction 0")
    check(z.isExpired(at: at(0)), "Countdown: duration 0 → expired immediately")
}

// MARK: - Summary

print("")
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
