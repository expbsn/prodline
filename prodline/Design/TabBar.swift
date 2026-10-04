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

    /// Outline when idle, filled when selected.
    func symbol(selected: Bool) -> String {
        let base: String = switch self {
        case .projects: "rectangle.stack"
        case .plan: "list.bullet.rectangle"
        case .insights: "chart.bar"
        case .me: "person"
        }
        return selected ? base + ".fill" : base
    }
}

/// Floating, color-neutral tab bar (no animations): the selected tab shows a filled black icon.
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
                            Image(systemName: tab.symbol(selected: selected))
                                .font(.system(size: 18, weight: .semibold))
                                .frame(height: 22) // symbols differ in height; keep labels on one baseline
                            Text(tab.title)
                                .font(.ui(11, .semibold))
                                .tracking(0.6)
                        }
                        .foregroundStyle(selected ? Theme.ink : Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
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
