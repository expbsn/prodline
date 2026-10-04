import SwiftUI

// MARK: - Chunky button (Duolingo-style 3D press)

struct ChunkyButtonStyle: ButtonStyle {
    var color: Color = Theme.blue
    var shadow: Color = Theme.blueDark
    var foreground: Color = .white
    var border: Color? = nil
    var height: CGFloat = 52
    var fullWidth = true
    var uppercase = true

    private let depth: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.rounded(height < 48 ? 14 : 16, .heavy))
            .textCase(uppercase ? .uppercase : nil)
            .tracking(uppercase ? 0.8 : 0)
            .foregroundStyle(foreground)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border, lineWidth: 2)
                }
            }
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(shadow)
                    .offset(y: pressed ? 0 : depth)
            }
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: pressed)
            .onChange(of: pressed) { _, isDown in if isDown { Haptics.tap() } }
    }
}

extension ButtonStyle where Self == ChunkyButtonStyle {
    static var chunky: ChunkyButtonStyle { ChunkyButtonStyle() }

    static func chunky(_ kind: ChunkyKind, height: CGFloat = 52, fullWidth: Bool = true) -> ChunkyButtonStyle {
        switch kind {
        case .primary:
            ChunkyButtonStyle(height: height, fullWidth: fullWidth)
        case .success:
            ChunkyButtonStyle(color: Theme.green, shadow: Theme.greenDark, height: height, fullWidth: fullWidth)
        case .danger:
            ChunkyButtonStyle(color: Theme.red, shadow: Theme.redDark, height: height, fullWidth: fullWidth)
        case .secondary:
            ChunkyButtonStyle(color: .white, shadow: Theme.line, foreground: Theme.blue,
                              border: Theme.line, height: height, fullWidth: fullWidth)
        case .dangerOutline:
            ChunkyButtonStyle(color: .white, shadow: Theme.line, foreground: Theme.red,
                              border: Theme.line, height: height, fullWidth: fullWidth)
        }
    }
}

enum ChunkyKind { case primary, success, danger, secondary, dangerOutline }

// MARK: - Card

struct CardModifier: ViewModifier {
    var tint: Color = Theme.line
    var fill: Color = .white
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint, lineWidth: 2))
    }
}

extension View {
    func card(tint: Color = Theme.line, fill: Color = .white) -> some View {
        modifier(CardModifier(tint: tint, fill: fill))
    }

    func chunkyField(focused: Bool = false) -> some View {
        self.font(.rounded(17, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Theme.blue : Theme.line, lineWidth: 2))
    }
}

/// Subtle squish when a card-like row is pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in if down { Haptics.soft() } }
    }
}

// MARK: - Chip

struct ChunkyChip: View {
    let title: String
    let isOn: Bool
    var color: Color = Theme.blue
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.select()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { action() }
        } label: {
            Text(title)
                .font(.rounded(14, .heavy))
                .foregroundStyle(isOn ? color : Theme.inkLight)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(minWidth: 40, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isOn ? color.opacity(0.12) : .white))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? color : Theme.line, lineWidth: 2))
                .scaleEffect(isOn ? 1.03 : 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress

struct ChunkyProgressBar: View {
    var value: Double
    var color: Color = Theme.green
    var height: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .overlay(alignment: .top) {
                        Capsule().fill(.white.opacity(0.3))
                            .frame(height: height * 0.25)
                            .padding(.horizontal, height * 0.4)
                            .padding(.top, height * 0.2)
                    }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: value)
        }
        .frame(height: height)
    }
}

// MARK: - Slider

struct ChunkySlider: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var color: Color = Theme.blue
    @State private var dragging = false

    private let knob: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = CGFloat(range.upperBound - range.lowerBound)
            let frac = span == 0 ? 0 : CGFloat(value - range.lowerBound) / span
            let x = frac * (w - knob)

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line).frame(height: 16)
                Capsule().fill(color).frame(width: x + knob / 2, height: 16)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(color, lineWidth: 5))
                    .background(Circle().fill(color.opacity(0.35)).offset(y: 4))
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: x)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { dragging = true }
                            Haptics.soft()
                        }
                        let f = min(max((g.location.x - knob / 2) / (w - knob), 0), 1)
                        let new = range.lowerBound + Int((f * span).rounded())
                        if new != value {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) { value = new }
                            Haptics.select()
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { dragging = false }
                    }
            )
        }
        .frame(height: 44)
    }
}

// MARK: - Pills

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(icon).font(.system(size: 18))
            Text(value).font(.rounded(17, .heavy)).foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 2))
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.rounded(20, .heavy))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Mascot

struct Pip: View {
    var size: CGFloat = 80
    var cheering = false
    @State private var blink = false
    @State private var bounce = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                .fill(Theme.blue)
                .frame(width: size, height: size * 0.9)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.42, style: .continuous)
                        .fill(Theme.blueDark)
                        .frame(width: size, height: size * 0.9)
                        .offset(y: size * 0.06)
                )
            HStack(spacing: size * 0.14) { eye; eye }
                .offset(y: -size * 0.1)
            Smile(open: cheering)
                .fill(.white)
                .frame(width: size * 0.3, height: cheering ? size * 0.18 : size * 0.1)
                .offset(y: size * 0.16)
        }
        .frame(width: size, height: size)
        .offset(y: bounce ? -size * 0.05 : 0)
        .task {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bounce = true }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.2...4)))
                withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Ellipse().fill(.white)
            .frame(width: size * 0.22, height: blink ? size * 0.03 : size * 0.28)
            .overlay(
                Circle().fill(Theme.ink)
                    .frame(width: size * 0.1, height: size * 0.1)
                    .opacity(blink ? 0 : 1)
            )
    }
}

private struct Smile: Shape {
    var open: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        p.closeSubpath()
        return p
    }
}

// MARK: - Confetti & celebration

@Observable
final class CelebrationCenter {
    struct Banner: Equatable { var title: String; var subtitle: String; var tint: Bool }
    var banner: Banner?
    var confettiID: UUID?
    private var dismissTask: Task<Void, Never>?

    func fire(title: String, subtitle: String, confetti: Bool = true) {
        Haptics.success()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            banner = Banner(title: title, subtitle: subtitle, tint: true)
        }
        if confetti { confettiID = UUID() }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.banner = nil }
        }
    }

    func nudge(title: String, subtitle: String) {
        Haptics.warning()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            banner = Banner(title: title, subtitle: subtitle, tint: false)
        }
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { self?.banner = nil }
        }
    }
}

struct CelebrationOverlay: View {
    @Environment(CelebrationCenter.self) private var center

    var body: some View {
        ZStack(alignment: .top) {
            if let id = center.confettiID {
                ConfettiView().id(id).transition(.opacity)
            }
            if let b = center.banner {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.title).font(.rounded(20, .heavy))
                    Text(b.subtitle).font(.rounded(14, .semibold)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(b.tint ? Theme.green : Theme.orange))
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(b.tint ? Theme.greenDark : Theme.orangeDark).offset(y: 4))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

struct ConfettiView: View {
    private struct Particle {
        let x: CGFloat, delay: Double, speed: CGFloat, wobble: Double, phase: Double
        let spin: Double, size: CGFloat, color: Color
    }

    @State private var start = Date()
    @State private var particles: [Particle] = {
        let colors: [Color] = [Theme.blue, Theme.green, Theme.yellow, Theme.orange, Theme.purple, Theme.red]
        return (0..<70).map { _ in
            Particle(x: .random(in: 0...1), delay: .random(in: 0...0.5), speed: .random(in: 260...520),
                     wobble: .random(in: 2...5), phase: .random(in: 0...6), spin: .random(in: -6...6),
                     size: .random(in: 7...12), color: colors.randomElement()!)
        }
    }()

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            Canvas { gc, size in
                for p in particles {
                    let lt = t - p.delay
                    guard lt > 0 else { continue }
                    let y = -20 + CGFloat(lt) * p.speed + CGFloat(lt * lt) * 120
                    let x = p.x * size.width + CGFloat(sin(lt * p.wobble + p.phase)) * 22
                    guard y < size.height + 20 else { continue }
                    var c = gc
                    c.opacity = max(0, 1 - lt / 3.2)
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(lt * p.spin))
                    c.fill(Path(roundedRect: CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.size * 0.66),
                                cornerRadius: 2), with: .color(p.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
