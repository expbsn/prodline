import SwiftUI
import SwiftData
import CoreText

// Prodline for Mac: the iPhone app's screens in a Mac window, plus a menu bar item. Works on its own
// (projects, integrations with keys in this Mac's Keychain, GitHub sync) and shares projects with the
// iPhone through the same private iCloud database. Models, services and screens come from the iOS
// target's folder (see the Mac target's membership exceptions); Mac-only pieces live here.

@main
struct ProdlineMacApp: App {
    @State private var refresher = DataRefresher()
    @State private var github = GitHubService()
    @State private var celebration = CelebrationCenter()
    @AppStorage(AppSettings.Key.appearance) private var appearance = "system"

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

    private var scheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }

    var body: some Scene {
        WindowGroup("Prodline", id: "main") {
            MacRootView()
                .frame(minWidth: 900, minHeight: 620)
                .environment(refresher)
                .environment(github)
                .environment(celebration)
                .preferredColorScheme(scheme)
        }
        .modelContainer(Self.container)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1180, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { NotificationCenter.default.post(name: .macNewProject, object: nil) }
                    .keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .modelContainer(Self.container)
                .environment(refresher)
                .environment(celebration)
                .preferredColorScheme(scheme)
        } label: {
            MenuBarLabel()
                .modelContainer(Self.container)
        }
        .menuBarExtraStyle(.window)
    }
}
