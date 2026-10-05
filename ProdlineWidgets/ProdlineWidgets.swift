import WidgetKit
import SwiftUI
import AppIntents

@main
struct ProdlineWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProjectWidget()
        TractionWidget()
        LineupWidget()
    }
}

// MARK: - Configuration

/// A project to follow, or the automatic choice ("auto": next deadline / all projects).
struct ProjectEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static let defaultQuery = ProjectQuery()
    static let autoID = "auto"
    static let nextDeadline = ProjectEntity(id: autoID, name: "Next deadline")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    /// nil for the automatic choice.
    var projectID: String? { id == Self.autoID ? nil : id }
}

struct ProjectQuery: EntityQuery {
    static func projects() -> [ProjectEntity] {
        (SharedStore.read()?.projects ?? []).map { ProjectEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        ([ProjectEntity.nextDeadline] + Self.projects()).filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [ProjectEntity] { [.nextDeadline] + Self.projects() }
    func defaultResult() async -> ProjectEntity? { .nextDeadline }
}

/// Same projects, but the automatic choice adds all of them up.
struct TractionSourceEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Source"
    static let defaultQuery = TractionSourceQuery()
    static let all = TractionSourceEntity(id: ProjectEntity.autoID, name: "All projects")

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    var projectID: String? { id == ProjectEntity.autoID ? nil : id }
}

struct TractionSourceQuery: EntityQuery {
    private var all: [TractionSourceEntity] {
        [.all] + ProjectQuery.projects().map { TractionSourceEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [TractionSourceEntity] { all.filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [TractionSourceEntity] { all }
    func defaultResult() async -> TractionSourceEntity? { .all }
}

struct SelectProjectIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a project"
    static let description = IntentDescription("Pick the project this widget follows, or let it show whichever deadline comes next.")

    @Parameter(title: "Follow")
    var project: ProjectEntity?
}

enum MetricChoice: String, AppEnum {
    case visits, socialViews = "social_views", revenue

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [MetricChoice: DisplayRepresentation] = [
        .visits: "Visits", .socialViews: "Social views", .revenue: "Revenue",
    ]
}

struct TractionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Traction"
    static let description = IntentDescription("One number and its last week, for a single project or all of them added up.")

    @Parameter(title: "Metric", default: .visits)
    var metric: MetricChoice

    @Parameter(title: "Source")
    var project: TractionSourceEntity?
}

// MARK: - Timeline

struct ProdlineEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    let projectID: String?
    var metric: String = "visits"

    /// The picked project, or the most urgent one when none is picked (or it was deleted).
    var project: WidgetProject? { data.project(id: projectID) ?? data.mostUrgent(on: date) }
    var pickedProject: WidgetProject? { data.project(id: projectID) }
}

/// Data comes from the app; the timeline only needs fresh entries at midnight so
/// "Tomorrow" turns into "Today" without the app running.
private func dailyTimeline(_ make: (Date) -> ProdlineEntry) -> Timeline<ProdlineEntry> {
    let now = Date.now
    let days = (1...3).map { now.startOfDay.adding(days: $0) }
    return Timeline(entries: [make(now)] + days.map(make), policy: .after(days.last!))
}

private func load(_ context: TimelineProviderContext) -> WidgetData {
    if let data = SharedStore.read(), !data.projects.isEmpty { return data }
    return context.isPreview ? .sample() : WidgetData(generatedAt: .now, streak: 0, projects: [])
}

struct ProjectProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProdlineEntry {
        ProdlineEntry(date: .now, data: .sample(), projectID: nil)
    }
    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> ProdlineEntry {
        ProdlineEntry(date: .now, data: load(context), projectID: configuration.project?.projectID)
    }
    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<ProdlineEntry> {
        let data = load(context)
        return dailyTimeline { ProdlineEntry(date: $0, data: data, projectID: configuration.project?.projectID) }
    }
}

struct TractionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProdlineEntry {
        ProdlineEntry(date: .now, data: .sample(), projectID: "sample-habit")
    }
    func snapshot(for configuration: TractionIntent, in context: Context) async -> ProdlineEntry {
        ProdlineEntry(date: .now, data: load(context), projectID: configuration.project?.projectID, metric: configuration.metric.rawValue)
    }
    func timeline(for configuration: TractionIntent, in context: Context) async -> Timeline<ProdlineEntry> {
        let data = load(context)
        return dailyTimeline { ProdlineEntry(date: $0, data: data, projectID: configuration.project?.projectID, metric: configuration.metric.rawValue) }
    }
}

struct LineupProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProdlineEntry { ProdlineEntry(date: .now, data: .sample(), projectID: nil) }
    func getSnapshot(in context: Context, completion: @escaping (ProdlineEntry) -> Void) {
        completion(ProdlineEntry(date: .now, data: load(context), projectID: nil))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProdlineEntry>) -> Void) {
        let data = load(context)
        completion(dailyTimeline { ProdlineEntry(date: $0, data: data, projectID: nil) })
    }
}

// MARK: - Widgets

struct ProjectWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ProjectWidget", intent: SelectProjectIntent.self, provider: ProjectProvider()) { entry in
            ProjectEntryView(entry: entry)
        }
        .configurationDisplayName("Project")
        .description("The next checkpoint, its goals and how long you have.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct ProjectEntryView: View {
    let entry: ProdlineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        ProjectWidgetView(project: entry.project, date: entry.date, family: family)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular, .accessoryInline: AccessoryWidgetBackground().opacity(0)
                default: Color.white
                }
            }
    }
}

struct TractionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TractionWidget", intent: TractionIntent.self, provider: TractionProvider()) { entry in
            TractionEntryView(entry: entry)
        }
        .configurationDisplayName("Traction")
        .description("Visits, social views or revenue with the last seven days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TractionEntryView: View {
    let entry: ProdlineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TractionWidgetView(project: entry.pickedProject, projects: entry.data.projects, metricKey: entry.metric,
                           date: entry.date, family: family)
            .containerBackground(for: .widget) {
                if family == .systemSmall { TractionWidgetView.background(for: entry.pickedProject) } else { Color.white }
            }
    }
}

struct LineupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LineupWidget", provider: LineupProvider()) { entry in
            LineupEntryView(entry: entry)
        }
        .configurationDisplayName("All projects")
        .description("Every running project with its next deadline.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct LineupEntryView: View {
    let entry: ProdlineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        LineupWidgetView(data: entry.data, date: entry.date, family: family)
            .containerBackground(.white, for: .widget)
    }
}
