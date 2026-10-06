import SwiftUI
import SwiftData

/// On the project screen: the targets, how close the numbers are, and the call once the observe phase ends.
struct SuccessCard: View {
    @Bindable var project: Project
    var onSetTargets: () -> Void
    var onDecide: () -> Void
    var onUndo: () -> Void
    @Environment(DataRefresher.self) private var refresher
    @Environment(\.accent) private var accent

    var body: some View {
        let results = VerdictEngine.results(project, refresher: refresher)
        let due = VerdictEngine.isDue(project)
        VStack(alignment: .leading, spacing: 14) {
            if due {
                HStack(spacing: 10) {
                    Image(systemName: "scalemass.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(accent.on)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(accent.base))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Decision time").display(20, 750).foregroundStyle(Theme.ink)
                        Text("The observe phase is over. Keep it, pivot it or kill it?")
                            .font(.ui(13)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Success looks like").display(20, 750).foregroundStyle(Theme.ink)
                    Spacer()
                    if project.verdict != .pivot && project.verdict != .kill {
                        Button(project.criteria.isEmpty ? "Set" : "Edit", action: onSetTargets)
                            .font(.ui(14, .semibold)).foregroundStyle(accent.text)
                    }
                }
            }

            if results.isEmpty {
                Text("Pick 1–3 targets, like 1,000 visitors or $200 revenue. When the observe phase ends, Prodline checks them and suggests whether to keep, pivot or kill.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !due {
                    Button("Set targets", action: onSetTargets).buttonStyle(.chunky(.neutral, height: 46))
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(results) { r in CriterionRow(result: r) }
                }
            }

            if let v = project.verdict, !due {
                verdictLine(v)
            }
            if due {
                Button("Make the call", action: onDecide).buttonStyle(.chunky(.accent, height: 50))
            } else if VerdictEngine.canDecide(project) {
                Button("Decide early", action: onDecide)
                    .font(.ui(14, .semibold)).foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .card()
    }

    @ViewBuilder
    private func verdictLine(_ v: Verdict) -> some View {
        let color = Accent(hex: v.hex)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(v.pastTense, systemImage: v.symbol)
                    .font(.ui(13, .bold))
                    .foregroundStyle(color.on)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(color.base))
                if let at = project.verdictAt {
                    Text(v == .keep ? "\(at.dayMonth) · next call \(project.observeEnd.dayMonth)" : at.dayMonth)
                        .font(.ui(13)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                if v != .keep {
                    Button("Undo", action: onUndo).font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                }
            }
            if !project.verdictNote.isEmpty {
                Text(project.verdictNote).font(.ui(14)).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}

struct CriterionRow: View {
    let result: VerdictEngine.Result
    @Environment(\.accent) private var accent

    var body: some View {
        let key = result.criterion.key
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(VerdictEngine.title(key)).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(VerdictEngine.format(key, result.actual)) of \(VerdictEngine.format(key, result.criterion.target))")
                    .font(.ui(14, .medium)).monospacedDigit()
                    .foregroundStyle(result.hit ? Theme.ink : Theme.secondary)
                if result.hit {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.success)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.background)
                    Capsule().fill(result.hit ? Theme.success : accent.base)
                        .frame(width: max(10, geo.size.width * result.progress))
                }
            }
            .frame(height: 10)
        }
    }
}

// MARK: - Targets

struct CriteriaSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @State private var rows: [SuccessCriterion] = []
    @State private var texts: [UUID: String] = [:]
    @FocusState private var focus: UUID?

    private var keys: [String] { VerdictEngine.availableKeys(project, refresher: refresher) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Success looks like").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Set the numbers that would make \(project.name) worth keeping. Ambitious but honest beats wishful.")
                        .font(.ui(15)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach($rows) { $row in
                        HStack(spacing: 10) {
                            Menu {
                                ForEach(keys, id: \.self) { k in
                                    Button(VerdictEngine.title(k)) { row.key = k }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(VerdictEngine.title(row.key)).font(.ui(16, .semibold)).lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 14).frame(height: 52)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                            }
                            TextField("", text: Binding(get: { texts[row.id] ?? "" }, set: { texts[row.id] = $0 }),
                                      prompt: Text("Target").foregroundStyle(Theme.tertiary))
                                .keyboardType(.decimalPad)
                                .focused($focus, equals: row.id)
                                .inputField(focused: focus == row.id)
                            Button {
                                withAnimation(.snappy) { rows.removeAll { $0.id == row.id } }
                            } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 22)).foregroundStyle(Theme.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if rows.count < 3 {
                        Button {
                            let used = Set(rows.map(\.key))
                            let key = keys.first { !used.contains($0) } ?? MetricKey.visits.rawValue
                            withAnimation(.snappy) { rows.append(SuccessCriterion(key: key, target: 0)) }
                        } label: {
                            Label("Add target", systemImage: "plus")
                        }
                        .buttonStyle(.chunky(.neutral, height: 48))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
                Button("Save") {
                    project.criteria = rows.compactMap { r in
                        guard let v = Double((texts[r.id] ?? "").replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
                        return SuccessCriterion(id: r.id, key: r.key, target: v)
                    }
                    try? context.save()
                    Haptics.success()
                    dismiss()
                }
                .buttonStyle(.chunky)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            rows = project.criteria
            if rows.isEmpty { rows = [SuccessCriterion(key: MetricKey.visits.rawValue, target: 0)] }
            for r in rows where r.target > 0 {
                texts[r.id] = r.target == r.target.rounded() ? String(Int(r.target)) : String(r.target)
            }
        }
    }
}

// MARK: - The call

struct VerdictSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @State private var choice: Verdict?
    @State private var keepDays = 28
    @State private var newName = ""
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        let results = VerdictEngine.results(project, refresher: refresher)
        let suggestion = VerdictEngine.suggestion(results)
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name.uppercased()).eyebrow()
                    Text("Decision time").display(28, 800).foregroundStyle(Theme.ink)
                }
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scoreCard(results, suggestion: suggestion)
                    VStack(spacing: 10) {
                        ForEach(Verdict.allCases) { v in choiceCard(v, suggested: v == suggestion) }
                    }
                    if let choice { details(choice).transition(.opacity.combined(with: .move(edge: .top))) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: choice)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
                Button(confirmTitle) { confirm() }
                    .buttonStyle(.chunky(choice == nil ? .neutral : .accent))
                    .environment(\.accent, choice.map { Accent(hex: $0.hex) } ?? project.accent)
                    .disabled(choice == nil || (choice == .pivot && newName.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .onAppear {
            newName = project.name + " 2"
            choice = nil
        }
    }

    private var confirmTitle: String {
        switch choice {
        case .keep: "Keep it"
        case .pivot: "Start the pivot"
        case .kill: "Kill it"
        case nil: "Pick one"
        }
    }

    @ViewBuilder
    private func scoreCard(_ results: [VerdictEngine.Result], suggestion: Verdict?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if results.isEmpty {
                Text("No targets were set, so this one's on gut feeling. Here's where it ended up:")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(MetricKey.allCases) { k in
                    HStack {
                        Text(k.title).font(.ui(15)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(refresher.value(k, for: project).map(k.format) ?? "–").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    }
                }
            } else {
                let hits = results.filter(\.hit).count
                HStack(spacing: 14) {
                    Text("\(hits)/\(results.count)").display(34, 800).foregroundStyle(Theme.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("targets hit").font(.ui(14, .semibold)).foregroundStyle(Theme.secondary)
                        if let suggestion {
                            Text("Prodline says: \(suggestion.title.lowercased())").font(.ui(15, .bold))
                                .foregroundStyle(Accent(hex: suggestion.hex).text)
                        }
                    }
                }
                ForEach(results) { CriterionRow(result: $0) }
            }
        }
        .card()
    }

    private func choiceCard(_ v: Verdict, suggested: Bool) -> some View {
        let color = Accent(hex: v.hex)
        let selected = choice == v
        return Button {
            Haptics.select()
            choice = v
        } label: {
            HStack(spacing: 14) {
                Image(systemName: v.symbol).font(.system(size: 22, weight: .bold))
                    .foregroundStyle(selected ? color.on : color.base)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(selected ? color.base : color.tint))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(v.title).display(19, 750).foregroundStyle(Theme.ink)
                        if suggested {
                            Text("SUGGESTED").font(.ui(10, .bold)).tracking(0.6)
                                .foregroundStyle(color.text)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(color.tint))
                        }
                    }
                    Text(v.blurb).font(.ui(13)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? color.base : Theme.line, lineWidth: selected ? 2.5 : 1.5))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }

    @ViewBuilder
    private func details(_ v: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch v {
            case .keep:
                Text("Watch it for").eyebrow()
                HStack(spacing: 8) {
                    ForEach(VerdictEngine.keepDays, id: \.self) { d in
                        Chip(title: "\(d / 7) weeks", isOn: keepDays == d) { keepDays = d }
                    }
                }
                Text("Next call on \(Date.now.adding(days: keepDays).dayMonth).").font(.ui(13)).foregroundStyle(Theme.secondary)
            case .pivot:
                Text("New project").eyebrow()
                TextField("", text: $newName, prompt: Text("Name").foregroundStyle(Theme.tertiary))
                    .inputField()
                Text("What changes?").eyebrow().padding(.top, 4)
                TextField("", text: $note, prompt: Text("Different audience, smaller scope, new pricing…").foregroundStyle(Theme.tertiary), axis: .vertical)
                    .lineLimit(2...4)
                    .focused($noteFocused)
                    .inputField(focused: noteFocused)
                Text("It starts building today with the same look, repo and integrations. \(project.name) is closed as pivoted.")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .kill:
                Text("What did it teach you?").eyebrow()
                TextField("", text: $note, prompt: Text("One line for future you").foregroundStyle(Theme.tertiary), axis: .vertical)
                    .lineLimit(2...4)
                    .focused($noteFocused)
                    .inputField(focused: noteFocused)
                Text("Killing a project on time is a skill. It stays in your history with its numbers.")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func confirm() {
        guard let choice, let profile = profiles.first else { return }
        let lesson = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = Accent(hex: choice.hex)
        switch choice {
        case .keep:
            VerdictEngine.keep(project, days: keepDays, profile: profile)
            celebration.fire(title: "Kept · +\(VerdictEngine.xp) XP", subtitle: "\(project.name) earned another \(keepDays / 7) weeks", accent: color)
        case .pivot:
            let next = VerdictEngine.pivot(project, newName: newName.trimmingCharacters(in: .whitespaces), note: lesson,
                                           profile: profile, context: context)
            celebration.fire(title: "Pivot · +\(VerdictEngine.xp) XP", subtitle: "\(next.name) starts building today", accent: color)
        case .kill:
            VerdictEngine.kill(project, lesson: lesson, profile: profile)
            celebration.fire(title: "Killed · +\(VerdictEngine.xp) XP", subtitle: "Brave call. Your time is free again.", accent: color, confetti: false)
        }
        if profile.remindersEnabled { Notifier.scheduleVerdict(project, hour: profile.reminderHour) }
        try? context.save()
        dismiss()
    }
}
