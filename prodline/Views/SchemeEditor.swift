import SwiftUI
import SwiftData

/// The user's custom building scheme (phase lengths, cadence, milestone weekdays).
struct SchemeEditor: View {
    @Bindable var profile: Profile

    private let days: [(Int, String)] = [(2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat"), (1, "Sun")]

    private var overlap: Int {
        Int((Double(profile.buildDays + profile.observeDays) / Double(max(profile.newProjectEveryDays, 1))).rounded(.up))
    }

    var body: some View {
        VStack(spacing: 22) {
            slider("Build phase", profile.buildDays.durationText, Theme.blue) {
                ChunkySlider(value: $profile.buildDays, range: 3...42, color: Theme.blue)
            }
            slider("Observe phase", profile.observeDays.durationText, Theme.orange) {
                ChunkySlider(value: $profile.observeDays, range: 7...90, color: Theme.orange)
            }
            slider("New project every", profile.newProjectEveryDays.durationText, Theme.green) {
                ChunkySlider(value: $profile.newProjectEveryDays, range: 3...42, color: Theme.green)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Checkpoint weekdays").font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    ForEach(days, id: \.0) { wd, label in
                        ChunkyChip(title: String(label.prefix(2)), isOn: profile.hasWeekday(wd)) {
                            profile.toggleWeekday(wd)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Every \(profile.newProjectEveryDays.durationText) you start a project: \(profile.buildDays.durationText) building, then \(profile.observeDays.durationText) watching traction. About \(overlap) project\(overlap == 1 ? "" : "s") will overlap.")
                .font(.rounded(14, .semibold)).foregroundStyle(Theme.ink)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: Theme.blue.opacity(0.4), fill: Theme.blueTint.opacity(0.4))
        }
    }

    private func slider<C: View>(_ title: String, _ value: String, _ color: Color, @ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.rounded(16, .heavy)).foregroundStyle(Theme.ink)
                Spacer()
                Text(value).font(.rounded(16, .heavy)).foregroundStyle(color)
                    .contentTransition(.numericText())
            }
            content()
        }
    }
}

struct MeView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Query private var projects: [Project]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack { Text("Me").font(.display(30)).foregroundStyle(Theme.ink); Spacer() }
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        stat("🔥", "\(profile.streak)", "Streak")
                        stat("🏆", "\(profile.bestStreak)", "Best")
                        stat("⭐️", "\(profile.xp)", "XP")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Building scheme")
                        SchemeEditor(profile: profile)
                        Text("Changes apply to projects you create from now on.")
                            .font(.rounded(12, .semibold)).foregroundStyle(Theme.inkLight)
                    }
                    .padding(16).card()

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle("Reminders")
                        Toggle(isOn: $profile.remindersEnabled) {
                            Text("Deadline notifications").font(.rounded(16, .bold)).foregroundStyle(Theme.ink)
                        }
                        .tint(Theme.green)
                        .onChange(of: profile.remindersEnabled) { _, on in
                            Haptics.select()
                            if on { Task { _ = await Notifier.requestAuth(); Notifier.rescheduleAll(projects: projects, profile: profile) } }
                            else { Notifier.rescheduleAll(projects: projects, profile: profile) }
                        }
                        if profile.remindersEnabled {
                            HStack {
                                Text("Morning reminder").font(.rounded(16, .bold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(String(format: "%02d:00", profile.reminderHour))
                                    .font(.rounded(16, .heavy)).foregroundStyle(Theme.blue)
                            }
                            ChunkySlider(value: $profile.reminderHour, range: 5...12)
                        }
                    }
                    .padding(16).card()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func stat(_ icon: String, _ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.system(size: 24))
            Text(value).font(.rounded(22, .heavy)).foregroundStyle(Theme.ink)
            Text(title).font(.rounded(12, .bold)).foregroundStyle(Theme.inkLight)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).card()
    }
}

struct OnboardingView: View {
    @Bindable var profile: Profile
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            ChunkyProgressBar(value: Double(step + 1) / 3, color: Theme.green, height: 14)
                .padding(.horizontal, 20).padding(.top, 12)

            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: scheme
                    default: reminders
                    }
                }
                .padding(.horizontal, 20).padding(.top, 24)
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollBounceBehavior(.basedOnSize)

            Button(step == 2 ? "Let's go!" : "Continue", action: next)
                .buttonStyle(.chunky)
                .padding(.horizontal, 20).padding(.vertical, 12)
            if step == 2 {
                Button("Maybe later") { profile.remindersEnabled = false; finish() }
                    .font(.rounded(15, .heavy)).foregroundStyle(Theme.inkLight)
                    .padding(.bottom, 8)
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Pip(size: 130, cheering: true).padding(.top, 30)
            Text("Prodline").font(.display(44)).foregroundStyle(Theme.blue)
            Text("Build a project every cycle, watch the numbers roll in, and keep your streak alive.")
                .font(.rounded(18, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
        }
    }

    private var scheme: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Pip(size: 56)
                Text("How do you like to build?").font(.display(24)).foregroundStyle(Theme.ink)
            }
            SchemeEditor(profile: profile)
        }
    }

    private var reminders: some View {
        VStack(spacing: 18) {
            Pip(size: 110, cheering: true).padding(.top, 20)
            Text("Want a nudge?").font(.display(30)).foregroundStyle(Theme.ink)
            Text("I'll remind you on checkpoint days so deadlines never sneak up on you.")
                .font(.rounded(18, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
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
        celebration.fire(title: "You're set! 🎉", subtitle: "Create your first project to begin.")
    }
}
