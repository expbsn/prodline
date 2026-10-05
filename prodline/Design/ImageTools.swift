import UIKit

enum ImageTools {
    /// Center-crops to a square and downsizes for storage.
    static func squareJPEG(from data: Data, side: CGFloat = 1024) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return squareJPEG(image, side: side)
    }

    static func squareJPEG(_ image: UIImage, side: CGFloat = 1024) -> Data? {
        let s = min(image.size.width, image.size.height)
        guard s > 0 else { return nil }
        let target = min(side, s)
        let scale = target / s
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            image.draw(in: CGRect(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return out.jpegData(compressionQuality: 0.85)
    }

    /// Picks the most prominent vivid color and tunes it to work as a button color.
    /// Black-and-white or muted photos get a charcoal carrying the photo's faint tint instead.
    static func dominantAccentHex(_ image: UIImage) -> Int? {
        let side = 48
        guard let cg = image.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var rSum = [Double](repeating: 0, count: bins)
        var gSum = [Double](repeating: 0, count: bins)
        var bSum = [Double](repeating: 0, count: bins)
        var total = 0.0

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            let v = maxC
            let s = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard s > 0.18, v > 0.18 else { continue }
            var h: Double
            let d = maxC - minC
            if maxC == r { h = (g - b) / d } else if maxC == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
            h = (h / 6).truncatingRemainder(dividingBy: 1)
            if h < 0 { h += 1 }
            // Favor vivid, mid-bright pixels.
            let w = s * s * (v > 0.95 ? 0.7 : 1)
            let bin = min(Int(h * Double(bins)), bins - 1)
            weight[bin] += w
            rSum[bin] += r * w; gSum[bin] += g * w; bSum[bin] += b * w
            total += w
        }
        // Too little color: a neutral that still leans the way the photo does (warm, cool or pure gray).
        guard total > Double(side * side) * 0.01 else { return neutralHex(pixels) }

        // Merge each bin with its neighbors so hues on a bin edge aren't split.
        var best = 0, bestW = -1.0
        for i in 0..<bins {
            let w = weight[i] + 0.5 * (weight[(i + 1) % bins] + weight[(i + bins - 1) % bins])
            if w > bestW { bestW = w; best = i }
        }
        let w = weight[best]
        guard w > 0 else { return nil }
        return normalize(r: rSum[best] / w, g: gSum[best] / w, b: bSum[best] / w)
    }

    /// Dark enough for white text on buttons, light enough to read as a color rather than black.
    static func neutralHex(_ pixels: [UInt8]) -> Int? {
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 127 {
            r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
        }
        guard n > 0 else { return nil }
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        UIColor(red: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        let out = UIColor(hue: h, saturation: min(s, 0.18), brightness: 0.27, alpha: 1)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0
        out.getRed(&rr, green: &gg, blue: &bb, alpha: &a)
        return Int(rr * 255) << 16 | Int(gg * 255) << 8 | Int(bb * 255)
    }

    /// Keeps hue, pushes saturation/brightness into a range that reads well as a UI accent.
    static func normalize(r: Double, g: Double, b: Double) -> Int {
        let ui = UIColor(red: r, green: g, blue: b, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Photos average out muddy; lift toward the punchy range the hand-picked accents live in.
        let ns = min(max(s * 1.1, 0.7), 0.95)
        let nv = min(max(v, 0.74), 0.92)
        let out = UIColor(hue: h, saturation: ns, brightness: nv, alpha: 1)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0
        out.getRed(&rr, green: &gg, blue: &bb, alpha: &a)
        return Int(rr * 255) << 16 | Int(gg * 255) << 8 | Int(bb * 255)
    }
}

/// Decoded cover images, keyed by project + data size, so cards don't re-decode on every render.
enum CoverCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ data: Data?, key: String) -> UIImage? {
        guard let data else { return nil }
        let k = "\(key)-\(data.count)" as NSString
        if let img = cache.object(forKey: k) { return img }
        guard let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: k)
        return img
    }
}
