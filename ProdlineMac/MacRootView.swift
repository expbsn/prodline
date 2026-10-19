import SwiftUI
import SwiftData
import AppKit

struct MacRootView: View {
    @Query(sort: \Project.startDate, order: .reverse) private var projects: [Project]
    @Query private var profiles: [Profile]
    @State private var selection: UUID?
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration

    private var groups: [(Phase, [Project])] {
        [Phase.building, .observing, .upcoming, .finished].compactMap { phase in
            let ps = projects.filter { $0.phase() == phase }
            return ps.isEmpty ? nil : (phase, ps)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups, id: \.0) { phase, ps in
                    Section(phase.title) {
                        ForEach(ps) { p in SidebarRow(project: p).tag(p.id) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            .overlay {
                if projects.isEmpty {
                    ContentUnavailableView("No projects yet", systemImage: "square.stack.3d.up",
                                           description: Text("Projects you create on your iPhone show up here through iCloud."))
                }
            }
        } detail: {
            if let p = projects.first(where: { $0.id == selection }) {
                ProjectPane(project: p)
            } else {
                ContentUnavailableView("Pick a project", systemImage: "sidebar.left")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { StreakBadge(streak: profiles.first?.streak ?? 0) }
        }
        .overlay(alignment: .top) {
            if let b = celebration.banner { CelebrationBanner(banner: b).padding(.top, 12).transition(.move(edge: .top).combined(with: .opacity)) }
        }
        .onAppear {
            #if DEBUG
            MacDemo.seedIfNeeded(context)
            MacDemo.snapshotIfAsked(context, container: ProdlineMacApp.container)
            #endif
            if selection == nil { selection = groups.first?.1.first?.id }
        }
        .onChange(of: projects.count) { if selection == nil { selection = groups.first?.1.first?.id } }
    }
}

struct SidebarRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 10) {
            ProjectThumb(project: project, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(project.isActive ? "Day \(project.dayInPhase) of \(project.phaseLength)" : project.phase().title)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Cover photo, or the initial on the project color.
struct ProjectThumb: View {
    let project: Project
    var size: CGFloat

    var body: some View {
        Group {
            if let data = project.coverImage, let img = NSImage(data: data) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                project.accent.base.overlay {
                    Text(project.initial).font(.display(size * 0.5, 750)).foregroundStyle(project.accent.on)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct StreakBadge: View {
    let streak: Int
    var body: some View {
        Label("\(streak)", systemImage: "flame.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(streak > 0 ? Theme.flame : .secondary)
            .font(.system(size: 13, weight: .bold))
            .help("\(streak)-day streak")
    }
}
