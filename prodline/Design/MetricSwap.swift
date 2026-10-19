import SwiftUI

/// The long-press menu on a metric tile: every other number there is, to show in its place.
struct MetricSwapMenu: View {
    let key: String
    let shown: [String]
    let available: [String]
    let value: (String) -> Double?
    var onPick: (String) -> Void

    var body: some View {
        let others = available.filter { !shown.contains($0) }
        Section("Show instead of \(Stat.title(key))") {
            ForEach(others, id: \.self) { k in
                Button {
                    Haptics.select()
                    onPick(k)
                } label: {
                    // Title, value as the subtitle, symbol: the menu lays these out itself.
                    Text(Stat.title(k))
                    if let v = value(k) { Text(Stat.format(k, v)) }
                    Image(systemName: Stat.symbol(k))
                }
            }
        }
    }
}

/// The small note under the tiles when there are more numbers than fit.
struct MetricSwapHint: View {
    #if os(macOS)
    private static let text = "Click a number with two fingers to swap it for another one"
    private static let symbol = "cursorarrow.click.2"
    #else
    private static let text = "Hold a number to swap it for another one"
    private static let symbol = "hand.tap.fill"
    #endif

    var body: some View {
        Label(Self.text, systemImage: Self.symbol)
            .font(.ui(12, .medium))
            .foregroundStyle(Theme.secondary)
            .labelStyle(.titleAndIcon)
            .imageScale(.small)
    }
}
