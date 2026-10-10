#!/usr/bin/env swift
// Renders the Screenshot app icon from vectors and builds Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift [--sheet <contact-sheet.png>]
//
// Outputs (relative to the repo root):
//   Resources/AppIcon.png              1024×1024 master
//   Resources/AppIcon.iconset/*.png    every iconset size, each rendered from vectors
//   Resources/AppIcon.icns             via `iconutil -c icns`
//
// Design (Apple macOS icon grid): 1024 canvas, 824×824 continuous-corner body centred with
// a 100 px margin and a soft drop shadow. Deep indigo gradient body with a glassy top
// sheen, a white viewfinder (four corner brackets) around a faint frosted selection, and
// the app's red Skitch-style arrow sweeping in from the lower left. Small sizes get
// thicker strokes and fewer details so they stay legible at 16 and 32 px.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

/// Apple-style continuous-curvature rounded square (the well-known "continuous corner"
/// bezier approximation): each corner blends over 1.528 × radius of edge, giving straight
/// sides and a curvature-continuous squircle corner rather than a circular arc.
func squircle(center c: CGPoint, radius half: CGFloat, corner r: CGFloat = 185) -> CGPath {
    let minX = c.x - half, maxX = c.x + half, minY = c.y - half, maxY = c.y + half
    // (corner point, incoming edge direction, outgoing edge direction), clockwise in y-down.
    let corners: [(CGPoint, CGVector, CGVector)] = [
        (CGPoint(x: maxX, y: minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: maxX, y: maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: minX, y: maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: minX, y: minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]
    let path = CGMutablePath()
    for (k, (cp, din, dout)) in corners.enumerated() {
        // x = distance back along the incoming edge, y = distance along the outgoing edge.
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cp.x - x * din.dx * r + y * dout.dx * r, y: cp.y - x * din.dy * r + y * dout.dy * r)
        }
        if k == 0 { path.move(to: P(1.52866483, 0)) } else { path.addLine(to: P(1.52866483, 0)) }
        path.addCurve(to: P(0.66993427, 0.06549600), control1: P(1.08849323, 0), control2: P(0.86840689, 0))
        path.addLine(to: P(0.63149399, 0.07491100))
        path.addCurve(to: P(0.07491100, 0.63149399), control1: P(0.37282392, 0.16905899), control2: P(0.16905899, 0.37282392))
        path.addLine(to: P(0.06549600, 0.66993427))
        path.addCurve(to: P(0, 1.52866483), control1: P(0, 0.86840689), control2: P(0, 1.08849323))
    }
    path.closeSubpath()
    return path
}

/// Skitch-style arrow outline (same proportions as ScreenshotCore.ArrowRenderer):
/// rounded narrow tail, shaft widening to `neck`, bold head with swept-back barbs.
func arrowPath(from start: CGPoint, to tip: CGPoint, neck: CGFloat) -> CGPath {
    let dx = tip.x - start.x, dy = tip.y - start.y
    let len = (dx * dx + dy * dy).squareRoot()
    let ux = dx / len, uy = dy / len
    let px = -uy, py = ux
    let headLength = 2.6 * neck, halfHead = 2.8 * neck / 2
    let neckBack = headLength * 0.8, halfNeck = neck / 2
    let tailR = 0.55 * neck / 2
    func head(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: tip.x - ux * back + px * side, y: tip.y - uy * back + py * side)
    }
    func tail(_ back: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: start.x - ux * back + px * side, y: start.y - uy * back + py * side)
    }
    let p = CGMutablePath()
    p.move(to: tip)
    p.addLine(to: head(headLength, halfHead))
    p.addLine(to: head(neckBack, halfNeck))
    p.addLine(to: tail(0, tailR))
    p.addArc(tangent1End: tail(tailR, tailR), tangent2End: tail(tailR, 0), radius: tailR)
    p.addArc(tangent1End: tail(tailR, -tailR), tangent2End: tail(0, -tailR), radius: tailR)
    p.addLine(to: head(neckBack, -halfNeck))
    p.addLine(to: head(headLength, -halfHead))
    p.closeSubpath()
    return p
}

/// One viewfinder corner bracket: an L with a rounded bend, as an open stroke path.
func bracket(corner: CGPoint, dirX: CGFloat, dirY: CGFloat, arm: CGFloat, bend: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: corner.x + dirX * arm, y: corner.y))
    p.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x, y: corner.y + dirY * arm), radius: bend)
    p.addLine(to: CGPoint(x: corner.x, y: corner.y + dirY * arm))
    return p
}

// MARK: - Icon

/// Renders the icon at `px`×`px` pixels. All geometry is authored on the 1024 grid in a
/// y-down space; `u` converts device pixels to grid units for size-aware stroke weights.
func renderIcon(px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let s = CGFloat(px) / 1024
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: s, y: -s)               // y-down, 1024 units
    let u = 1 / s                          // one device pixel in grid units
    let small = px <= 32                   // 16, 32: simplified
    let tiny = px <= 16

    let center = CGPoint(x: 512, y: 512)
    let body = squircle(center: center, radius: 412)

    // Drop shadow beneath the body (offsets/blur are in device space, not scaled by CTM).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 28 * s, color: rgb(0x000000, 0.32))
    ctx.addPath(body); ctx.setFillColor(rgb(0x1A1B4B)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -2 * s), blur: 4 * s, color: rgb(0x000000, 0.22))
    ctx.addPath(body); ctx.setFillColor(rgb(0x1A1B4B)); ctx.fillPath()
    ctx.restoreGState()

    // Body: indigo → deep navy, lit from the top.
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0x5456EA)), (0.5, rgb(0x2E2EA6)), (1, rgb(0x131340))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // Soft violet glow from the upper right for depth.
    ctx.drawRadialGradient(gradient([(0, rgb(0x9A7CFF, 0.45)), (1, rgb(0x9A7CFF, 0))]),
                           startCenter: CGPoint(x: 760, y: 200), startRadius: 0,
                           endCenter: CGPoint(x: 760, y: 200), endRadius: 560, options: [])
    // Darken the bottom-left a touch so the arrow's tail sits in shade.
    ctx.drawRadialGradient(gradient([(0, rgb(0x05051A, 0.35)), (1, rgb(0x05051A, 0))]),
                           startCenter: CGPoint(x: 180, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 180, y: 900), endRadius: 520, options: [])
    // Glassy top sheen: a soft wash of light fading out by the middle.
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.16)), (0.5, rgb(0xFFFFFF, 0.04)), (1, rgb(0xFFFFFF, 0))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Rim light: a hairline inner stroke, bright on top, fading toward the bottom.
    if !tiny {
        ctx.saveGState()
        ctx.addPath(body); ctx.clip()
        ctx.addPath(body)
        ctx.setLineWidth(max(6, 1.2 * u))
        ctx.replacePathWithStrokedPath(); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.55)), (0.35, rgb(0xFFFFFF, 0.08)),
                                         (0.8, rgb(0xFFFFFF, 0.0)), (1, rgb(0x000000, 0.25))]),
                               start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
        ctx.restoreGState()
    }

    // Selection frame (viewfinder), centred.
    let frame = small ? CGRect(x: 222, y: 222, width: 580, height: 580)
                      : CGRect(x: 238, y: 238, width: 548, height: 548)

    // Frosted selection fill: a faint glass pane inside the brackets.
    if !tiny {
        let pane = CGPath(roundedRect: frame.insetBy(dx: 26, dy: 26), cornerWidth: 34, cornerHeight: 34, transform: nil)
        ctx.saveGState()
        ctx.addPath(pane); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.16)), (1, rgb(0xFFFFFF, 0.05))]),
                               start: CGPoint(x: frame.minX, y: frame.minY),
                               end: CGPoint(x: frame.maxX, y: frame.maxY), options: [])
        ctx.restoreGState()
        if !small {
            ctx.addPath(pane)
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
    }

    // Corner brackets.
    let bw = max(small ? 52 : 40, 1.5 * u)
    let arm: CGFloat = small ? 150 : 128
    let bend: CGFloat = small ? 44 : 52
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * s), blur: 18 * s, color: rgb(0x0A0A30, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineWidth(bw)
    let i = bw / 2
    let f = frame.insetBy(dx: i, dy: i)
    for (c, dx, dy) in [(CGPoint(x: f.minX, y: f.minY), CGFloat(1), CGFloat(1)),
                        (CGPoint(x: f.maxX, y: f.minY), -1, 1),
                        (CGPoint(x: f.maxX, y: f.maxY), -1, -1),
                        (CGPoint(x: f.minX, y: f.maxY), 1, -1)] {
        ctx.addPath(bracket(corner: c, dirX: dx, dirY: dy, arm: arm, bend: bend))
    }
    // Pure white on top easing to a faint lavender at the bottom, like lit frosted plastic.
    ctx.saveGState()
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF)), (1, rgb(0xE4E3F7))]),
                           start: CGPoint(x: 512, y: frame.minY), end: CGPoint(x: 512, y: frame.maxY), options: [])
    ctx.restoreGState()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // The red Skitch arrow, annotating the selection from lower left to upper right.
    let neck: CGFloat = tiny ? 100 : small ? 86 : 70
    let tail = small ? CGPoint(x: 348, y: 676) : CGPoint(x: 364, y: 660)
    let tip = small ? CGPoint(x: 668, y: 356) : CGPoint(x: 652, y: 372)
    let arrow = arrowPath(from: tail, to: tip, neck: neck)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 30 * s, color: rgb(0x07071F, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setLineJoin(.round); ctx.setLineCap(.round)
    let outline = max(small ? 0 : 11, tiny ? 0 : 0.9 * u)
    if outline > 0 {
        ctx.addPath(arrow)
        ctx.setStrokeColor(rgb(0xFFFFFF))
        ctx.setLineWidth(2 * outline)
        ctx.strokePath()
    }
    // Red fill with a gentle top-to-bottom shade so it reads as a solid, lit object.
    ctx.saveGState()
    ctx.addPath(arrow); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(0xFF5A4E)), (0.55, rgb(0xFF3B30)), (1, rgb(0xE0261C))]),
                           start: CGPoint(x: tip.x + 60, y: tip.y - 80), end: CGPoint(x: tail.x, y: tail.y + 20),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    if !small {
        // Subtle specular along the upper edge of the arrow.
        // Gradient runs across the arrow, from its upper-left edge toward the axis.
        let dx = tip.x - tail.x, dy = tip.y - tail.y, l = (dx * dx + dy * dy).squareRoot()
        let nx = dy / l, ny = -dx / l                  // perpendicular pointing up-left
        let mid = CGPoint(x: (tip.x + tail.x) / 2, y: (tip.y + tail.y) / 2)
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.30)), (1, rgb(0xFFFFFF, 0))]),
                               start: CGPoint(x: mid.x + nx * 1.4 * neck, y: mid.y + ny * 1.4 * neck),
                               end: mid, options: [.drawsBeforeStartLocation])
    }
    ctx.restoreGState()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Output

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

/// Contact sheet: 16/32/64/128 at 1×, plus 16/32 magnified 4× (nearest neighbour), on
/// light and dark backgrounds.
func contactSheet(to url: URL) {
    let sizes = [16, 32, 64, 128]
    let w = 960, rowH = 200, h = rowH * 2
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for (row, bg) in [(0, rgb(0xF2F2F5)), (1, rgb(0x1E1E22))] {
        let y0 = CGFloat(h - (row + 1) * rowH)
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: y0, width: CGFloat(w), height: CGFloat(rowH)))
        var x: CGFloat = 24
        for sz in sizes {
            let img = renderIcon(px: sz)
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: x, y: y0 + (CGFloat(rowH) - CGFloat(sz)) / 2, width: CGFloat(sz), height: CGFloat(sz)))
            x += CGFloat(sz) + 28
        }
        ctx.interpolationQuality = .none
        for sz in [16, 32] {
            let img = renderIcon(px: sz)
            let m = CGFloat(sz * (sz == 16 ? 8 : 4))
            ctx.draw(img, in: CGRect(x: x, y: y0 + (CGFloat(rowH) - m) / 2, width: m, height: m))
            x += m + 28
        }
        // Retina 32@2x (i.e. 64 px shown at 32 pt is the 64 render) shown at 2× for reference.
        let r = renderIcon(px: 256)
        ctx.interpolationQuality = .high
        ctx.draw(r, in: CGRect(x: x, y: y0 + 12, width: 176, height: 176))
    }
    writePNG(ctx.makeImage()!, to: url)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
let fm = FileManager.default
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

writePNG(renderIcon(px: 1024), to: resources.appendingPathComponent("AppIcon.png"))
for base in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(px: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(renderIcon(px: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--sheet"), i + 1 < args.count {
    contactSheet(to: URL(fileURLWithPath: args[i + 1]))
}
print("Wrote \(resources.path)/AppIcon.icns")
