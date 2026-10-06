import SwiftUI
import Testing
@testable import prodline

@MainActor
@Suite("Share card")
struct ShareCardTests {
    private var data: ShareCardData {
        ShareCardData(name: "Habit Hero", initial: "H", accent: Accent(hex: 0x58CC02), cover: nil, status: "Day 11 of building",
                      days: 11, values: [.activeDays: "2", .goals: "2"])
    }

    private func render(_ style: ShareCardStyle) throws -> UIImage {
        let r = ImageRenderer(content: ShareCardView(data: data, stats: [.activeDays, .goals], style: style))
        r.scale = 3
        r.isOpaque = false
        return try #require(r.uiImage)
    }

    /// Alpha of the pixel at (x, y) in the PNG the share sheet exports.
    private func alpha(_ image: UIImage, x: Int, y: Int) throws -> UInt8 {
        let png = try #require(PNGImage(image: image).image.pngData())
        let cg = try #require(UIImage(data: png)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let ctx = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        return pixel[3]
    }

    @Test func cardsFillTheSquareArtworkAndExportAtThreeX() throws {
        let image = try render(.color)
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1620)
        // Opaque inside, the rounded corner is transparent.
        #expect(try alpha(image, x: 540, y: 300) == 255)
        #expect(try alpha(image, x: 0, y: 0) == 0)
    }

    @Test func transparentVersionKeepsItsTransparency() throws {
        let image = try render(.transparent)
        // Empty space between the stats is see-through in the exported PNG.
        #expect(try alpha(image, x: 1070, y: 200) == 0)
    }
}
