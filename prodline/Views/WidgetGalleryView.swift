import SwiftUI
import SwiftData
import WidgetKit

/// Widget sizes on a 6.3" iPhone, in points.
private enum WidgetSize {
    static let small = CGSize(width: 170, height: 170)
    static let medium = CGSize(width: 364, height: 170)
    static let large = CGSize(width: 364, height: 382)
}

/// A widget preview: the shared widget view inside a home-screen-sized tile.
struct WidgetTile<Content: View, Background: View>: View {
    let size: CGSize
    var scale: CGFloat = 1
    @ViewBuilder var content: () -> Content
    @ViewBuilder var background: () -> Background

    var body: some View {
        content()
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(background())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
            .environment(\.openURL, OpenURLAction { _ in .handled })
            .allowsHitTesting(false)
    }
}

extension WidgetTile where Background == Color {
    init(size: CGSize, scale: CGFloat = 1, @ViewBuilder content: @escaping () -> Content) {
        self.size = size; self.scale = scale; self.content = content; self.background = { Color.white }
    }
}

/// Me → Widgets: what the widgets look like with your projects, and how to add them.
struct WidgetsCard: View {
    let data: WidgetData
    @State private var showGallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Widgets")
            GeometryReader { geo in
                let scale = min(1, geo.size.width / WidgetSize.medium.width)
                WidgetTile(size: WidgetSize.medium, scale: scale) {
                    ProjectWidgetView(project: data.mostUrgent(on: .now), date: .now, family: .systemMedium)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: WidgetSize.medium.height * 0.86)
            Text("Touch and hold the Home Screen, tap Edit → Add Widget and search for Prodline. While editing, tap a widget to choose which project it follows; left empty, it always shows your next deadline.")
                .font(.ui(14)).foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("See all widgets") { showGallery = true }
                .buttonStyle(.chunky(.neutral, height: 50))
        }
        .card()
        .sheet(isPresented: $showGallery) { WidgetGalleryView(data: data) }
        #if DEBUG
        .onAppear { if UserDefaults.standard.string(forKey: "PRODLINE_SHEET") == "widgets" { showGallery = true } }
        #endif
    }
}

struct WidgetGalleryView: View {
    let data: WidgetData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let now = Date.now
        let project = data.mostUrgent(on: now)
        VStack(spacing: 0) {
            HStack {
                Text("Widgets").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    section("Project", "The next checkpoint, its goals and how long you have. Pick a project or let it follow your next deadline.") {
                        HStack(spacing: 14) {
                            WidgetTile(size: WidgetSize.small, scale: 0.98) {
                                ProjectWidgetView(project: project, date: now, family: .systemSmall)
                            }
                            WidgetTile(size: WidgetSize.small, scale: 0.98, content: {
                                TractionWidgetView(project: project, projects: data.projects, metricKey: "visits", date: now, family: .systemSmall)
                            }, background: { TractionWidgetView.background(for: project) })
                        }
                        WidgetTile(size: WidgetSize.medium) {
                            ProjectWidgetView(project: project, date: now, family: .systemMedium)
                        }
                        WidgetTile(size: WidgetSize.large) {
                            ProjectWidgetView(project: project, date: now, family: .systemLarge)
                        }
                    }
                    section("Traction", "Visits, social views or revenue for one project or all of them, with the last seven days.") {
                        WidgetTile(size: WidgetSize.medium) {
                            TractionWidgetView(project: nil, projects: data.projects, metricKey: "revenue", date: now, family: .systemMedium)
                        }
                    }
                    section("All projects", "Every running project, soonest deadline first.") {
                        WidgetTile(size: WidgetSize.medium) {
                            LineupWidgetView(data: data, date: now, family: .systemMedium)
                        }
                        WidgetTile(size: WidgetSize.large) {
                            LineupWidgetView(data: data, date: now, family: .systemLarge)
                        }
                    }
                    section("Lock Screen", "A countdown ring, the next checkpoint, or one line above the clock.") {
                        HStack(spacing: 14) {
                            lock(CGSize(width: 72, height: 72)) { ProjectWidgetView(project: project, date: now, family: .accessoryCircular) }
                            lock(CGSize(width: 170, height: 72)) { ProjectWidgetView(project: project, date: now, family: .accessoryRectangular) }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private func section<Content: View>(_ title: String, _ text: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).display(20, 750).foregroundStyle(Theme.ink)
                Text(text).font(.ui(14)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 14) { content() }.frame(maxWidth: .infinity)
        }
    }

    /// Lock Screen widgets render monochrome on the wallpaper.
    private func lock<Content: View>(_ size: CGSize, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .tint(.white)
            .padding(8)
            .frame(width: size.width, height: size.height)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0x4A4E69), Color(hex: 0x22223B)], startPoint: .top, endPoint: .bottom)))
    }
}
