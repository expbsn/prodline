import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case projects, plan, insights, me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: "Dash"
        case .plan: "Plan"
        case .insights: "Data"
        case .me: "Me"
        }
    }

    var symbol: String {
        switch self {
        case .projects: "rectangle.stack.fill"
        case .plan: "calendar"
        case .insights: "chart.bar.fill"
        case .me: "person.fill"
        }
    }
}

/// Floating, color-neutral tab bar (no animations) with a separate round "+" button.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    let selected = tab == selection
                    Button {
                        guard !selected else { return }
                        Haptics.select()
                        selection = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(height: 22) // symbols differ in height; keep labels on one baseline
                            Text(tab.title)
                                .font(.ui(11, .semibold))
                                .tracking(0.6)
                        }
                        .foregroundStyle(selected ? .white : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background {
                            if selected { Capsule().fill(Theme.ink) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(5)
            .background(Capsule().fill(.white))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)

            Button(action: { Haptics.tap(); onAdd() }) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
            }
            .buttonStyle(PressableStyle(scale: 0.9))
            .accessibilityLabel("New project")
        }
        .padding(.horizontal, 16)
    }
}
