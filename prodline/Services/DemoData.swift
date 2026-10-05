import Foundation
import SwiftData
import UIKit
import SwiftUI

/// Creates projects wired to the local mock server (MockProject/server.py) for end-to-end testing.
enum DemoData {
    struct Spec {
        let slug: String, name: String
        var details: String = ""
        let key: String, startedDaysAgo: Int, accent: Int
        var githubRepo: String = ""
        /// Bundled photo (Assets: Cover-<slug>, credits in design/IMAGE_CREDITS.md).
        /// `accent` is the fallback when the photo has no usable color (Side Shop is black and white).
        var cover: UIImage? { UIImage(named: "Cover-\(slug)") }
    }

    /// Must match PROJECTS in MockProject/server.py.
    static let projects: [Spec] = [
        Spec(slug: "habit-hero", name: "Habit Hero", details: "A tiny habit tracker that rewards streaks with plant growth.", key: "hh_live_demo", startedDaysAgo: 9, accent: 0x58CC02),
        Spec(slug: "pixel-quest", name: "Pixel Quest", details: "Daily five-minute pixel art puzzles.", key: "pq_live_demo", startedDaysAgo: 23, accent: 0xA35CFF),
        Spec(slug: "side-shop", name: "Side Shop", details: "A one-page shop for limited print runs.", key: "ss_live_demo", startedDaysAgo: 2, accent: 0x3A3A3C, githubRepo: "demo/side-shop"),
        Spec(slug: "flaky-app", name: "Flaky App", key: "fa_live_demo", startedDaysAgo: 5, accent: 0xD9902F),
    ]

    static func load(baseURL: String, profile: Profile, context: ModelContext) {
        let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        // The mock server also plays GitHub for repos named demo/<project>.
        UserDefaults.standard.set("\(base)/github", forKey: "githubAPIBase")
        // Reloading replaces earlier demo projects (e.g. ones pointing at an old address).
        let existing = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        for p in existing where projects.contains(where: { p.name == $0.name && p.endpoint.hasSuffix("/projects/\($0.slug)/metrics") }) {
            for m in p.milestones ?? [] { Notifier.cancel(m) }
            Keychain.delete(p.id.uuidString)
            context.delete(p)
        }
        for spec in projects {
            let p = Project(name: spec.name, accentHex: spec.accent,
                            startDate: Date.now.startOfDay.adding(days: -spec.startedDaysAgo),
                            buildDays: profile.buildDays, observeDays: profile.observeDays)
            if let img = spec.cover, let data = ImageTools.squareJPEG(img, side: 600) {
                p.coverImage = data
                p.accentHex = ImageTools.dominantAccentHex(UIImage(data: data)!) ?? spec.accent
            }
            p.details = spec.details
            p.githubRepo = spec.githubRepo
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

    /// Generated artwork for exercising color extraction in tests.
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
