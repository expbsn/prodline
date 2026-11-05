import SwiftUI

/// The stages of a plan as editable cards: name, length, and whether it ends with the keep, pivot or kill
/// call. Used by the create flow, a project's edit sheet and the template on Me.
struct StageListEditor: View {
    @Binding var stages: [Stage]
    /// The plan's first day, for dates under each stage; nil for the template.
    var start: Date? = nil
    /// Spans of a running project: finished stages are locked, the current one is marked.
    var spans: [StageSpan] = []
    @Environment(\.accent) private var accent
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { i, stage in
                if stage.finishedAt != nil {
                    finishedRow(stage)
                } else {
                    row(i)
                }
            }
            Button {
                Haptics.select()
                let new = Stage(name: "", days: 7)
                withAnimation(.snappy) { stages.append(new) }
                focused = new.id
            } label: {
                Label("Add stage", systemImage: "plus.circle.fill")
                    .font(.ui(15, .semibold)).foregroundStyle(accent.text)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }

    private func dates(_ i: Int) -> String? {
        if let span = spans[safe: i] { return span.dateRange }
        guard let start else { return nil }
        var cursor = start.startOfDay
        for s in stages.prefix(i) { cursor = cursor.adding(days: max(1, s.days)) }
        return StageSpan.range(cursor, cursor.adding(days: max(1, stages[i].days) - 1))
    }

    private func row(_ i: Int) -> some View {
        let stage = stages[i]
        let current = spans[safe: i]?.state == .current
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(i + 1)")
                    .font(.ui(13, .bold)).foregroundStyle(accent.on)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(accent.base))
                TextField("", text: Binding(get: { stages[safe: i]?.name ?? "" },
                                            set: { if stages.indices.contains(i) { stages[i].name = $0 } }),
                          prompt: Text("Stage name").foregroundStyle(Theme.tertiary))
                    .font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    .focused($focused, equals: stage.id)
                    .submitLabel(.done)
                Spacer(minLength: 4)
                if current {
                    Text("Now").font(.ui(12, .semibold)).foregroundStyle(accent.text)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(accent.soft))
                }
                menu(i)
            }
            HStack(alignment: .firstTextBaseline) {
                if let d = dates(i) { Text(d).font(.ui(13)).foregroundStyle(Theme.secondary) }
                Spacer()
                Text(stage.days.durationText).display(18, 700).foregroundStyle(accent.text)
                    .contentTransition(.numericText())
            }
            ChunkySlider(value: Binding(get: { stages[safe: i]?.days ?? 7 },
                                        set: { if stages.indices.contains(i) { stages[i].days = $0 } }),
                         range: 1...90)
            Toggle(isOn: Binding(get: { stages[safe: i]?.decides ?? false },
                                 set: { if stages.indices.contains(i) { stages[i].decides = $0 } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ends with a decision").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    Text("Keep, pivot or kill, judged on your numbers").font(.ui(13)).foregroundStyle(Theme.secondary)
                }
            }
            .tint(Theme.switchOn)
        }
        .card(padding: 16, radius: 22)
    }

    private func menu(_ i: Int) -> some View {
        let firstEditable = stages.firstIndex { $0.finishedAt == nil } ?? 0
        return Menu {
            Button { move(i, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                .disabled(i <= firstEditable)
            Button { move(i, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                .disabled(i >= stages.count - 1)
            Button(role: .destructive) {
                Haptics.warning()
                withAnimation(.snappy) { _ = stages.remove(at: i) }
            } label: { Label("Remove stage", systemImage: "trash") }
                .disabled(stages.count <= 1 || spans[safe: i]?.state == .current)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
    }

    private func move(_ i: Int, by d: Int) {
        let j = i + d
        guard stages.indices.contains(j) else { return }
        Haptics.select()
        withAnimation(.snappy) { stages.swapAt(i, j) }
    }

    private func finishedRow(_ stage: Stage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(accent.base)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.name).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Text("Done \(stage.finishedAt?.dayMonth ?? "")").font(.ui(13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .card(padding: 16, radius: 22)
    }
}

extension StageSpan {
    static func range(_ a: Date, _ b: Date) -> String { a == b ? a.dayMonth : "\(a.dayMonth) – \(b.dayMonth)" }
    /// "Nov 8 – Nov 21": as it went, or as planned from today.
    var dateRange: String { StageSpan.range(start, max(start, lastDay)) }
}

/// One bar per stage, as long as its days, with today's marker. Done stages full, the current one full up
/// to today, the rest pale; a stage that ends with the call carries a small fork.
struct StageTimelineBar: View {
    let spans: [StageSpan]
    var today: Date = .now
    var height: CGFloat = 16
    @Environment(\.accent) private var accent

    var body: some View {
        GeometryReader { geo in
            let total = Double(max(1, spans.map(\.length).reduce(0, +)))
            let gaps = CGFloat(max(0, spans.count - 1)) * 4
            let w = max(0, geo.size.width - gaps)
            HStack(spacing: 4) {
                ForEach(spans) { span in
                    let segment = w * CGFloat(Double(span.length) / total)
                    ZStack(alignment: .leading) {
                        Capsule().fill(accent.base.opacity(span.state == .done ? 1 : 0.28))
                        if span.state == .current {
                            let done = min(1, max(0, Double(span.day(on: today) - 1) / Double(span.length)))
                            Capsule().fill(span.daysOver(on: today) > 0 ? Theme.danger : accent.base)
                                .frame(width: max(height, segment * done))
                        }
                    }
                    .frame(width: max(height, segment), height: height)
                    .overlay(alignment: .trailing) {
                        if span.stage.decides {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: height * 0.55, weight: .bold))
                                .foregroundStyle(span.state == .done ? accent.on : accent.text)
                                .padding(.trailing, height * 0.3)
                        }
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// Stage names with their dates, one per line, the current one marked; for the timeline card and the overview.
struct StageLegend: View {
    let spans: [StageSpan]
    var checkpoints: [UUID: Int] = [:]
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(spans) { span in
                HStack(spacing: 10) {
                    Image(systemName: span.state == .done ? "checkmark.circle.fill" : span.state == .current ? "circle.inset.filled" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(span.state == .ahead ? Theme.tertiary : accent.text)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(span.stage.name.isEmpty ? "Stage \(span.index + 1)" : span.stage.name)
                                .font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                            if span.stage.decides {
                                Image(systemName: "arrow.triangle.branch").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.secondary)
                            }
                        }
                        Text(detail(span)).font(.ui(13)).foregroundStyle(span.daysOver() > 0 ? Theme.danger : Theme.secondary)
                    }
                    Spacer()
                    Text(span.stage.days.durationText).font(.ui(13, .medium)).foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func detail(_ span: StageSpan) -> String {
        var parts = [span.dateRange]
        if span.daysOver() > 0 { parts.append("\(span.daysOver())d over") }
        if let n = checkpoints[span.stage.id] { parts.append("\(n) checkpoint\(n == 1 ? "" : "s")") }
        if span.stage.decides { parts.append("ends with a decision") }
        return parts.joined(separator: " · ")
    }
}

extension Project {
    /// Spans for a plan that hasn't been saved: the create flow and the overview.
    static func previewSpans(_ stages: [Stage], start: Date) -> [StageSpan] {
        var cursor = start.startOfDay
        return stages.enumerated().map { i, s in
            let end = cursor.adding(days: max(1, s.days))
            defer { cursor = end }
            return StageSpan(index: i, stage: s, start: cursor, plannedEnd: end, end: end, state: .ahead)
        }
    }
}

/// Pinned to the bottom of a project: finish the current stage once everything in it is done (the next one
/// starts today), or make the call in a stage that ends with one. Nothing before the start or once done.
struct StageBar: View {
    let project: Project
    var onFinish: () -> Void
    var onDecide: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.wideLayout) private var wide

    var body: some View {
        if let span = project.currentSpan(), project.verdict != .kill, project.verdict != .pivot {
            let content = VStack(alignment: wide ? .trailing : .leading, spacing: 8) {
                if span.stage.decides {
                    Button("Make the call", action: onDecide)
                        .buttonStyle(.chunky(.accent, height: wide ? 44 : 54))
                } else {
                    Button(action: onFinish) {
                        Label(title(span), systemImage: StageEngine.canFinishStage(project) ? "checkmark" : "lock.fill")
                    }
                    .buttonStyle(.chunky(.accent, height: wide ? 44 : 54))
                    .disabled(!StageEngine.canFinishStage(project))
                }
                Text(note(span))
                    .font(.ui(13)).foregroundStyle(span.daysOver() > 0 ? Theme.danger : Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: wide ? .trailing : .leading)
                    .padding(.horizontal, 4)
            }
            if wide {
                VStack(spacing: 0) {
                    Divider()
                    HStack { Spacer(minLength: 0); content.frame(width: 300) }
                        .padding(.horizontal, 24).padding(.vertical, 14)
                }
                .background(Theme.background)
            } else {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .background {
                        LinearGradient(stops: [.init(color: Theme.background.opacity(0), location: 0),
                                               .init(color: Theme.background, location: 0.3)],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(.top, -24)
                            .ignoresSafeArea(edges: .bottom)
                    }
            }
        }
    }

    private func title(_ span: StageSpan) -> String {
        let name = span.stage.name
        guard let next = project.stages[safe: span.index + 1] else { return "Finish \(name)" }
        return "Finish \(name), start \(next.name)"
    }

    private func note(_ span: StageSpan) -> String {
        let over = span.daysOver()
        if span.stage.decides {
            if over > 0 { return "\(span.stage.name) is \(over) day\(over == 1 ? "" : "s") over: keep, pivot or kill" }
            return "\(span.stage.name) ends \(span.plannedLastDay.shortDay). Decide early if the numbers are clear."
        }
        if let left = StageEngine.remaining(project), !left.isEmpty {
            var s = "\(left.checkpoints) checkpoint\(left.checkpoints == 1 ? "" : "s") left in \(span.stage.name)"
            if left.goals > 0 { s += " · \(left.goals) open goal\(left.goals == 1 ? "" : "s")" }
            if over > 0 { s += " · \(over)d over" }
            return s
        }
        if over > 0 { return "Everything's done, \(over) day\(over == 1 ? "" : "s") over plan. Move on." }
        let early = Date.days(from: .now.startOfDay, to: span.plannedLastDay)
        return early > 0 ? "Everything's done, \(early) day\(early == 1 ? "" : "s") early." : "Everything's done. Time to move on."
    }
}
