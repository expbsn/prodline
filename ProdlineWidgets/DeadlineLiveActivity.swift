import ActivityKit
import WidgetKit
import SwiftUI

/// Deadline day on the Lock Screen and in the Dynamic Island: which checkpoint, the goals still open,
/// and a countdown to midnight. Started and ended by the app (Services/LiveActivities.swift).
struct DeadlineLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeadlineAttributes.self) { context in
            DeadlineLockScreen(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(.white)
                .activitySystemActionForegroundColor(Theme.ink)
                .widgetURL(context.attributes.url)
        } dynamicIsland: { context in
            let a = context.attributes, s = context.state
            let accent = Accent(hex: a.accentHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LABadge(initial: a.initial, accent: accent, size: 34)
                        .padding(.leading, 4).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LACountdown(state: s, deadline: a.deadline, onDark: true)
                        .padding(.trailing, 4).padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.projectName.uppercased()).font(.ui(11, .semibold)).tracking(0.6)
                            .foregroundStyle(.white.opacity(0.6))
                        Text(a.checkpoint).display(17, 800).foregroundStyle(.white).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        LAGoals(state: s, accent: accent, onDark: true, max: 2)
                        LAProgress(state: s, accent: accent, onDark: true)
                    }
                    .padding(.horizontal, 4).padding(.top, 6)
                }
            } compactLeading: {
                LARing(state: s, accent: accent, size: 20, onDark: true)
                    .padding(.horizontal, 2)
            } compactTrailing: {
                if s.allDone {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(accent.island)
                } else {
                    Text(timerInterval: Date.now...max(Date.now, a.deadline), countsDown: true, showsHours: true)
                        .font(.ui(14, .semibold)).monospacedDigit()
                        .foregroundStyle(accent.island)
                        .frame(width: 66)
                        .multilineTextAlignment(.trailing)
                }
            } minimal: {
                LARing(state: s, accent: accent, size: 20, onDark: true)
            }
            .widgetURL(a.url)
            .keylineTint(accent.island)
        }
    }
}

private struct DeadlineLockScreen: View {
    let attributes: DeadlineAttributes
    let state: DeadlineAttributes.ContentState
    let isStale: Bool
    private var accent: Accent { Accent(hex: attributes.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                LABadge(initial: attributes.initial, accent: accent, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.allDone ? "CHECKPOINT CLEARED" : "DUE TODAY · \(attributes.projectName.uppercased())")
                        .font(.ui(11, .semibold)).tracking(0.6)
                        .foregroundStyle(state.allDone ? accent.text : Theme.secondary)
                        .lineLimit(1)
                    Text(attributes.checkpoint).display(19, 800).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer(minLength: 6)
                LACountdown(state: state, deadline: attributes.deadline, onDark: false)
            }
            LAGoals(state: state, accent: accent, onDark: false, max: 2, showsMore: false)
            LAProgress(state: state, accent: accent, onDark: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(isStale ? 0.6 : 1)
    }
}

// MARK: - Pieces

private extension Accent {
    /// The accent on the black island: very dark accents would vanish, so they turn white.
    var island: Color { luminance < 0.06 ? .white : base }
}

private struct LABadge: View {
    let initial: String
    let accent: Accent
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(accent.base)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(accent.dark).offset(y: size * 0.08))
            .overlay(Text(initial).display(size * 0.55, 800).foregroundStyle(accent.on))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(accent.luminance < 0.06 ? 0.25 : 0), lineWidth: 1))
            .frame(width: size, height: size)
            .padding(.bottom, size * 0.08)
    }
}

private struct LARing: View {
    let state: DeadlineAttributes.ContentState
    let accent: Accent
    var size: CGFloat
    var onDark: Bool

    var body: some View {
        let color = onDark ? accent.island : accent.base
        ZStack {
            Circle().inset(by: 1.5).stroke(color.opacity(0.25), lineWidth: 3)
            Circle().inset(by: 1.5).trim(from: 0, to: max(0.02, state.progress))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if state.allDone {
                Image(systemName: "checkmark").font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Time left until midnight, or a check once everything's done.
private struct LACountdown: View {
    let state: DeadlineAttributes.ContentState
    let deadline: Date
    let onDark: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if state.allDone {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 26, weight: .bold))
                    .foregroundStyle(onDark ? .white : Theme.success)
            } else {
                Text("LEFT").font(.ui(11, .semibold)).tracking(0.6)
                    .foregroundStyle(onDark ? .white.opacity(0.6) : Theme.secondary)
                Text(timerInterval: Date.now...max(Date.now, deadline), countsDown: true, showsHours: true)
                    .display(19, 800).monospacedDigit()
                    .foregroundStyle(onDark ? .white : Theme.ink)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }
}

private struct LAGoals: View {
    let state: DeadlineAttributes.ContentState
    let accent: Accent
    let onDark: Bool
    var max: Int
    /// The Lock Screen leaves it to the progress line; it has no room for another row.
    var showsMore = true

    var body: some View {
        let shown = Array(state.goals.prefix(max))
        let more = state.openCount - shown.filter { !$0.done }.count
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, goal in
                HStack(spacing: 8) {
                    Image(systemName: goal.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(goal.done ? (onDark ? accent.island : accent.base) : (onDark ? .white.opacity(0.45) : Theme.tertiary))
                    Text(goal.title)
                        .font(.ui(14, goal.done ? .regular : .medium))
                        .strikethrough(goal.done)
                        .foregroundStyle(goal.done ? (onDark ? .white.opacity(0.45) : Theme.secondary) : (onDark ? .white : Theme.ink))
                        .lineLimit(1)
                }
            }
            if showsMore, more > 0 {
                Text("+\(more) more open")
                    .font(.ui(12, .semibold))
                    .foregroundStyle(onDark ? .white.opacity(0.55) : Theme.secondary)
                    .padding(.leading, 23)
            }
        }
    }
}

private struct LAProgress: View {
    let state: DeadlineAttributes.ContentState
    let accent: Accent
    let onDark: Bool

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(onDark ? Color.white.opacity(0.15) : Theme.line)
                    Capsule().fill(onDark ? accent.island : accent.base)
                        .frame(width: max(8, geo.size.width * state.progress))
                }
            }
            .frame(height: 8)
            Text(state.allDone ? "All \(state.goalCount) done" : "\(state.goalsDone)/\(state.goalCount) done · \(state.openCount) open")
                .font(.ui(12, .semibold)).monospacedDigit()
                .foregroundStyle(onDark ? .white.opacity(0.7) : Theme.secondary)
        }
    }
}

// MARK: - Previews

extension DeadlineAttributes {
    static let preview = DeadlineAttributes(projectID: "p", milestoneID: "m", projectName: "Habit Hero", accentHex: 0x58CC02,
                                            checkpoint: "Streak screen", due: .now)
}

extension DeadlineAttributes.ContentState {
    static let open = Self(goals: [WidgetGoal(title: "Shareable streak card", done: false),
                                   WidgetGoal(title: "Push reminders", done: false),
                                   WidgetGoal(title: "Onboarding flow live", done: true)],
                           goalCount: 4, goalsDone: 1)
    static let done = Self(goals: [WidgetGoal(title: "Shareable streak card", done: true)], goalCount: 4, goalsDone: 4)
}

#Preview("Lock Screen", as: .content, using: DeadlineAttributes.preview) {
    DeadlineLiveActivity()
} contentStates: {
    DeadlineAttributes.ContentState.open
    DeadlineAttributes.ContentState.done
}
