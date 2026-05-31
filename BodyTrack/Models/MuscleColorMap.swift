import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Color Definitions

/// Exact RGB values from the color-map PNG files (body_front_map / body_back_map).
private struct MapColor {
    let r: UInt8; let g: UInt8; let b: UInt8

    /// Squared Euclidean distance to a sampled pixel (avoids sqrt, same ordering)
    func distanceSq(to pixel: RGBA) -> Int {
        let dr = Int(r) - Int(pixel.r)
        let dg = Int(g) - Int(pixel.g)
        let db = Int(b) - Int(pixel.b)
        return dr*dr + dg*dg + db*db
    }
}

private let frontColorMap: [(MuscleRegion, MapColor)] = [
    (.chest,        MapColor(r: 250, g:   0, b:   0)),   // #FA0000
    (.frontDelt,    MapColor(r:   0, g: 250, b:   0)),   // #00FA00
    (.biceps,       MapColor(r:   0, g:   0, b: 250)),   // #0000FA
    (.forearmFront, MapColor(r: 125, g: 125, b:   0)),   // #7D7D00
    (.upperAbs,     MapColor(r: 250, g: 250, b:   0)),   // #FAFA00
    (.lowerAbs,     MapColor(r: 175, g: 250, b:   0)),   // #AFFA00
    (.obliques,     MapColor(r: 250, g:   0, b: 250)),   // #FA00FA
    (.quadriceps,   MapColor(r:   0, g: 250, b: 250)),   // #00FAFA
    (.tibialis,     MapColor(r: 250, g: 125, b:   0)),   // #FA7D00
]

private let backColorMap: [(MuscleRegion, MapColor)] = [
    (.traps,        MapColor(r:   0, g: 125, b: 250)),   // #007DFA
    (.rearDelt,     MapColor(r: 125, g: 250, b:   0)),   // #7DFA00
    (.lats,         MapColor(r: 250, g:   0, b: 125)),   // #FA007D
    (.triceps,      MapColor(r: 125, g:   0, b: 250)),   // #7D00FA
    (.forearmBack,  MapColor(r:   0, g: 125, b: 125)),   // #007D7D
    (.lowerBack,    MapColor(r:   0, g: 250, b: 125)),   // #00FA7D
    (.glutes,       MapColor(r: 250, g: 150, b:   0)),   // #FA9600
    (.hamstrings,   MapColor(r: 150, g: 150, b:   0)),   // #969600
    (.calves,       MapColor(r:   0, g: 250, b: 150)),   // #00FA96
]

// Lookup dict'i (mask generation için)
private let frontColorDict: [MuscleRegion: MapColor] =
    Dictionary(uniqueKeysWithValues: frontColorMap)
private let backColorDict: [MuscleRegion: MapColor] =
    Dictionary(uniqueKeysWithValues: backColorMap)

/// Maksimum kabul edilebilir kare mesafe ≈ per-channel 60 birimlik hata payı.
/// sqrt(60²+60²+60²) ≈ 104 — düz renkli PNG'de bu fazlasıyla yeterli.
private let maxDistanceSq = 60 * 60 * 3

// MARK: - Pixel Sampler

/// Harita PNG'sinde normalleştirilmiş noktadaki kası döndürür.
/// En yakın renk eşleştirmesi kullanır — çakışma riski sıfır.
func muscleRegion(at normalizedPoint: CGPoint, isFront: Bool) -> MuscleRegion? {
    let imageName = isFront ? "body_front_map" : "body_back_map"
    guard let cgImage = loadCGImage(named: imageName) else { return nil }

    let px = Int(normalizedPoint.x * Double(cgImage.width))
    let py = Int(normalizedPoint.y * Double(cgImage.height))
    guard px >= 0, py >= 0, px < cgImage.width, py < cgImage.height else { return nil }
    guard let pixel = samplePixel(cgImage, x: px, y: py) else { return nil }
    guard pixel.a > 10 else { return nil }   // şeffaf alan (arka plan) → geçersiz

    let colorMap = isFront ? frontColorMap : backColorMap

    var bestRegion: MuscleRegion? = nil
    var bestDist = Int.max
    for (region, mc) in colorMap {
        let d = mc.distanceSq(to: pixel)
        if d < bestDist {
            bestDist = d
            bestRegion = region
        }
    }
    return bestDist <= maxDistanceSq ? bestRegion : nil
}

// MARK: - Mask Generation

/// Verilen kas bölgesi için beyaz/şeffaf maske CGImage döndürür. Önbelleğe alınır.
private var maskCache: [String: CGImage] = [:]

func muscleMask(for region: MuscleRegion, isFront: Bool) -> CGImage? {
    let key = "\(isFront ? "f" : "b")_\(region.rawValue)"
    if let cached = maskCache[key] { return cached }

    let imageName = isFront ? "body_front_map" : "body_back_map"
    guard let source = loadCGImage(named: imageName) else { return nil }

    let colorDict = isFront ? frontColorDict : backColorDict
    let colorMap  = isFront ? frontColorMap  : backColorMap
    guard colorDict[region] != nil else { return nil }

    let w = source.width, h = source.height

    // Kaynak pikselleri oku
    guard let ctx = CGContext(
        data: nil,
        width: w, height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let srcData = ctx.data else { return nil }

    let srcBytes = srcData.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var pixelData = [UInt8](repeating: 0, count: w * h * 4)

    for i in 0 ..< w * h {
        let base = i * 4
        let a = srcBytes[base + 3]
        guard a > 10 else { continue }   // arka plan

        let px = RGBA(r: srcBytes[base], g: srcBytes[base+1], b: srcBytes[base+2], a: a)

        // En yakın rengi bul
        var bestRegionForPixel: MuscleRegion? = nil
        var bestDist = Int.max
        for (r, mc) in colorMap {
            let d = mc.distanceSq(to: px)
            if d < bestDist { bestDist = d; bestRegionForPixel = r }
        }

        let matches = bestDist <= maxDistanceSq && bestRegionForPixel == region
        pixelData[base]     = 255
        pixelData[base + 1] = 255
        pixelData[base + 2] = 255
        pixelData[base + 3] = matches ? 255 : 0
    }

    guard let maskCtx = CGContext(
        data: &pixelData,
        width: w, height: h,
        bitsPerComponent: 8,
        bytesPerRow: w * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let mask = maskCtx.makeImage() else { return nil }

    maskCache[key] = mask
    return mask
}

// MARK: - Platform Helpers

private func loadCGImage(named name: String) -> CGImage? {
#if canImport(UIKit)
    return UIImage(named: name)?.cgImage
#elseif canImport(AppKit)
    return NSImage(named: name).flatMap { img in
        var rect = CGRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
#else
    return nil
#endif
}

private struct RGBA { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

private func samplePixel(_ image: CGImage, x: Int, y: Int) -> RGBA? {
    var buf = [UInt8](repeating: 0, count: 4)
    guard let ctx = CGContext(
        data: &buf,
        width: 1, height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.translateBy(x: CGFloat(-x), y: CGFloat(-(image.height - y - 1)))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return RGBA(r: buf[0], g: buf[1], b: buf[2], a: buf[3])
}
