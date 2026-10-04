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
