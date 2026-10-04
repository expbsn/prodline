import SwiftUI
import SwiftData

/// The user's custom building scheme (phase lengths, cadence, checkpoint weekdays).
struct SchemeEditor: View {
    @Bindable var profile: Profile

    private let days: [(Int, String)] = [(2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa"), (1, "Su")]

    private var overlap: Int {
        Int((Double(profile.buildDays + profile.observeDays) / Double(max(profile.newProjectEveryDays, 1))).rounded(.up))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            row("Build phase", profile.buildDays.durationText) {
                ChunkySlider(value: $profile.buildDays, range: 3...42)
            }
            row("Observe phase", profile.observeDays.durationText) {
                ChunkySlider(value: $profile.observeDays, range: 7...90)
            }
            row("New project every", profile.newProjectEveryDays.durationText) {
                ChunkySlider(value: $profile.newProjectEveryDays, range: 3...42)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Checkpoint days").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ForEach(days, id: \.0) { wd, label in
                        Chip(title: label, isOn: profile.hasWeekday(wd)) { profile.toggleWeekday(wd) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            SchemePreview(build: profile.buildDays, observe: profile.observeDays, every: profile.newProjectEveryDays)
            Text("A new project every \(profile.newProjectEveryDays.durationText): \(profile.buildDays.durationText) building, then \(profile.observeDays.durationText) watching traction. About \(overlap) project\(overlap == 1 ? "" : "s") run at once.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row<C: View>(_ title: String, _ value: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).font(.display(20, 700)).foregroundStyle(Theme.ink).contentTransition(.numericText())
            }
            content()
        }
    }
}

/// Mini Gantt of how projects overlap with the current scheme.
struct SchemePreview: View {
    let build: Int, observe: Int, every: Int

    var body: some View {
        GeometryReader { geo in
            let span = Double(every * 3 + build + observe)
            let w = geo.size.width
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<4) { i in
                    let x = Double(i * every) / span * w
                    HStack(spacing: 2) {
                        Capsule().fill(Theme.ink).frame(width: Double(build) / span * w)
                        Capsule().fill(Theme.ink.opacity(0.18)).frame(width: Double(observe) / span * w)
                    }
                    .frame(height: 9)
                    .offset(x: x)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: build + observe * 100 + every * 10000)
        }
        .frame(height: 4 * 9 + 3 * 5)
        .accessibilityHidden(true)
    }
}

struct MeView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]
    @AppStorage("mockServerURL") private var mockServerURL = "http://127.0.0.1:8787"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Level \(profile.level)", title: "Me")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(profile.xp % 100) / 100 XP to level \(profile.level + 1)").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text("Best streak \(profile.bestStreak)").font(.ui(13)).foregroundStyle(Theme.secondary)
                    }
                    ChunkyProgressBar(value: profile.levelProgress, color: Color(hex: 0xFFC800))
                }
                .card()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle("Building scheme")
                    SchemeEditor(profile: profile)
                    Label("Applies to projects you create from now on.", systemImage: "info.circle")
                        .font(.ui(12)).foregroundStyle(Theme.secondary)
                }
                .card()
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Reminders")
                    Toggle(isOn: $profile.remindersEnabled) {
                        Text("Deadline notifications").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                    }
                    .tint(Theme.ink)
                    .onChange(of: profile.remindersEnabled) { _, on in
                        Haptics.select()
                        Task {
                            if on { _ = await Notifier.requestAuth() }
                            Notifier.rescheduleAll(projects: projects, profile: profile)
                        }
                    }
                    if profile.remindersEnabled {
                        HStack {
                            Text("Morning reminder").font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text(String(format: "%02d:00", profile.reminderHour)).font(.display(20, 700)).foregroundStyle(Theme.ink)
                        }
                        ChunkySlider(value: $profile.reminderHour, range: 5...12)
                            .onChange(of: profile.reminderHour) { Notifier.rescheduleAll(projects: projects, profile: profile) }
                    }
                }
                .card()
                .padding(.horizontal, 16)

                developerCard.padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }

    private var developerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Demo & testing")
            Text("Run `python3 MockProject/server.py` on your Mac, then load demo projects that stream data from it.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
            TextField("Mock server URL", text: $mockServerURL)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .inputField()
            Button("Load demo projects") {
                DemoData.load(baseURL: mockServerURL, profile: profile, context: context)
                celebration.fire(title: "Demo loaded", subtitle: "\(DemoData.projects.count) projects connected to the mock server")
                Task { await refresher.refresh(projects: projects, context: context, force: true) }
            }
            .buttonStyle(.chunky(.neutral, height: 50))
        }
        .card()
    }
}

struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @State private var step = 0
    @State private var fanned = false

    var body: some View {
        VStack(spacing: 0) {
            ChunkyProgressBar(value: Double(step + 1) / 3, color: Theme.ink, height: 12)
                .padding(.horizontal, 24).padding(.top, 14)

            ScrollView(showsIndicators: false) {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: scheme
                    default: reminders
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 4) {
                Button(step == 2 ? "Turn on reminders" : (step == 0 ? "Get started" : "Continue"), action: next)
                    .buttonStyle(.chunky)
                if step == 2 {
                    Button("Not now") { profile.remindersEnabled = false; finish() }
                        .font(.ui(15, .semibold)).foregroundStyle(Theme.secondary)
                        .frame(height: 40)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                ForEach(Array(sampleCards.enumerated()), id: \.offset) { i, c in
                    ProjectCardFace(name: c.0, initial: String(c.0.prefix(1)), accent: Accent(hex: c.1), cover: nil,
                                    cornerLabel: "Day", cornerValue: "\(c.2)", footnote: c.3)
                        .frame(width: 180)
                        .rotationEffect(.degrees(fanned ? Double(i - 1) * 12 : 0), anchor: .bottom)
                        .offset(x: fanned ? CGFloat(i - 1) * 46 : 0, y: fanned ? abs(CGFloat(i - 1)) * 16 : 0)
                        .shadow(color: .black.opacity(0.12), radius: 16, y: 10)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 330)
            .onAppear {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.15)) { fanned = true }
            }

            Text("Welcome to").eyebrow()
            Text("Prodline").font(.display(60, 800)).foregroundStyle(Theme.ink).padding(.top, -14)
            Text("Ship a project every cycle, watch its numbers come in, and keep the streak going.")
                .font(.ui(19)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private let sampleCards: [(String, Int, Int, String)] = [
        ("Habit Hero", 0x58CC02, 12, "Building"),
        ("Pixel Quest", 0xA35CFF, 5, "Building"),
        ("Side Shop", 0xFF9600, 9, "Observing"),
    ]

    private var scheme: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your rhythm").eyebrow()
                Text("How do you like to build?").font(.display(34, 750)).foregroundStyle(Theme.ink)
            }
            SchemeEditor(profile: profile).card()
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stay on time").eyebrow()
                Text("A nudge on deadline days").font(.display(34, 750)).foregroundStyle(Theme.ink)
            }
            // Notification preview.
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: 0x58CC02))
                    .frame(width: 38, height: 38)
                    .overlay(Text("H").font(.display(20, 800)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Habit Hero: deadline day").font(.ui(15, .semibold))
                        Spacer()
                        Text("9:00").font(.ui(13)).foregroundStyle(Theme.secondary)
                    }
                    Text("Checkpoint 2 is due today. You've got this.").font(.ui(15)).foregroundStyle(Theme.inkSoft)
                }
            }
            .card(padding: 14, radius: 22)
            Text("We remind you in the morning and again at 6 pm if it's still open. Nothing else.")
                .font(.ui(17)).foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func next() {
        if step < 2 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            Task { profile.remindersEnabled = await Notifier.requestAuth(); finish() }
        }
    }

    private func finish() {
        profile.onboarded = true
        try? context.save()
        celebration.fire(title: "You're set", subtitle: "Create your first project to begin.")
    }
}
