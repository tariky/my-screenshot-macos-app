import CoreGraphics
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

// MARK: - lineWidth

check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 100, height: 80)), 3), "lineWidth: small image → 3")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 2000, height: 1000)), 5), "lineWidth: 2000×1000 → 5")
check(approx(ArrowRenderer.lineWidth(for: CGSize(width: 0, height: 0)), 3), "lineWidth: zero size → 3")

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
        // Head is wider than the shaft: a point off-axis inside the head base is red.
        let lw = ArrowRenderer.lineWidth(for: CGSize(width: w, height: h))
        let headBaseX = Int(180 - 4.5 * lw + 2)
        let headSide = pixel(px, width: w, x: headBaseX, y: 50 + Int(lw * 1.2))
        check(isRedish(headSide), "render: head wider than shaft", "\(headSide) at x=\(headBaseX)")
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
