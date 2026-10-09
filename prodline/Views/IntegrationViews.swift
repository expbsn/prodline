import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The services connected to a project, in the Connection sheet.
struct IntegrationsSection: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @State private var picking = false
    @State private var editing: Integration?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Integrations").eyebrow()
                Text("Downloads, revenue and visitors straight from the services you use. Keys stay in your Keychain.")
                    .font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !project.integrations.isEmpty {
                VStack(spacing: 0) {
                    ForEach(project.integrations) { i in
                        Button { editing = i } label: { IntegrationRow(kind: i.kind, caption: i.kind.provides, chevron: true) }
                            .buttonStyle(.plain)
                        if i.id != project.integrations.last?.id { Divider().padding(.leading, 56) }
                    }
                }
                .card(padding: 14, radius: 20)
            }
            Button {
                picking = true
            } label: {
                Label("Add integration", systemImage: "plus")
            }
            .buttonStyle(.chunky(.neutral, height: 50))
        }
        .sheet(isPresented: $picking) {
            IntegrationPicker(connected: Set(project.integrations.map(\.kind))) { kind in
                picking = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    editing = Integration(kind: kind)
                }
            }
        }
        .sheet(item: $editing) { i in
            IntegrationEditor(project: project, integration: i, isNew: !project.integrations.contains { $0.id == i.id })
        }
    }
}

struct IntegrationRow: View {
    let kind: IntegrationKind
    let caption: String
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            IntegrationIcon(kind: kind, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.title).font(.ui(16, .semibold)).foregroundStyle(Theme.ink)
                Text(caption).font(.ui(13)).foregroundStyle(Theme.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct IntegrationIcon: View {
    let kind: IntegrationKind
    var size: CGFloat = 40

    var body: some View {
        let accent = Accent(hex: kind.colorHex)
        if let logo = kind.logo, logo.isIcon {
            Image(logo.asset).resizable().scaledToFit()
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(accent.base)
                .overlay {
                    if let logo = kind.logo {
                        Image(logo.asset).resizable().scaledToFit().frame(width: size * 0.7)
                    } else {
                        Image(systemName: kind.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(accent.on)
                    }
                }
                .frame(width: size, height: size)
        }
    }
}

/// Every service, grouped: stores, revenue, analytics, hosting, newsletters, social.
struct IntegrationPicker: View {
    let connected: Set<IntegrationKind>
    var onPick: (IntegrationKind) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add integration").display(26, 750).foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(IntegrationKind.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.rawValue).eyebrow()
                            VStack(spacing: 0) {
                                let kinds = IntegrationKind.allCases.filter { $0.group == group }
                                ForEach(kinds) { kind in
                                    Button {
                                        Haptics.select()
                                        onPick(kind)
                                    } label: {
                                        IntegrationRow(kind: kind, caption: connected.contains(kind) ? "Connected · add another" : kind.provides,
                                                       chevron: true)
                                    }
                                    .buttonStyle(.plain)
                                    if kind != kinds.last { Divider().padding(.leading, 56) }
                                }
                            }
                            .card(padding: 14, radius: 20)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

/// Settings and key for one service, with a test that shows what it found.
struct IntegrationEditor: View {
    @Bindable var project: Project
    let isNew: Bool
    /// Off for a project that doesn't exist yet (onboarding): nothing to save or refresh until it's created.
    var live = true
    @State private var integration: Integration
    @State private var secret: String
    @State private var test: TestState = .idle
    @State private var importing = false
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(DataRefresher.self) private var refresher
    @FocusState private var focus: String?

    enum TestState: Equatable {
        case idle, running
        case ok([(String, Double)], days: Int)
        case failed(String)

        static func == (a: TestState, b: TestState) -> Bool {
            switch (a, b) {
            case (.idle, .idle), (.running, .running): true
            case let (.failed(x), .failed(y)): x == y
            case let (.ok(x, d1), .ok(y, d2)): d1 == d2 && x.map(\.0) == y.map(\.0) && x.map(\.1) == y.map(\.1)
            default: false
            }
        }
    }

    init(project: Project, integration: Integration, isNew: Bool, live: Bool = true) {
        self.project = project
        self.isNew = isNew
        self.live = live
        _integration = State(initialValue: integration)
        _secret = State(initialValue: Keychain.get(integration.keychainAccount) ?? "")
    }

    private var kind: IntegrationKind { integration.kind }
    private var canSave: Bool { integration.isComplete && (!kind.needsSecret || !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IntegrationIcon(kind: kind, size: 36)
                Text(kind.title).display(24, 750).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(kind.provides + ", counted from the project's start.")
                        .font(.ui(15)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    steps

                    ForEach(kind.fields) { f in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(f.optional ? "\(f.label) · optional" : f.label).eyebrow()
                            TextField("", text: binding(f.key), prompt: Text(verbatim: f.placeholder).foregroundStyle(Theme.tertiary))
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .focused($focus, equals: f.key)
                                .inputField(focused: focus == f.key)
                        }
                    }
                    if kind.needsSecret { secretField }
                    testButton
                    testResult
                    if !isNew {
                        Button("Remove \(kind.title)", role: .destructive) { confirmRemove = true }
                            .font(.ui(15, .semibold))
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
            .bottomActionBar {
                Button(isNew ? "Connect" : "Save") { save() }
                    .buttonStyle(.chunky)
                    .disabled(!canSave)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, project.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text, .item]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) { secret = text }
        }
        .confirmationDialog("Remove \(kind.title)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { remove() }
        } message: {
            Text("Numbers it already brought in stay in the history.")
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where to find these").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
            ForEach(Array(kind.steps.enumerated()), id: \.offset) { n, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(n + 1)").font(.ui(12, .bold)).foregroundStyle(Theme.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.background))
                    Text(step).font(.ui(14)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(padding: 16, radius: 20)
    }

    @ViewBuilder
    private var secretField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.secretLabel).eyebrow()
            if kind == .appStore {
                ZStack(alignment: .topLeading) {
                    if secret.isEmpty {
                        Text(kind.secretPlaceholder).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, 16).padding(.vertical, 14)
                    }
                    TextEditor(text: $secret)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focus, equals: "secret")
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .frame(height: 120)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focus == "secret" ? Theme.ink : Theme.line, lineWidth: 2))
                Button { importing = true } label: {
                    Label("Choose the .p8 file", systemImage: "doc.badge.plus").font(.ui(14, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
            } else {
                SecureField("", text: $secret, prompt: Text(kind.secretPlaceholder).foregroundStyle(Theme.tertiary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: "secret")
                    .inputField(focused: focus == "secret")
            }
            Label("Stored in your Keychain, never in iCloud data.", systemImage: "lock.fill")
                .font(.ui(12)).foregroundStyle(Theme.secondary)
        }
    }

    private var testButton: some View {
        Button {
            focus = nil
            runTest()
        } label: {
            HStack(spacing: 8) {
                if test == .running { ProgressView().tint(Theme.ink) }
                Text(test == .running ? "Testing" : "Test connection")
            }
        }
        .buttonStyle(.chunky(.neutral, height: 50))
        .disabled(!canSave || test == .running)
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle, .running: EmptyView()
        case .failed(let msg):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text(msg).font(.ui(14, .medium)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 14, radius: 18)
        case let .ok(values, days):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text("Connected").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    if days > 0 { Text("\(days) days of history").eyebrow(size: 10) }
                }
                ForEach(values, id: \.0) { key, value in
                    HStack {
                        Text(key == "revenue" ? "Revenue" : key == "visits" ? "Visitors" : IntegrationMetric.title(key))
                            .font(.ui(15)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(key == "revenue" ? MetricKey.money(value) : IntegrationMetric.format(key, value))
                            .font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .card(padding: 14, radius: 18)
        }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { integration.fields[key] ?? "" }, set: { integration.fields[key] = $0 })
    }

    private func runTest() {
        test = .running
        let i = integration, s = secret.trimmingCharacters(in: .whitespacesAndNewlines), start = project.startDate
        Task {
            do {
                let r = try await IntegrationCache.shared.result(for: i, secret: s, start: start, session: .shared, force: true)
                let values = r.totals.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { test = .ok(values, days: r.daily.count) }
                Haptics.success()
            } catch {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { test = .failed(error.localizedDescription) }
                Haptics.warning()
            }
        }
    }

    private func save() {
        var all = project.integrations
        if let n = all.firstIndex(where: { $0.id == integration.id }) { all[n] = integration } else { all.append(integration) }
        project.integrations = all
        Keychain.set(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: integration.keychainAccount)
        Haptics.success()
        if live {
            try? context.save()
            let p = project
            Task { await refresher.refresh(projects: [p], context: context, force: true) }
        }
        dismiss()
    }

    private func remove() {
        project.integrations = project.integrations.filter { $0.id != integration.id }
        Keychain.delete(integration.keychainAccount)
        let i = integration
        Task { await IntegrationCache.shared.forget(i) }
        if live { try? context.save() }
        dismiss()
    }
}
