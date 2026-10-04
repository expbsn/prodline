import SwiftUI
import UIKit

/// Playing-card (5:7) face for a project. Used in the carousel, the create flow preview and the detail hero,
/// so a project always looks the same everywhere.
struct ProjectCardFace: View {
    let name: String
    let initial: String
    let accent: Accent
    let cover: UIImage?
    var cornerLabel: String = ""
    var cornerValue: String = ""
    var footnote: String = ""

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let s = w / 260
            // Small cards drop the tiny labels so they stay legible.
            let compact = w < 200

            ZStack(alignment: .topLeading) {
                background(w: w, h: h, s: s)

                // Top row: badge + corner stat.
                HStack(alignment: .top) {
                    Text(initial)
                        .display(24 * s, 800)
                        .foregroundStyle(accent.on)
                        .frame(width: 46 * s, height: 46 * s)
                        .background(RoundedRectangle(cornerRadius: 13 * s, style: .continuous).fill(accent.base))
                        .overlay(RoundedRectangle(cornerRadius: 13 * s, style: .continuous)
                            .strokeBorder(.white.opacity(0.35), lineWidth: 1.5 * s))
                        .shadow(color: accent.dark.opacity(0.35), radius: 4 * s, y: 2 * s)
                    Spacer()
                    if !cornerValue.isEmpty {
                        VStack(alignment: .trailing, spacing: 0) {
                            if !compact {
                                Text(cornerLabel)
                                    .font(.ui(11 * s, .semibold)).tracking(2.2 * s).textCase(.uppercase)
                                    .foregroundStyle(cover == nil ? Theme.secondary : .white.opacity(0.85))
                            }
                            Text(cornerValue)
                                .display(38 * s, 700)
                                .foregroundStyle(cover == nil ? Theme.ink : .white)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .padding(20 * s)

                // Name on the slab; the footnote hugs the name, long names shrink instead of growing upward.
                VStack(alignment: .leading, spacing: 4 * s) {
                    if !footnote.isEmpty && !compact {
                        Text(footnote)
                            .font(.ui(11 * s, .semibold)).tracking(1.8 * s).textCase(.uppercase)
                            .foregroundStyle(accent.on.opacity(0.8))
                    }
                    Text(name.isEmpty ? "Untitled" : name)
                        .display(46 * s, 800)
                        .foregroundStyle(accent.on)
                        .lineLimit(2)
                        .minimumScaleFactor(0.4)
                }
                .frame(maxWidth: .infinity, maxHeight: h * 0.27, alignment: .bottomLeading)
                .padding(.horizontal, 22 * s)
                .padding(.bottom, 22 * s)
                .frame(width: w, height: h, alignment: .bottomLeading)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 30 * s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30 * s, style: .continuous)
                .strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
        }
        .aspectRatio(5 / 7, contentMode: .fit)
    }

    /// Square artwork on top (the cover, or a tinted letter), melting into the accent below:
    /// the lower part of the square fades to the accent color and blurs progressively.
    private func background(w: CGFloat, h: CGFloat, s: CGFloat) -> some View {
        let fadeStart = 0.42 // of the square
        let fade = LinearGradient(stops: [.init(color: .clear, location: fadeStart),
                                          .init(color: .black, location: 1)],
                                  startPoint: .top, endPoint: .bottom)
        return ZStack(alignment: .top) {
            accent.base

            artwork(w: w, s: s)
                .frame(width: w, height: w)
                .clipped()
                // Covered by solid accent before the edge, so no anti-aliased seam shows below the square.
                .padding(.bottom, 1)
                // Progressive blur on photos: a blurred copy revealed toward the bottom of the square.
                .overlay {
                    if let cover {
                        Image(uiImage: cover).resizable().scaledToFill()
                            .frame(width: w, height: w)
                            .clipped()
                            .blur(radius: 16 * s)
                            .mask(fade)
                    }
                }
                // Color fade into the accent, eased so there's no visible edge.
                .overlay {
                    LinearGradient(stops: [.init(color: accent.base.opacity(0), location: fadeStart),
                                           .init(color: accent.base.opacity(0.35), location: 0.68),
                                           .init(color: accent.base.opacity(0.8), location: 0.84),
                                           .init(color: accent.base, location: 0.96)],
                                   startPoint: .top, endPoint: .bottom)
                }
                // Keeps the corner stat readable on photos.
                .overlay(alignment: .top) {
                    if cover != nil {
                        LinearGradient(colors: [.black.opacity(0.32), .clear], startPoint: .top, endPoint: .center)
                            .frame(height: w * 0.4)
                    }
                }
        }
        .frame(width: w, height: h, alignment: .top)
    }

    @ViewBuilder
    private func artwork(w: CGFloat, s: CGFloat) -> some View {
        if let cover {
            Image(uiImage: cover).resizable().scaledToFill()
        } else {
            ZStack(alignment: .topTrailing) {
                Color.white
                LinearGradient(colors: [.white, accent.base.opacity(0.12), accent.base.opacity(0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [accent.base.opacity(0.2), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: w * 0.9)
                Text(initial)
                    .display(300 * s, 900)
                    .foregroundStyle(accent.base.opacity(0.12))
                    .offset(x: 30 * s, y: -10 * s)
            }
        }
    }
}

extension ProjectCardFace {
    init(project: Project, refresher: DataRefresher?) {
        let phase = project.phase()
        var label = "", value = "", foot = ""
        switch phase {
        case .upcoming:
            label = "Starts in"; value = project.daysLeftInPhase.shortDuration
            foot = "Starts \(project.startDate.dayMonth)"
        case .building:
            label = "Day"; value = "\(project.dayInPhase)"
            foot = "Building · \(project.daysLeftInPhase)d left"
        case .observing:
            label = "Visits"
            value = refresher?.value(.visits, for: project).map(MetricKey.count) ?? "–"
            foot = "Observing · day \(project.dayInPhase)"
        case .finished:
            label = "Revenue"
            value = refresher?.value(.revenue, for: project).map(MetricKey.money) ?? "–"
            foot = "Finished"
        }
        self.init(name: project.name, initial: project.initial, accent: project.accent, cover: project.cover,
                  cornerLabel: label, cornerValue: value, footnote: foot)
    }
}

/// The "add" card at the end of the carousel.
struct CreateProjectCardFace: View {
    var subtitle: String

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 260
            VStack(alignment: .leading, spacing: 10 * s) {
                Image(systemName: "plus")
                    .font(.system(size: 30 * s, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64 * s, height: 64 * s)
                    .background(Circle().fill(Theme.ink))
                Spacer()
                Text("New\nproject")
                    .display(48 * s, 800)
                .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.ui(14 * s, .medium))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(24 * s)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 30 * s, style: .continuous).fill(.white))
            .overlay(
                RoundedRectangle(cornerRadius: 30 * s, style: .continuous)
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                    .padding(8 * s)
            )
        }
        .aspectRatio(5 / 7, contentMode: .fit)
    }
}

/// Small square project mark (cover or letter) for rows.
struct ProjectThumb: View {
    let project: Project
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let cover = project.cover {
                Image(uiImage: cover).resizable().scaledToFill()
            } else {
                Text(project.initial)
                    .display(size * 0.5, 800)
                    .foregroundStyle(project.accent.on)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(project.accent.base)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

extension View {
    /// A soft, detached floor shadow, as if the card hovers above the page.
    func cardFloorShadow(width: CGFloat, strength: Double = 1) -> some View {
        background(alignment: .bottom) {
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.3 * strength), .black.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: width * 0.62))
                .frame(width: width * 1.3, height: width * 0.22)
                .blur(radius: width * 0.05)
                .offset(y: width * 0.2)
                .allowsHitTesting(false)
        }
    }
}
