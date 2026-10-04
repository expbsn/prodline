import Testing
import UIKit
import SwiftUI
@testable import prodline

@MainActor
@Suite("Accent & cover images")
struct AccentTests {
    private func image(_ size: CGSize = CGSize(width: 200, height: 200), draw: (CGContext) -> Void) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { draw($0.cgContext) }
    }

    private func hue(_ hex: Int) -> CGFloat {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h * 360
    }

    @Test func solidColorKeepsItsHue() throws {
        let img = image { ctx in UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200)) }
        let hex = try #require(ImageTools.dominantAccentHex(img))
        let h = hue(hex)
        #expect(h < 8 || h > 352)
    }

    @Test func dominantAreaWinsOverSmallAccent() throws {
        let img = image { ctx in
            UIColor.systemBlue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
        let h = hue(try #require(ImageTools.dominantAccentHex(img)))
        #expect(h > 190 && h < 230)
    }

    @Test func vividBeatsLargeGrayBackground() throws {
        let img = image { ctx in
            UIColor(white: 0.9, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor(red: 0.2, green: 0.8, blue: 0.3, alpha: 1).setFill(); ctx.fill(CGRect(x: 60, y: 60, width: 60, height: 60))
        }
        let h = hue(try #require(ImageTools.dominantAccentHex(img)))
        #expect(h > 110 && h < 150)
    }

    @Test func monochromeImageHasNoAccent() {
        let img = image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 100, width: 200, height: 100))
        }
        #expect(ImageTools.dominantAccentHex(img) == nil)
    }

    @Test func normalizedColorsAreUsableAsButtons() {
        // A very dark, desaturated navy gets lifted into a readable range.
        let hex = ImageTools.normalize(r: 0.05, g: 0.07, b: 0.2)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #expect(b >= 0.54 && b <= 0.93)
        #expect(s >= 0.49)
    }

    @Test func demoCoverExtractsAVividColor() throws {
        let img = try #require(DemoData.coverImage([0xFF5FA2, 0xA35CFF, 0x2D1B69]))
        #expect(ImageTools.dominantAccentHex(img) != nil)
    }

    @Test func squareCropAndDownscale() throws {
        let img = image(CGSize(width: 1600, height: 800)) { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1600, height: 800)) }
        let data = try #require(ImageTools.squareJPEG(img, side: 512))
        let out = try #require(UIImage(data: data))
        #expect(out.size.width == 512 && out.size.height == 512)
    }

    @Test func foregroundContrast() {
        #expect(Accent(hex: 0xFFC800).on == Theme.ink)  // yellow -> dark text
        #expect(Accent(hex: 0x58CC02).on == .white)
        #expect(Accent(hex: 0x1C1C1E).on == .white)
        #expect(Accent(hex: 0xFFFFFF).on == Theme.ink)
    }

    @Test func hexRoundTrip() {
        for hex in Theme.swatches { #expect(Color(hex: hex).hex == hex) }
    }
}
