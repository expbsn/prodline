import SwiftUI
import Charts

/// The project's numbers while it's being built: commits, goals done and active days.
struct MomentumCard: View {
    let project: Project
    var onConnect: () -> Void = {}
    @Environment(\.accent) private var accent
    @State private var stat: Stat = .commits

    enum Stat: CaseIterable { case commits, goals, active }

    var body: some View {
        let m = Momentum.make(project: project)
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Momentum").display(24, 700).foregroundStyle(Theme.ink)
                Spacer()
                Text("Day \(m.elapsedDays) of \(m.buildLength)").eyebrow(size: 10)
            }
            HStack(spacing: 8) {
                tile(.commits, symbol: "chevron.left.forwardslash.chevron.right",
                     value: m.hasCommitData ? "\(m.totalCommits)" : "–", label: "Commits")
                tile(.goals, symbol: "checkmark.circle.fill",
                     value: "\(m.goalsDone)/\(m.goalsTotal)", label: "Goals done")
                tile(.active, symbol: "flame.fill",
                     value: m.hasCommitData ? "\(m.activeDays)/\(m.elapsedDays)" : "–", label: "Active days")
            }
            chart(m)
                .frame(height: 150)
                .animation(.snappy, value: stat)
            Text(caption(m)).font(.ui(13)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !m.hasCommitData && stat != .goals {
                Button(action: onConnect) {
                    Label("Link the GitHub repo to count commits", systemImage: "link")
                        .font(.ui(14, .semibold)).foregroundStyle(accent.text)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func tile(_ s: Stat, symbol: String, value: String, label: String) -> some View {
        let selected = stat == s
        return Button {
            Haptics.select()
            withAnimation(.snappy) { stat = s }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(value).display(22, 700).lineLimit(1).minimumScaleFactor(0.6).contentTransition(.numericText())
                Text(label).font(.ui(11, .semibold)).opacity(0.75).lineLimit(1)
            }
            .foregroundStyle(selected ? accent.on : Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(selected ? accent.base : Theme.background))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
    }

    @ViewBuilder
    private func chart(_ m: Momentum) -> some View {
        switch stat {
        case .commits:
            Chart(m.days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Commits", d.commits))
                    .foregroundStyle(Calendar.current.isDateInToday(d.date) ? accent.base : accent.base.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .chartXScale(domain: project.startDate...project.buildEnd)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(1, m.buildLength / 4))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            } }
            .opacity(m.hasCommitData ? 1 : 0.25)
        case .goals:
            Chart(m.days) { d in
                AreaMark(x: .value("Day", d.date, unit: .day), y: .value("Goals done", d.goalsDone))
                    .foregroundStyle(LinearGradient(colors: [accent.base.opacity(0.3), accent.base.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.stepEnd)
                LineMark(x: .value("Day", d.date, unit: .day), y: .value("Goals done", d.goalsDone))
                    .foregroundStyle(accent.base)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.stepEnd)
            }
            .chartXScale(domain: project.startDate...project.buildEnd)
            .chartYScale(domain: 0...max(1, m.goalsTotal))
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: max(1, m.buildLength / 4))) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            } }
        case .active:
            activeStrip(m)
        }
    }

    /// One dot per build day: filled when something was committed, outlined for days still ahead.
    private func activeStrip(_ m: Momentum) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0..<m.buildLength, id: \.self) { i in
                let day = m.days[safe: i]
                ZStack {
                    if let day {
                        Circle().fill(day.isActive ? accent.base : Theme.line)
                        if Calendar.current.isDateInToday(day.date) {
                            Circle().strokeBorder(Theme.ink, lineWidth: 2)
                        }
                    } else {
                        Circle().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
                .frame(width: 22, height: 22)
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(m.hasCommitData ? 1 : 0.35)
    }

    private func caption(_ m: Momentum) -> String {
        switch stat {
        case .commits:
            guard m.hasCommitData else { return "Commits per day while building." }
            return m.commitsToday > 0
                ? "\(m.commitsToday) commit\(m.commitsToday == 1 ? "" : "s") today. Keep it moving."
                : "Nothing committed yet today."
        case .goals:
            let left = m.goalsTotal - m.goalsDone
            return m.goalsTotal == 0 ? "Add goals to your checkpoints to see them here."
                : left == 0 ? "Every goal of the build is done." : "\(left) goal\(left == 1 ? "" : "s") left before launch."
        case .active:
            guard m.hasCommitData else { return "Days with at least one commit." }
            return "Days with at least one commit. Small daily steps beat one big push."
        }
    }
}
