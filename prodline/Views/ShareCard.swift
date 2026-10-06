import SwiftUI

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
    case photo, color, light
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// The card itself: 360×450 points, rendered at 3× (1080×1350, a 4:5 post). Built like the Dash cards:
/// artwork on top melting into the accent (color fade plus progressive blur), the numbers on the accent slab.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)
    static let inset: CGFloat = 24
    let data: ShareCardData
    let stats: [ShareStat]
    let style: ShareCardStyle

    private var w: CGFloat { Self.size.width }
    /// Artwork height; its lower part fades into the slab.
    private var art: CGFloat { 270 }
    private var light: Bool { style == .light }
    /// Text on the slab.
    private var ink: Color { light ? Theme.ink : data.accent.on }
    private var soft: Color { light ? Theme.secondary : data.accent.on.opacity(0.75) }
    private var showsPhoto: Bool { style == .photo && data.cover != nil }

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
                .shadow(color: .black.opacity(showsPhoto ? 0.18 : 0), radius: 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(data.values[s] ?? "–").display(23, 800).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                            Text(s.label).font(.ui(12, .semibold)).foregroundStyle(soft).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(light ? Theme.background : Color.white.opacity(0.18)))
                    }
                }
                HStack(spacing: 6) {
                    Image("Mark").resizable().renderingMode(.template).scaledToFit().frame(width: 13, height: 13)
                    Text("Built with Prodline").font(.ui(11, .bold))
                    Spacer()
                    Text(Date.now.formatted(.dateTime.month(.abbreviated).day().year())).font(.ui(11, .semibold))
                }
                .foregroundStyle(soft)
            }
            .padding(.horizontal, Self.inset)
            .padding(.bottom, 20)
            .frame(width: w, height: Self.size.height, alignment: .bottomLeading)
        }
        .frame(width: w, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    /// Badge, name and status, top left. On photos they get a soft blur behind them and a shadow.
    private var header: some View {
        let onPhoto = showsPhoto
        let textColor: Color = onPhoto || style == .color ? .white : Theme.ink
        return HStack(spacing: 10) {
            Text(data.initial).display(19, 800).foregroundStyle(data.accent.on)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(data.accent.base))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(data.name).display(22, 800).foregroundStyle(style == .color ? data.accent.on : textColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(data.status.uppercased()).font(.ui(10, .bold)).tracking(1.2)
                    .foregroundStyle((style == .color ? data.accent.on : textColor).opacity(0.8))
            }
        }
        .shadow(color: .black.opacity(onPhoto ? 0.45 : 0), radius: 1.5, y: 0.5)
        .shadow(color: .black.opacity(onPhoto ? 0.3 : 0), radius: 10)
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
            LinearGradient(colors: [data.accent.base, data.accent.dark], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .light:
            ZStack(alignment: .topTrailing) {
                Color.white
                Circle().fill(data.accent.base.opacity(0.14)).frame(width: 300).offset(x: 110, y: -130)
            }
        }
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
                        .mask(LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
                }
                .overlay {
                    photo.blur(radius: 14)
                        .mask(RadialGradient(colors: [.black, .black.opacity(0.6), .clear], center: .topLeading,
                                             startRadius: 0, endRadius: 210))
                }
                .overlay {
                    LinearGradient(stops: [.init(color: data.accent.base.opacity(0), location: 0.42),
                                           .init(color: data.accent.base.opacity(0.35), location: 0.66),
                                           .init(color: data.accent.base.opacity(0.8), location: 0.84),
                                           .init(color: data.accent.base, location: 0.97)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: art * 0.4)
                }
                .frame(width: w, height: art)
        } else {
            data.accent.base
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
                        GeometryReader { geo in
                            let scale = min(1, geo.size.width / ShareCardView.size.width)
                            ShareCardView(data: data, stats: picks, style: style)
                                .scaleEffect(scale, anchor: .top)
                                .frame(width: geo.size.width, alignment: .center)
                                .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
                        }
                        .frame(height: ShareCardView.size.height)
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
                    ShareLink(item: Image(uiImage: image), preview: SharePreview(project.name, image: Image(uiImage: image))) {
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
