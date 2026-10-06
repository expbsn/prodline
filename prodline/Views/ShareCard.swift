import SwiftUI
import UniformTypeIdentifiers

/// One number on a share card.
enum ShareStat: String, CaseIterable, Identifiable {
    case activeDays, commits, goals, checkpoints, visits, socialViews, revenue, downloads, mrr

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeDays: "active days"
        case .commits: "commits"
        case .goals: "goals done"
        case .checkpoints: "checkpoints"
        case .visits: "visits"
        case .socialViews: "social views"
        case .revenue: "revenue"
        case .downloads: "downloads"
        case .mrr: "MRR"
        }
    }

    var chip: String {
        switch self {
        case .activeDays: "Active days"
        case .commits: "Commits"
        case .goals: "Goals"
        case .checkpoints: "Checkpoints"
        case .visits: "Visits"
        case .socialViews: "Social views"
        case .revenue: "Revenue"
        case .downloads: "Downloads"
        case .mrr: "MRR"
        }
    }
}

/// Everything a card shows, gathered once so the view stays a plain drawing.
struct ShareCardData {
    var name: String
    var initial: String
    var accent: Accent
    var cover: UIImage?
    var status: String
    var days: Int
    var values: [ShareStat: String]

    /// Stats this project actually has.
    var available: [ShareStat] { ShareStat.allCases.filter { values[$0] != nil } }

    @MainActor
    static func make(_ p: Project, refresher: DataRefresher, now: Date = .now) -> ShareCardData {
        let end = min(now, p.observeEnd.adding(days: -1))
        let days = max(1, Date.days(from: p.startDate, to: end) + 1)
        let momentum = Momentum.make(project: p, now: now)
        var v: [ShareStat: String] = [:]
        if momentum.activeDays > 0 { v[.activeDays] = "\(momentum.activeDays)" }
        if momentum.hasCommitData { v[.commits] = MetricKey.count(Double(momentum.totalCommits)) }
        let goals = p.sortedMilestones.flatMap { $0.goals ?? [] }
        if !goals.isEmpty { v[.goals] = "\(goals.filter(\.isDone).count)" }
        let ms = p.sortedMilestones
        if !ms.isEmpty { v[.checkpoints] = "\(ms.filter(\.isDone).count)/\(ms.count)" }
        if p.phase(on: now) != .building && p.phase(on: now) != .upcoming || p.hasDataSource {
            for (stat, key) in [(ShareStat.visits, MetricKey.visits), (.socialViews, .socialViews), (.revenue, .revenue)] {
                if let x = refresher.value(key, for: p), x > 0 { v[stat] = key.format(x) }
            }
        }
        let extras = Dictionary(uniqueKeysWithValues: refresher.extras(for: p).map { ($0.key, $0.value) })
        if let d = extras["downloads"], d > 0 { v[.downloads] = MetricKey.count(d) }
        if let m = extras["mrr"], m > 0 { v[.mrr] = MetricKey.money(m) }

        let status: String
        switch (p.verdict, p.phase(on: now)) {
        case (.pivot?, _): status = "Pivoted"
        case (.kill?, _): status = "Retired"
        case (_, .upcoming): status = "Starting \(p.startDate.dayMonth)"
        case (_, .building): status = "Day \(p.dayInPhase) of building"
        case (_, .observing): status = "Shipped \(p.launchDay.dayMonth)"
        case (_, .finished): status = "Shipped and measured"
        }
        return ShareCardData(name: p.name, initial: p.initial, accent: p.accent, cover: p.cover, status: status, days: days, values: v)
    }

    /// Building: effort. Shipped: results.
    func defaultPicks(shipped: Bool) -> [ShareStat] {
        let order: [ShareStat] = shipped
            ? [.revenue, .visits, .downloads, .mrr, .socialViews, .activeDays, .checkpoints]
            : [.activeDays, .commits, .goals, .checkpoints, .visits, .revenue]
        return Array(order.filter { values[$0] != nil }.prefix(4))
    }
}

enum ShareCardStyle: String, CaseIterable, Identifiable {
    case photo, color, light, transparent
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The card itself, rendered at 3×. Built like the Dash cards: the square artwork fills the full width on
/// top and melts into the accent (color fade plus progressive blur); the numbers sit on the slab below.
/// 360×540 points (1080×1620). The transparent style is a sticker for your own photos: just the text.
struct ShareCardView: View {
    static let width: CGFloat = 360
    static let inset: CGFloat = 24
    static func size(_ style: ShareCardStyle) -> CGSize {
        CGSize(width: width, height: style == .transparent ? 356 : 540)
    }

    let data: ShareCardData
    let stats: [ShareStat]
    let style: ShareCardStyle

    private var w: CGFloat { Self.width }
    private var h: CGFloat { Self.size(style).height }
    /// The artwork is square, as wide as the card.
    private var art: CGFloat { w }
    private var light: Bool { style == .light }
    private var clear: Bool { style == .transparent }
    /// Text on the slab.
    private var ink: Color { light ? Theme.ink : clear ? .white : data.accent.on }
    private var soft: Color { light ? Theme.secondary : clear ? .white.opacity(0.85) : data.accent.on.opacity(0.75) }
    private var showsPhoto: Bool { style == .photo && data.cover != nil }
    /// Text that can land on a busy background gets a shadow.
    private var shadowed: Bool { showsPhoto || clear }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            header
                .padding(Self.inset)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text("\(data.days)").display(76, 850).foregroundStyle(ink).lineLimit(1)
                    Text(data.days == 1 ? "day spent" : "days spent").font(.ui(18, .bold)).foregroundStyle(ink.opacity(light ? 0.6 : 0.92))
                    Spacer(minLength: 0)
                }
                .shadow(color: .black.opacity(clear ? 0.35 : showsPhoto ? 0.18 : 0), radius: clear ? 6 : 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.values[s] ?? "–").display(23, 800).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                            Text(s.label).font(.ui(12, .semibold)).foregroundStyle(soft).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(tile)
                        .shadow(color: .black.opacity(clear ? 0.35 : 0), radius: 4)
                    }
                }
                HStack(spacing: 6) {
                    Image("Mark").resizable().renderingMode(.template).scaledToFit().frame(width: 13, height: 13)
                    Text("Built with Prodline").font(.ui(11, .bold))
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.abbreviated).day().year())).font(.ui(11, .semibold))
                }
                .foregroundStyle(soft)
                .shadow(color: .black.opacity(clear ? 0.35 : 0), radius: 4)
            }
            .padding(.horizontal, Self.inset)
            .padding(.bottom, 20)
            .frame(width: w, height: h, alignment: .bottomLeading)
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: clear ? 0 : 30, style: .continuous))
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if clear {
            shape.fill(.white.opacity(0.12)).overlay(shape.strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
        } else {
            shape.fill(light ? Theme.background : Color.white.opacity(0.18))
        }
    }

    /// Badge, name and status, top left. On photos they get a soft blur behind them and a shadow.
    private var header: some View {
        let textColor: Color = light ? Theme.ink : style == .color ? data.accent.on : .white
        return HStack(spacing: 10) {
            Text(data.initial).display(19, 800).foregroundStyle(data.accent.on)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(data.accent.base))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(data.name).display(22, 800).foregroundStyle(textColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(data.status.uppercased()).font(.ui(10, .bold)).tracking(1.2)
                    .foregroundStyle(textColor.opacity(0.8))
            }
        }
        .shadow(color: .black.opacity(shadowed ? 0.45 : 0), radius: 1.5, y: 0.5)
        .shadow(color: .black.opacity(shadowed ? 0.3 : 0), radius: 10)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .photo:
            ZStack(alignment: .top) {
                data.accent.base
                artwork
            }
        case .color:
            ZStack(alignment: .top) {
                LinearGradient(colors: [data.accent.base, data.accent.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
                letter(data.accent.on.opacity(0.12))
            }
        case .light:
            ZStack(alignment: .top) {
                Color.white
                LinearGradient(colors: [.white, data.accent.base.opacity(0.12), data.accent.base.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                letter(data.accent.base.opacity(0.12))
            }
        case .transparent:
            Color.clear
        }
    }

    /// The big faint initial the Dash cards show when there's no photo, filling the square.
    private func letter(_ color: Color) -> some View {
        Text(data.initial).display(400, 900).foregroundStyle(color)
            .frame(width: w, height: art, alignment: .topTrailing)
            .offset(x: 40, y: -30)
            .clipped()
    }

    /// Same recipe as the Dash card: the photo, a blurred copy revealed toward the bottom, an eased fade
    /// into the accent, and here also a blurred top-left corner under the header.
    @ViewBuilder
    private var artwork: some View {
        if let cover = data.cover {
            let photo = Image(uiImage: cover).resizable().scaledToFill().frame(width: w, height: art).clipped()
            photo
                .overlay {
                    photo.blur(radius: 18)
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.42), .init(color: .black, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    photo.blur(radius: 14)
                        .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear], center: .topLeading,
                                             startRadius: 0, endRadius: 210))
                }
                .overlay {
                    LinearGradient(stops: [.init(color: data.accent.base.opacity(0), location: 0.42),
                                           .init(color: data.accent.base.opacity(0.35), location: 0.68),
                                           .init(color: data.accent.base.opacity(0.8), location: 0.84),
                                           .init(color: data.accent.base, location: 0.96)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: art * 0.4)
                }
                .padding(.bottom, 1)
                .frame(width: w, height: art)
        } else {
            data.accent.base
        }
    }
}

/// Exports as PNG so the transparent card keeps its transparency.
struct PNGImage: Transferable {
    let image: UIImage
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
    }
}

/// Dark checkerboard: the usual "this is transparent" backdrop, dark so the white sticker stays readable.
struct Checkerboard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 14
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x2C2C2E)))
            for row in 0..<Int(size.height / cell) + 1 {
                for col in 0..<Int(size.width / cell) + 1 where (row + col) % 2 == 0 {
                    ctx.fill(Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                             with: .color(Color(hex: 0x3A3A3C)))
                }
            }
        }
    }
}

struct ShareCardSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(DataRefresher.self) private var refresher
    @State private var data: ShareCardData?
    @State private var picks: [ShareStat] = []
    @State private var style: ShareCardStyle = .photo
    @State private var image: UIImage?
    /// The card is designed at full size; the preview shows it a little smaller so the options fit.
    static let previewScale: CGFloat = 0.8

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Share card").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let data {
                        let size = ShareCardView.size(style)
                        ShareCardView(data: data, stats: picks, style: style)
                            .background {
                                if style == .transparent { Checkerboard() }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
                            .scaleEffect(Self.previewScale, anchor: .top)
                            .frame(width: size.width * Self.previewScale, height: size.height * Self.previewScale, alignment: .top)
                            .frame(maxWidth: .infinity)
                        .animation(.snappy, value: style)
                        .animation(.snappy, value: picks)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Style").eyebrow()
                            HStack(spacing: 6) {
                                ForEach(ShareCardStyle.allCases.filter { $0 != .photo || data.cover != nil }) { s in
                                    Chip(title: s.title, isOn: style == s) { style = s }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Numbers · up to 4").eyebrow()
                            FlowChips(items: data.available, selected: picks) { s in toggle(s) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .bottomActionBar {
                if let image {
                    ShareLink(item: PNGImage(image: image), preview: SharePreview(project.name, image: Image(uiImage: image))) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.chunky)
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            let d = ShareCardData.make(project, refresher: refresher)
            data = d
            let shipped = project.phase() == .observing || project.phase() == .finished
            picks = d.defaultPicks(shipped: shipped)
            style = d.cover != nil ? .photo : .color
            render()
        }
        .onChange(of: style) { render() }
        .onChange(of: picks) { render() }
    }

    private func toggle(_ s: ShareStat) {
        Haptics.select()
        if let i = picks.firstIndex(of: s) { picks.remove(at: i) }
        else if picks.count < 4 { picks.append(s) }
    }

    private func render() {
        guard let data else { return }
        let renderer = ImageRenderer(content: ShareCardView(data: data, stats: picks, style: style))
        renderer.scale = 3
        renderer.isOpaque = false
        image = renderer.uiImage
    }
}

/// Wrapping row of toggle chips.
struct FlowChips: View {
    let items: [ShareStat]
    let selected: [ShareStat]
    var onTap: (ShareStat) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items) { s in
                Chip(title: s.chip, isOn: selected.contains(s)) { onTap(s) }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
