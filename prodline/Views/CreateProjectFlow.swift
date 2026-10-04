import SwiftUI
import SwiftData

/// Four short steps: basics → look (card + color) → schedule → connection.
struct CreateProjectFlow: View {
    let profile: Profile
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]

    @State private var step = 0
    @State private var name = ""
    @State private var details = ""
    @State private var imageData: Data?
    @State private var photoHex: Int?
    @State private var lockedToPhoto = false
    @State private var accentHex = Theme.swatches[0]
    @State private var startDate = Date.now.startOfDay
    @State private var buildDays = 14
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle
    @FocusState private var focus: Field?
    private enum Field { case name, details }

    private let steps = 4
    private var accent: Accent { Accent(hex: accentHex) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    switch step {
                    case 0: basicsStep
                    case 1: lookStep
                    case 2: scheduleStep
                    default: connectStep
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)

            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, accent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!trimmedName.isEmpty)
        .onAppear {
            buildDays = profile.buildDays
            startDate = max(ScheduleEngine.nextProjectDate(projects: projects, profile: profile), .now.startOfDay)
            let used = Set(projects.map(\.accentHex))
            accentHex = Theme.swatches.first { !used.contains($0) } ?? Theme.swatches[projects.count % Theme.swatches.count]
            focus = .name
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.soft()
                if step == 0 { dismiss() } else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step -= 1 } }
            } label: {
                Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 36, height: 36)
            }
            ChunkyProgressBar(value: Double(step + 1) / Double(steps), height: 14)
            // Once it has a face, the project rides along in the corner.
            if step >= 2 {
                miniMark.transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: step)
    }

    private var miniMark: some View {
        Group {
            if let data = imageData, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Text(trimmedName.first.map { String($0).uppercased() } ?? "?")
                    .display(17, 800)
                    .foregroundStyle(accent.on)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(accent.base)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button(step == steps - 1 ? "Create project" : "Continue", action: next)
                .buttonStyle(.chunky)
                .disabled(step == 0 && trimmedName.isEmpty)
            if step == steps - 1 && endpoint.isEmpty {
                Text("No endpoint yet? You'll see sample data until you connect.")
                    .font(.ui(13)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func stepTitle(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow).eyebrow(accent.text)
            Text(title).display(32, 750).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Steps

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Step 1 of 4", "What are you building?")

            VStack(alignment: .leading, spacing: 8) {
                Text("Name").eyebrow()
                TextField("", text: $name, prompt: Text("e.g. Habit Hero").foregroundStyle(Theme.tertiary))
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .details }
                    .inputField(focused: focus == .name)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description").eyebrow()
                TextField("", text: $details,
                          prompt: Text("One or two lines on what it is and who it's for").foregroundStyle(Theme.tertiary),
                          axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focus, equals: .details)
                    .padding(.vertical, 14)
                    .inputField(focused: focus == .details)
            }

            collaborators
        }
    }

    private var collaborators: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Collaborators").eyebrow()
                Spacer()
                Text("Coming soon")
                    .font(.ui(11, .semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.line))
            }
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.ink).frame(width: 40, height: 40)
                    Text("You").font(.ui(12, .semibold)).foregroundStyle(.white)
                }
                Circle()
                    .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "plus").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.tertiary))
                Text("Invite people to build with you")
                    .font(.ui(15)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 2))
            .opacity(0.55)
            .allowsHitTesting(false)
            .accessibilityLabel("Collaborators, coming soon")
        }
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle("Step 2 of 4", "Give it a face")
            CardCoverEditor(name: trimmedName, imageData: $imageData, accentHex: $accentHex,
                            photoHex: $photoHex, lockedToPhoto: $lockedToPhoto,
                            footnote: "Building · \(buildDays)d")
                .frame(width: 236)
                .frame(maxWidth: .infinity)
            AccentSlider(accentHex: $accentHex, locked: $lockedToPhoto, photoHex: photoHex)
        }
    }

    private var scheduleStep: some View {
        let draft = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                            buildDays: buildDays, observeDays: profile.observeDays)
        let ms = ScheduleEngine.makeMilestones(for: draft, weekdayMask: profile.milestoneWeekdayMask)
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 3 of 4", "Set the clock")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Starts").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().tint(accent.base)
                }
                Divider()
                HStack {
                    Text("Build phase").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(buildDays.durationText).display(20, 700).foregroundStyle(accent.text)
                        .contentTransition(.numericText())
                }
                ChunkySlider(value: $buildDays, range: 3...42)
            }
            .card()

            VStack(alignment: .leading, spacing: 12) {
                Text("Your deadlines").eyebrow()
                ForEach(ms, id: \.id) { m in
                    HStack {
                        Image(systemName: m.isLaunch ? "flag.checkered" : (m.title == "Traction review" ? "chart.line.uptrend.xyaxis" : "checkmark.circle"))
                            .foregroundStyle(accent.text)
                            .frame(width: 22)
                        Text(m.title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(m.dueDate.shortDay).font(.ui(14)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .card()
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 4 of 4", "Connect your numbers")
            ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe)
        }
    }

    // MARK: Actions

    private func next() {
        guard !(step == 0 && trimmedName.isEmpty) else { return }
        focus = nil
        if step < steps - 1 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            create()
        }
    }

    private func create() {
        let p = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                        buildDays: buildDays, observeDays: profile.observeDays)
        p.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        p.coverImage = imageData
        p.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: p.id.uuidString)
        ScheduleEngine.createProject(p, profile: profile, context: context)
        if profile.remindersEnabled { Task { _ = await Notifier.requestAuth() } }
        celebration.fire(title: "\(p.name) is live", subtitle: "Build phase: \(buildDays.durationText). Let's ship.", accent: p.accent)
        onCreated(p.id)
        dismiss()
    }
}
