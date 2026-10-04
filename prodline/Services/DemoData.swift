import Foundation
import SwiftData
import UIKit
import SwiftUI

/// Creates projects wired to the local mock server (MockProject/server.py) for end-to-end testing.
enum DemoData {
    struct Spec {
        let slug: String, name: String
        var details: String = ""
        let key: String, startedDaysAgo: Int, accent: Int, coverHues: [Int]?
    }

    /// Must match PROJECTS in MockProject/server.py.
    static let projects: [Spec] = [
        Spec(slug: "habit-hero", name: "Habit Hero", details: "A tiny habit tracker that rewards streaks with plant growth.", key: "hh_live_demo", startedDaysAgo: 9, accent: 0x58CC02, coverHues: nil),
        Spec(slug: "pixel-quest", name: "Pixel Quest", details: "Daily five-minute pixel art puzzles.", key: "pq_live_demo", startedDaysAgo: 23, accent: 0xA35CFF,
             coverHues: [0xFF5FA2, 0xA35CFF, 0x2D1B69]),
        Spec(slug: "side-shop", name: "Side Shop", key: "ss_live_demo", startedDaysAgo: 2, accent: 0xFF9600, coverHues: nil),
        Spec(slug: "flaky-app", name: "Flaky App", key: "fa_live_demo", startedDaysAgo: 5, accent: 0x1CB0F6, coverHues: nil),
    ]

    static func load(baseURL: String, profile: Profile, context: ModelContext) {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        for spec in projects {
            let p = Project(name: spec.name, accentHex: spec.accent,
                            startDate: Date.now.startOfDay.adding(days: -spec.startedDaysAgo),
                            buildDays: profile.buildDays, observeDays: profile.observeDays)
            if let hues = spec.coverHues, let img = coverImage(hues), let data = ImageTools.squareJPEG(img, side: 600) {
                p.coverImage = data
                p.accentHex = ImageTools.dominantAccentHex(UIImage(data: data)!) ?? spec.accent
            }
            p.details = spec.details
            p.endpoint = "\(base)/projects/\(spec.slug)/metrics"
            Keychain.set(spec.key, for: p.id.uuidString)
            context.insert(p)
            for m in ScheduleEngine.makeMilestones(for: p, weekdayMask: profile.milestoneWeekdayMask) {
                context.insert(m)
                m.project = p
                // Past deadlines count as done on time so the demo starts clean.
                if m.dueDate < Date.now.startOfDay { m.completedAt = m.dueDate }
            }
        }
        try? context.save()
    }

    /// Generated artwork so color extraction is exercised without bundling photos.
    static func coverImage(_ hexes: [Int]) -> UIImage? {
        let size = CGSize(width: 600, height: 600)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = hexes.map { UIColor(Color(hex: $0)).cgColor } as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            UIColor.white.withAlphaComponent(0.85).setFill()
            for i in 0..<6 {
                let r = CGFloat(30 + i * 14)
                UIBezierPath(ovalIn: CGRect(x: CGFloat(60 + i * 80), y: CGFloat(380 - i * 50), width: r, height: r)).fill()
            }
        }
    }
}
