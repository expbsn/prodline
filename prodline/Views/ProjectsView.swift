import SwiftUI
import SwiftData

struct ProjectsView: View {
    let profile: Profile
    @Query(sort: \Project.startDate, order: .reverse) private var projects: [Project]
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack {
                        Text("Projects").font(.display(30)).foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.top, 8)

                    Button("New project") { showAdd = true }
                        .buttonStyle(.chunky)

                    if projects.isEmpty {
                        VStack(spacing: 12) {
                            Pip(size: 90, cheering: true)
                            Text("No projects yet").font(.rounded(20, .heavy)).foregroundStyle(Theme.ink)
                            Text("Start your first build phase and I'll keep you on schedule.")
                                .font(.rounded(15, .semibold)).foregroundStyle(Theme.inkLight)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                    }

                    ForEach(projects) { p in
                        NavigationLink(value: p) { ProjectRow(project: p) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Project.self) { ProjectDetailView(project: $0) }
            .sheet(isPresented: $showAdd) { AddProjectSheet(profile: profile) }
        }
    }
}

struct PhaseBadge: View {
    let phase: Phase
    var body: some View {
        Text("\(phase.icon) \(phase.title)")
            .font(.rounded(12, .heavy))
            .foregroundStyle(phase.color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(phase.color.opacity(0.14)))
    }
}

struct ProjectRow: View {
    let project: Project
    @Environment(DataRefresher.self) private var refresher

    var body: some View {
        let phase = project.phase()
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(project.emoji).font(.system(size: 30))
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(project.color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.rounded(18, .heavy)).foregroundStyle(Theme.ink)
                    PhaseBadge(phase: phase)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.line)
            }
            ChunkyProgressBar(value: project.overallProgress, color: phase.color, height: 12)
            HStack {
                Text(detail(phase)).font(.rounded(13, .semibold)).foregroundStyle(Theme.inkLight)
                Spacer()
                if let c = refresher.current(for: project) {
                    Text("\(MetricKey.visits.icon) \(MetricKey.visits.format(c.visits))  \(MetricKey.revenue.icon) \(MetricKey.revenue.format(c.revenue))")
                        .font(.rounded(13, .bold)).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(14)
        .card()
    }

    private func detail(_ phase: Phase) -> String {
        switch phase {
        case .upcoming: "Starts in \(project.daysLeftInPhase.durationText)"
        case .building: "\(project.daysLeftInPhase.durationText) of building left"
        case .observing: "\(project.daysLeftInPhase.durationText) of observing left"
        case .finished: "Wrapped up \(project.observeEnd.shortDay)"
        }
    }
}

// MARK: - Add

struct AddProjectSheet: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]

    @State private var name = ""
    @State private var emoji = "🚀"
    @State private var colorIndex = 0
    @State private var startDate = Date.now.startOfDay
    @State private var buildDays = 14
    @State private var endpoint = ""
    @State private var apiKey = ""
    @FocusState private var focus: Field?
    private enum Field { case name, endpoint, key }

    private let emojis = ["🚀", "💡", "🛠️", "📱", "🎮", "🧪", "🛒", "🎨", "📈", "🌱", "🤖", "🎵"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    field("Name") {
                        TextField("e.g. Habit Hero", text: $name)
                            .chunkyField(focused: focus == .name).focused($focus, equals: .name)
                    }
                    field("Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button { Haptics.select(); emoji = e } label: {
                                    Text(e).font(.system(size: 26)).frame(maxWidth: .infinity).frame(height: 48)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(emoji == e ? Theme.blueTint : .white))
                                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(emoji == e ? Theme.blue : Theme.line, lineWidth: 2))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    field("Color") {
                        HStack(spacing: 12) {
                            ForEach(Theme.palette.indices, id: \.self) { i in
                                Button { Haptics.select(); colorIndex = i } label: {
                                    Circle().fill(Theme.palette[i]).frame(width: 36, height: 36)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 3).padding(2).opacity(colorIndex == i ? 1 : 0))
                                        .overlay(Circle().strokeBorder(Theme.palette[i], lineWidth: 2).opacity(colorIndex == i ? 1 : 0))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    field("Starts") {
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden().datePickerStyle(.compact).tint(Theme.blue)
                    }
                    field("Build phase: \(buildDays.durationText)") {
                        ChunkySlider(value: $buildDays, range: 3...42)
                    }
                    field("Connect later or now") {
                        VStack(spacing: 10) {
                            TextField("https://yourapp.com/api/prodline", text: $endpoint)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                                .chunkyField(focused: focus == .endpoint).focused($focus, equals: .endpoint)
                            SecureField("API key", text: $apiKey)
                                .chunkyField(focused: focus == .key).focused($focus, equals: .key)
                            Text("Leave empty to use sample data. Keys are stored in your Keychain.")
                                .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkLight)
                        }
                    }
                    Button("Create project", action: create)
                        .buttonStyle(.chunky(.success))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                buildDays = profile.buildDays
                startDate = max(ScheduleEngine.nextProjectDate(projects: projects, profile: profile), .now.startOfDay)
                colorIndex = projects.count % Theme.palette.count
            }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.rounded(14, .heavy)).foregroundStyle(Theme.inkLight).textCase(.uppercase)
            content()
        }
    }

    private func create() {
        let p = Project(name: name.trimmingCharacters(in: .whitespaces), emoji: emoji, colorIndex: colorIndex,
                        startDate: startDate, buildDays: buildDays, observeDays: profile.observeDays)
        p.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        Keychain.set(apiKey, for: p.id.uuidString)
        ScheduleEngine.createProject(p, profile: profile, context: context)
        if profile.remindersEnabled { Task { _ = await Notifier.requestAuth() } }
        celebration.fire(title: "Project created! \(emoji)", subtitle: "Build phase: \(buildDays.durationText). Let's ship.")
        dismiss()
    }
}
