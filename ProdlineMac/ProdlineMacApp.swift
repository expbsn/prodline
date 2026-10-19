import SwiftUI
import SwiftData
import CoreText

// Prodline for Mac: the same projects, synced through the same private iCloud database as the iPhone
// app. A window with the projects in a sidebar, and a menu bar item for the next deadline and its goals.
// Models and the metric/integration types come from the iOS app's files (see the target's membership
// exceptions); everything UI is Mac-only and lives here.

@main
struct ProdlineMacApp: App {
    @State private var celebration = CelebrationCenter()

    static let container: ModelContainer = {
        let schema = Schema([Profile.self, Project.self, Milestone.self, MetricSnapshot.self, Goal.self, Idea.self])
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)])
        } catch {
            // No iCloud (signed out, or an unsigned build): local only rather than crash.
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)])
        }
    }()

    init() {
        if let url = Bundle.main.url(forResource: "AfacadFlux-VariableFont_slnt,wght", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        WindowGroup("Prodline", id: "main") {
            MacRootView()
                .frame(minWidth: 860, minHeight: 560)
                .environment(celebration)
        }
        .modelContainer(Self.container)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra {
            MenuBarPanel()
                .modelContainer(Self.container)
        } label: {
            MenuBarLabel()
                .modelContainer(Self.container)
        }
        .menuBarExtraStyle(.window)
    }
}
