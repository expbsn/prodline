import SwiftUI
import SwiftData

/// Plan tab: the parked ideas and how many build slots are free.
struct IdeaInboxCard: View {
    let profile: Profile
    var onOpen: () -> Void
    @Query(sort: \Idea.createdAt, order: .reverse) private var ideas: [Idea]
    @Query private var projects: [Project]

    private var waiting: [Idea] { ideas.filter { $0.startedAt == nil } }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Idea inbox").display(20, 750).foregroundStyle(Theme.ink)
                    if !waiting.isEmpty {
                        Text("\(waiting.count)").font(.ui(13, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.ink))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.tertiary)
                }
                SlotsLine(profile: profile, projects: projects)
                if waiting.isEmpty {
                    Text("Park ideas here instead of starting them all at once.")
                        .font(.ui(14)).foregroundStyle(Theme.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(waiting.prefix(3)) { idea in
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill").font(.system(size: 12)).foregroundStyle(Color(hex: 0xFFC800))
                                Text(idea.title).font(.ui(15, .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                            }
                        }
                        if waiting.count > 3 {
                            Text("+\(waiting.count - 3) more").font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.98))
    }
}

/// "1 of 2 build slots free" / "Both build slots taken · next frees up Oct 12".
struct SlotsLine: View {
    let profile: Profile
    let projects: [Project]

    var body: some View {
        let limit = profile.buildLimit
        let used = ProjectLimit.building(projects).count
        HStack(spacing: 8) {
            if limit > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<limit, id: \.self) { i in
                        Capsule().fill(i < used ? Theme.ink : Theme.line).frame(width: 18, height: 8)
                    }
                }
            }
            Text(text(limit: limit, used: used)).font(.ui(13, .semibold)).foregroundStyle(Theme.secondary)
        }
    }

    private func text(limit: Int, used: Int) -> String {
        if limit == 0 { return "\(used) building · no limit" }
        let free = max(0, limit - used)
        if free > 0 { return "\(free) of \(limit) build slot\(limit == 1 ? "" : "s") free" }
        let next = ProjectLimit.nextFree(projects).map { " · next frees up \($0.dayMonth)" } ?? ""
        return (limit == 1 ? "Build slot taken" : limit == 2 ? "Both build slots taken" : "All \(limit) build slots taken") + next
    }
}

struct IdeaInboxSheet: View {
    let profile: Profile
    var onStart: (Idea) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Idea.createdAt, order: .reverse) private var ideas: [Idea]
    @Query private var projects: [Project]
    @State private var title = ""
    @State private var note = ""
    @FocusState private var focus: Field?
    enum Field { case title, note }

    private var waiting: [Idea] { ideas.filter { $0.startedAt == nil } }
    private var started: [Idea] { ideas.filter { $0.startedAt != nil } }
    private var full: Bool { ProjectLimit.isFull(projects, profile: profile) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Idea inbox").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SlotsLine(profile: profile, projects: projects)
                    IdeaCapture(title: $title, note: $note, focus: $focus) { save() }
                    if waiting.isEmpty {
                        Text("No ideas parked. When one pops up mid-build, drop it here and keep going.")
                            .font(.ui(14)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(waiting) { idea in row(idea) }
                        }
                    }
                    if !started.isEmpty {
                        Text("Started").eyebrow().padding(.top, 6)
                        ForEach(started) { idea in
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                                Text(idea.title).font(.ui(15, .medium)).foregroundStyle(Theme.secondary).lineLimit(1)
                                Spacer()
                                Text(idea.startedAt?.dayMonth ?? "").font(.ui(13)).foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .animation(.snappy, value: ideas.map(\.id))
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, .neutral)
    }

    private func row(_ idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    if !idea.note.isEmpty {
                        Text(idea.note).font(.ui(14)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Parked " + idea.createdAt.formatted(.relative(presentation: .named)))
                        .font(.ui(12)).foregroundStyle(Theme.tertiary)
                }
                Spacer()
                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        context.delete(idea)
                        try? context.save()
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.tertiary)
                        .frame(width: 32, height: 32)
                }
            }
            Button {
                onStart(idea)
            } label: {
                Text(full ? "Slots full" : "Start building")
            }
            .buttonStyle(.chunky(full ? .neutral : .accent, height: 42))
            .disabled(full)
        }
        .card(padding: 16, radius: 22)
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        context.insert(Idea(title: t, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? context.save()
        Haptics.success()
        title = ""
        note = ""
        focus = nil
    }
}

/// Title, optional note, park button.
struct IdeaCapture: View {
    @Binding var title: String
    @Binding var note: String
    var focus: FocusState<IdeaInboxSheet.Field?>.Binding
    var onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $title, prompt: Text("New idea").foregroundStyle(Theme.tertiary))
                .focused(focus, equals: .title)
                .submitLabel(.done)
                .onSubmit(onSave)
                .inputField(focused: focus.wrappedValue == .title)
            if !title.isEmpty {
                TextField("", text: $note, prompt: Text("Why it could work (optional)").foregroundStyle(Theme.tertiary), axis: .vertical)
                    .lineLimit(1...3)
                    .focused(focus, equals: .note)
                    .inputField(focused: focus.wrappedValue == .note)
                Button("Park it", action: onSave).buttonStyle(.chunky(.neutral, height: 46))
            }
        }
        .animation(.snappy, value: title.isEmpty)
    }
}

/// Shown instead of the create flow while every build slot is taken.
struct BuildLimitSheet: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]
    @State private var title = ""
    @State private var note = ""
    @FocusState private var focus: IdeaInboxSheet.Field?

    var body: some View {
        let building = ProjectLimit.building(projects).sorted { $0.buildEnd < $1.buildEnd }
        VStack(spacing: 0) {
            HStack {
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.top, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.buildLimit == 1 ? "One build at a time" : "\(profile.buildLimit) builds at a time")
                            .display(28, 800).foregroundStyle(Theme.ink)
                        Text("Finishing beats starting. Park the idea now and pick it up when a slot frees up.")
                            .font(.ui(15)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 0) {
                        ForEach(building) { p in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(p.accent.base)
                                    .overlay(Text(p.initial).display(17, 800).foregroundStyle(p.accent.on))
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                                    Text(p.phase() == .upcoming ? "Starts \(p.startDate.dayMonth)" : "Ships \(p.launchDay.dayMonth) · \(p.daysLeftInPhase)d left")
                                        .font(.ui(13)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .card(padding: 14, radius: 20)
                    Text("Park the idea").eyebrow()
                    IdeaCapture(title: $title, note: $note, focus: $focus) { park() }
                    Text("Change the limit in Me → Configuration.").font(.ui(13)).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, .neutral)
        .onAppear { focus = .title }
    }

    private func park() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        context.insert(Idea(title: t, note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        try? context.save()
        celebration.fire(title: "Idea parked", subtitle: t, accent: Accent(hex: 0xFFC800), confetti: false)
        dismiss()
    }
}
