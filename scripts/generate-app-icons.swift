#!/usr/bin/env swift
//
//  generate-app-icons.swift
//  Renders the Hercules "Atlas H" mark into a complete app icon set.
//
//  The mark itself comes from brand/logo-exploration/final/atlas-app-icon.svg and is
//  reproduced here as paths so every size can be rendered from vector rather than
//  resampled from one bitmap.
//
//  macOS and iOS need different artwork:
//
//    - macOS does not mask app icons. The squircle has to be baked into the PNG, inset
//      inside the canvas, with the drop shadow drawn in. Shape constants below were fitted
//      against macOS 26's own icon mask (see the accompanying note in scripts/README.md):
//      body = 80.47% of the canvas, corner radius = 0.26 x body side, continuous curvature.
//
//    - iOS masks the icon itself, so its artwork stays full-bleed and square. Baking a
//      squircle there would get clipped a second time by a slightly different curve.
//
//  The two smallest macOS sizes and the three smallest iOS sizes use a simplified glyph:
//  at that scale the crossbar's full 14-unit drop collapses into the stems and the letter
//  reads as two blobs, so the drop is flattened and the glyph is scaled up in its tile.
//
//  Usage:  swift scripts/generate-app-icons.swift <output-dir> [--dark]
//

import AppKit
import SwiftUI

// MARK: - Brand

/// Ivory field, ink mark. Inverted from the original dark icon so the tile does not read as
/// the darkest thing in the Dock. Both colours are the brand's own.
struct Palette {
    let field: CGColor
    let mark: CGColor

    static let ink = CGColor(srgbRed: 38 / 255, green: 36 / 255, blue: 31 / 255, alpha: 1)      // #26241F
    static let ivory = CGColor(srgbRed: 242 / 255, green: 239 / 255, blue: 232 / 255, alpha: 1) // #F2EFE8

    static let light = Palette(field: ivory, mark: ink)
    static let dark = Palette(field: ink, mark: ivory)
}

// MARK: - Shape constants, fitted against the system mask

enum Shape {
    /// Visible body as a fraction of the full canvas.
    static let bodyRatio = 0.8047
    /// Corner radius as a fraction of the body's side length.
    static let cornerRatio = 0.26
}

// MARK: - The mark

/// The glyph lives in a 58 x 64 box in the source SVG's coordinate space, y-down,
/// with its top-left corner at (21, 18).
enum Mark {
    static let boxOrigin = CGPoint(x: 21, y: 18)
    static let boxSize = CGSize(width: 58, height: 64)

    struct Metrics {
        /// Glyph height as a fraction of the body's side length.
        var heightRatio: Double
        /// Crossbar start and end y, in SVG units.
        var barStartY: Double
        var barEndY: Double
        var barWidth: Double
    }

    static let full = Metrics(heightRatio: 0.55, barStartY: 59, barEndY: 45, barWidth: 14)

    /// Flatter crossbar and a larger glyph, for sizes where the full mark turns to mush.
    static let simplified = Metrics(heightRatio: 0.66, barStartY: 55, barEndY: 49, barWidth: 15)

    /// Draws the mark into `rect`, mapping the SVG box onto it.
    static func draw(in ctx: CGContext, rect: CGRect, metrics: Metrics, color: CGColor) {
        ctx.saveGState()

        // Map SVG's y-down box onto the y-up target rect.
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: rect.width / boxSize.width, y: -rect.height / boxSize.height)
        ctx.translateBy(x: -boxOrigin.x, y: -boxOrigin.y)

        ctx.setFillColor(color)
        ctx.setStrokeColor(color)

        // Two capsule stems.
        for x in [21.0, 63.0] {
            let stem = CGRect(x: x, y: 18, width: 16, height: 64)
            ctx.addPath(CGPath(roundedRect: stem, cornerWidth: 8, cornerHeight: 8, transform: nil))
            ctx.fillPath()
        }

        // The descending crossbar: the weight-trend line that makes this an H and a chart.
        let bar = CGMutablePath()
        bar.move(to: CGPoint(x: 31, y: metrics.barStartY))
        bar.addCurve(to: CGPoint(x: 69, y: metrics.barEndY),
                     control1: CGPoint(x: 43, y: metrics.barStartY),
                     control2: CGPoint(x: 51, y: metrics.barEndY + 4))
        ctx.addPath(bar)
        ctx.setLineWidth(metrics.barWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        ctx.restoreGState()
    }
}

// MARK: - Rendering

enum Platform {
    /// Squircle baked in, inset inside the canvas, shadow drawn.
    case macOS
    /// Full-bleed square; the system applies its own mask.
    case iOS
}

func render(size: Int, platform: Platform, palette: Palette, simplified: Bool) -> Data {
    let S = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let body: CGRect
    switch platform {
    case .macOS:
        let side = (S * Shape.bodyRatio).rounded()
        body = CGRect(x: ((S - side) / 2).rounded(), y: ((S - side) / 2).rounded(),
                      width: side, height: side)
    case .iOS:
        body = CGRect(x: 0, y: 0, width: S, height: S)
    }

    // Body shape.
    let shapePath: CGPath
    switch platform {
    case .macOS:
        let r = Shape.cornerRatio * body.width
        shapePath = RoundedRectangle(cornerRadius: r, style: .continuous).path(in: body).cgPath
    case .iOS:
        shapePath = CGPath(rect: body, transform: nil)
    }

    // A restrained shadow, only on macOS: the Dock does not add one for a bitmap icon,
    // and without it the tile sits flatter than its neighbours.
    if case .macOS = platform, size >= 64 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.010),
                      blur: S * 0.022,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.26))
        ctx.addPath(shapePath)
        ctx.setFillColor(palette.field)
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shapePath)
    ctx.clip()
    ctx.setFillColor(palette.field)
    ctx.fill(body)

    let metrics = simplified ? Mark.simplified : Mark.full
    let glyphH = body.height * metrics.heightRatio
    let glyphW = glyphH * (Mark.boxSize.width / Mark.boxSize.height)
    let glyphRect = CGRect(x: body.midX - glyphW / 2,
                           y: body.midY - glyphH / 2,
                           width: glyphW, height: glyphH)
    Mark.draw(in: ctx, rect: glyphRect, metrics: metrics, color: palette.mark)
    ctx.restoreGState()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Output set

let args = Array(CommandLine.arguments.dropFirst())
guard let outDir = args.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write("usage: generate-app-icons.swift <output-dir> [--dark]\n".data(using: .utf8)!)
    exit(2)
}
let palette = args.contains("--dark") ? Palette.dark : Palette.light

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Which sizes get the simplified mark is decided in *points*, not pixels: the 16pt and 32pt
// macOS slots are physically small however many pixels back them, and on a Retina display the
// 64px raster is the one actually drawn at 32pt. Splitting by raster size instead would make
// the same slot look different on Retina and non-Retina.
//
// No file may serve both a simplified and a full role, so the raster sizes partition cleanly:
//   macOS  16/32/64 -> 16pt and 32pt slots      128/256/512/1024 -> 128pt and up
//   iOS    40/58/60/87 -> 20pt and 29pt slots   80/120/180/1024  -> 40pt and up
let macSizes: [(Int, Bool)] = [(16, true), (32, true), (64, true), (128, false),
                               (256, false), (512, false), (1024, false)]
let iosSizes: [(Int, Bool)] = [(40, true), (58, true), (60, true), (87, true),
                               (80, false), (120, false), (180, false), (1024, false)]

for (size, simplified) in macSizes {
    let data = render(size: size, platform: .macOS, palette: palette, simplified: simplified)
    let name = "icon_\(size).png"
    try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("mac  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(size)x\(size)\(simplified ? "  (simplified mark)" : "")")
}

for (size, simplified) in iosSizes {
    let data = render(size: size, platform: .iOS, palette: palette, simplified: simplified)
    let name = size == 1024 ? "icon_ios_1024.png" : "icon_ios_\(size).png"
    try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
    print("ios  \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(size)x\(size)\(simplified ? "  (simplified mark)" : "")")
}

print("\nwrote \(macSizes.count + iosSizes.count) files to \(outDir)")
