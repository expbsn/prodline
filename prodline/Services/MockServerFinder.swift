import Foundation
import Network

/// Finds MockProject/server.py on the local network. Run with --host 0.0.0.0, the server
/// advertises `_prodline._tcp` over Bonjour with its LAN address in the TXT record.
@Observable
final class MockServerFinder {
    static let serviceType = "_prodline._tcp"
    private(set) var url: String?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.lazy.compactMap { r -> String? in
                if case .bonjour(let txt) = r.metadata { return txt["url"] }
                return nil
            }.first
            Task { @MainActor in self?.url = found }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
