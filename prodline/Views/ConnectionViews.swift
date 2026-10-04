import SwiftUI

enum ProbeState: Equatable {
    case idle
    case running
    case ok(latencyMs: Int, metrics: [MetricsPayload.Metric], historyPoints: Int)
    case failed(String)
}

enum ConnectionProbe {
    static func run(endpoint: String, apiKey: String) async -> ProbeState {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true, url.host() != nil else {
            return .failed(MetricsError.invalidURL.localizedDescription)
        }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else { return .failed("Add the API key first.") }
        let client = RESTMetricsClient(url: url, apiKey: apiKey.trimmingCharacters(in: .whitespaces))
        let start = Date()
        do {
            let payload = try await client.fetch(since: nil)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return .ok(latencyMs: ms, metrics: payload.metrics, historyPoints: payload.history?.count ?? 0)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Endpoint + key fields with a test button and a readable result.
struct ConnectionFields: View {
    @Binding var endpoint: String
    @Binding var apiKey: String
    @Binding var probe: ProbeState
    @Environment(\.accent) private var accent
    @FocusState private var focus: Field?
    @State private var showSpec = false
    private enum Field { case url, key }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Endpoint").eyebrow()
                TextField("", text: $endpoint, prompt: Text(verbatim: "https://yourapp.com/api/prodline").foregroundStyle(Theme.tertiary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($focus, equals: .url)
                    .inputField(focused: focus == .url)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("API key").eyebrow()
                SecureField("", text: $apiKey, prompt: Text("Paste the project's key").foregroundStyle(Theme.tertiary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .key)
                    .inputField(focused: focus == .key)
                Label("Stored in your Keychain, never in iCloud data.", systemImage: "lock.fill")
                    .font(.ui(12)).foregroundStyle(Theme.secondary)
            }

            Button {
                focus = nil
                probe = .running
                Task {
                    let result = await ConnectionProbe.run(endpoint: endpoint, apiKey: apiKey)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { probe = result }
                    if case .ok = result { Haptics.success() } else { Haptics.warning() }
                }
            } label: {
                HStack(spacing: 8) {
                    if probe == .running { ProgressView().tint(Theme.ink) }
                    Text(probe == .running ? "Testing" : "Test connection")
                }
            }
            .buttonStyle(.chunky(.neutral, height: 50))
            .disabled(endpoint.isEmpty || probe == .running)

            ProbeResultView(probe: probe)

            Button {
                Haptics.soft()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showSpec.toggle() }
            } label: {
                HStack {
                    Text("What should my endpoint return?").font(.ui(15, .semibold))
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(showSpec ? 180 : 0))
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if showSpec { APISpecView() .transition(.opacity.combined(with: .move(edge: .top))) }

            GuideDisclosure(title: "How do I send goals?") { GoalsGuideView() }
        }
    }
}

struct ProbeResultView: View {
    let probe: ProbeState

    var body: some View {
        switch probe {
        case .idle, .running:
            EmptyView()
        case .failed(let msg):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text(msg).font(.ui(14, .medium)).foregroundStyle(Theme.ink)
            }
            .card(padding: 14, radius: 18)
        case let .ok(latency, metrics, history):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                    Text("Connected · \(latency) ms").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(history) history pts").eyebrow(size: 10)
                }
                ForEach(metrics, id: \.key) { m in
                    HStack {
                        Text(m.key).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Text(m.key == "revenue" ? MetricKey.money(m.value) : MetricKey.count(m.value))
                            .font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    }
                }
            }
            .card(padding: 14, radius: 18)
        }
    }
}

struct APISpecView: View {
    static let example = """
    GET <endpoint>?since=<ISO8601>
    Authorization: Bearer <api key>

    {
      "schemaVersion": 1,
      "asOf": "2026-10-04T12:00:00Z",
      "metrics": [
        { "key": "visits", "value": 1234 },
        { "key": "social_views", "value": 560 },
        { "key": "revenue", "value": 56.7, "unit": "USD" },
        { "key": "signups", "value": 42 }
      ],
      "history": [
        { "asOf": "2026-10-04T11:00:00Z",
          "metrics": [ { "key": "visits", "value": 1180 } ] }
      ]
    }
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Values are running totals. `history` is optional and only needs points newer than `since`. Any extra metric keys show up as custom metrics.")
                .font(.ui(13)).foregroundStyle(Theme.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.example)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.background))
            Button {
                UIPasteboard.general.string = Self.example
                Haptics.success()
            } label: {
                Label("Copy example", systemImage: "doc.on.doc").font(.ui(14, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
        }
        .card(padding: 14, radius: 18)
    }
}

// MARK: - GitHub

enum RepoCheck: Equatable {
    case idle, running
    case ok(GitHubSnapshot)
    case failed(String)
}

/// Repo + optional token. Linking a repo personalizes goals (issues), AI suggestions (README) and nudges (commits).
struct GitHubFields: View {
    @Binding var repo: String
    @Binding var token: String
    @Binding var check: RepoCheck
    @FocusState private var focus: Field?
    private enum Field { case repo, token }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GitHub repo").eyebrow()
                    Spacer()
                    Text("Optional").font(.ui(12)).foregroundStyle(Theme.tertiary)
                }
                TextField("", text: $repo, prompt: Text(verbatim: "owner/repo").foregroundStyle(Theme.tertiary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($focus, equals: .repo)
                    .inputField(focused: focus == .repo)
                SecureField("", text: $token, prompt: Text("Token, only for private repos").foregroundStyle(Theme.tertiary))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .token)
                    .inputField(focused: focus == .token)
                Text("Issues in GitHub milestones or labeled “prodline” become checkpoint goals and close themselves. Your README guides suggestions, and quiet weeks get a nudge.")
                    .font(.ui(12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !repo.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    focus = nil
                    run()
                } label: {
                    HStack(spacing: 8) {
                        if check == .running { ProgressView().tint(Theme.ink) }
                        Text(check == .running ? "Checking" : "Check repo")
                    }
                }
                .buttonStyle(.chunky(.neutral, height: 50))
                .disabled(check == .running)
            }

            switch check {
            case .idle, .running: EmptyView()
            case .failed(let msg):
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                    Text(msg).font(.ui(14, .medium)).foregroundStyle(Theme.ink)
                }
                .card(padding: 14, radius: 18)
            case .ok(let snap):
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success)
                        Text(GitHubRepoRef(repo)?.slug ?? repo).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                    }
                    if !snap.description.isEmpty {
                        Text(snap.description).font(.ui(14)).foregroundStyle(Theme.secondary)
                    }
                    let planned = snap.issues.filter(\.isPlanned)
                    Text("\(planned.count) planned issue\(planned.count == 1 ? "" : "s") · \(snap.milestones.count) milestone\(snap.milestones.count == 1 ? "" : "s")" +
                         (snap.lastCommit.map { " · last commit \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                        .font(.ui(13)).foregroundStyle(Theme.secondary)
                }
                .card(padding: 14, radius: 18)
            }
        }
        .onChange(of: repo) { check = .idle }
    }

    private func run() {
        guard let ref = GitHubRepoRef(repo) else { check = .failed(GitHubError.badRepo.localizedDescription); return }
        check = .running
        let client = GitHubClient(repo: ref, token: token.isEmpty ? nil : token, base: GitHubService.base)
        Task {
            do {
                let snap = try await client.fetch()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { check = .ok(snap) }
                Haptics.success()
            } catch {
                withAnimation { check = .failed(error.localizedDescription) }
                Haptics.warning()
            }
        }
    }
}

// MARK: - Goals guide

/// Expandable "how does this work" row, same look as the endpoint spec.
struct GuideDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Haptics.soft()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { open.toggle() }
            } label: {
                HStack {
                    Text(title).font(.ui(15, .semibold))
                    Spacer()
                    Image(systemName: "chevron.down").rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(Theme.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open { content.transition(.opacity.combined(with: .move(edge: .top))) }
        }
    }
}

/// Everything about where checkpoint goals come from and how they complete.
struct GoalsGuideView: View {
    static let example = """
    "goals": [
      { "id": "onboarding",
        "title": "Onboarding flow live",
        "checkpoint": 3,
        "done": false },
      { "id": "launch-post",
        "title": "Launch post published",
        "due": "2026-10-08T00:00:00Z" },
      { "id": "signups-500",
        "title": "500 signups",
        "checkpoint": 4,
        "metric": { "key": "signups", "target": 500 } }
    ]
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            item("checkmark.circle", "Goals complete checkpoints",
                 "Each checkpoint can hold a few concrete goals. When all are done, the checkpoint completes itself, with XP and streak as if you tapped it. Checkpoints without goals are ticked by hand.")

            item("bolt.fill", "From your API",
                 "Add a `goals` list to the same JSON your endpoint returns. `checkpoint` is the position in the project's deadlines (checkpoints, then Ship it, then Traction review). Use `due` instead to place it by date. `done: true` ticks it. A `metric` target ticks itself when the number gets there. Goals you remove from the list disappear unless already done.")
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(Self.example)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .padding(14)
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.background))
                Button {
                    UIPasteboard.general.string = Self.example
                    Haptics.success()
                } label: {
                    Label("Copy example", systemImage: "doc.on.doc").font(.ui(14, .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.ink)
            }
            .padding(.leading, 34)

            item("chevron.left.forwardslash.chevron.right", "From GitHub",
                 "Put issues in a GitHub milestone, or label them “prodline”. A milestone with a due date lands on the first checkpoint on or after it; without a date, your first milestone maps to checkpoint 1, the second to checkpoint 2, and so on. Closing the issue ticks the goal. Pull requests are ignored.")

            item("sparkles", "Suggestions",
                 "With Apple Intelligence, Prodline drafts goals on your iPhone from the description, README and open issues. Nothing leaves the device. Goals from your API or GitHub replace suggestions on the same checkpoint.")

            item("chart.line.uptrend.xyaxis", "Traction targets",
                 "After launch, the traction review gets stretch targets for visits and revenue based on last week's pace. They tick themselves.")
        }
        .card(padding: 16, radius: 18)
    }

    private func item(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                Text(LocalizedStringKey(text)).font(.ui(14)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
