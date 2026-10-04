import SwiftUI
import PhotosUI

/// The project card at full size, with the cover picked right on its face.
/// Tapping the photo area opens the photo library; the photo's color becomes the accent.
struct CardCoverEditor: View {
    let name: String
    @Binding var imageData: Data?
    @Binding var accentHex: Int
    /// The color extracted from the photo (nil without a photo or for monochrome photos).
    @Binding var photoHex: Int?
    /// True while the accent follows the photo.
    @Binding var lockedToPhoto: Bool
    var cornerLabel = "Day"
    var cornerValue = "1"
    var footnote = ""

    @State private var item: PhotosPickerItem?
    @State private var loading = false

    private var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }
    private var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ProjectCardFace(name: name, initial: initial, accent: Accent(hex: accentHex), cover: image,
                        cornerLabel: cornerLabel, cornerValue: cornerValue, footnote: footnote)
            .overlay { GeometryReader { geo in photoControls(size: geo.size) } }
            .cardFloorShadow(width: 236)
            .padding(.bottom, 30)
            .onChange(of: item) { _, new in load(new) }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: imageData)
    }

    @ViewBuilder
    private func photoControls(size: CGSize) -> some View {
        let s = size.width / 260
        // The photo area is the top ~60% of the card, above the slab.
        ZStack {
            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    Color.clear.contentShape(Rectangle())
                    if loading {
                        ProgressView().tint(image == nil ? Theme.ink : .white).scaleEffect(1.2)
                    } else if image == nil {
                        VStack(spacing: 8 * s) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 26 * s, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 64 * s, height: 64 * s)
                                .background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                            Text("Add cover")
                                .font(.ui(13 * s, .semibold))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityLabel(image == nil ? "Add cover photo" : "Change cover photo")

            if image != nil && !loading {
                Button {
                    Haptics.soft()
                    imageData = nil
                    item = nil
                    photoHex = nil
                    lockedToPhoto = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12 * s, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30 * s, height: 30 * s)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .accessibilityLabel("Remove cover photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(14 * s)
            }
        }
        // Photo area: the square artwork below the badge row, above the fade.
        .frame(width: size.width, height: size.width * 0.72)
        .padding(.top, size.height * 0.15)
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    private func load(_ new: PhotosPickerItem?) {
        guard let new else { return }
        loading = true
        Task {
            defer { loading = false }
            guard let raw = try? await new.loadTransferable(type: Data.self),
                  let square = ImageTools.squareJPEG(from: raw),
                  let img = UIImage(data: square) else { return }
            let hex = ImageTools.dominantAccentHex(img)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                imageData = square
                photoHex = hex
                lockedToPhoto = false
                if let hex {
                    accentHex = hex
                    lockedToPhoto = true
                }
            }
            Haptics.success()
        }
    }
}

/// Rainbow slider for the accent. When a photo set the color, it locks there until unlocked.
struct AccentSlider: View {
    @Binding var accentHex: Int
    @Binding var locked: Bool
    var photoHex: Int?

    @State private var dragging = false
    private let knob: CGFloat = 38
    private let steps = 48

    static func color(at hue: Double) -> Int {
        // Keep every stop usable as a button color.
        ImageTools.normalize(r: rgb(hue).0, g: rgb(hue).1, b: rgb(hue).2)
    }

    private static func rgb(_ hue: Double) -> (Double, Double, Double) {
        let c = UIColor(hue: hue, saturation: 0.78, brightness: 0.9, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    private var hue: Double {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Color(hex: accentHex)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return h
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Color").eyebrow()
                Spacer()
                if let photoHex {
                    Button {
                        Haptics.select()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            locked.toggle()
                            if locked { accentHex = photoHex }
                        }
                    } label: {
                        Label(locked ? "Matched to photo" : "Custom", systemImage: locked ? "lock.fill" : "lock.open.fill")
                            .font(.ui(13, .semibold))
                            .foregroundStyle(locked ? Theme.ink : Theme.secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                let x = hue * (w - knob)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: (0...12).map { Color(hex: Self.color(at: Double($0) / 12)) },
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 18)
                        .padding(.horizontal, knob / 2 - 9)
                        .opacity(locked ? 0.35 : 1)
                    Circle()
                        .fill(Color(hex: accentHex))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 5))
                        .overlay {
                            if locked {
                                Image(systemName: "lock.fill").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Accent(hex: accentHex).on)
                            }
                        }
                        .shadow(color: .black.opacity(dragging ? 0.25 : 0.15), radius: dragging ? 10 : 5, y: 3)
                        .frame(width: knob, height: knob)
                        .scaleEffect(dragging ? 1.15 : 1)
                        .offset(x: x)
                }
                .frame(height: 48)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if locked {
                                // First touch while locked unlocks: the user wants their own color.
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { locked = false }
                            }
                            if !dragging {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { dragging = true }
                                Haptics.soft()
                            }
                            let f = min(max((g.location.x - knob / 2) / (w - knob), 0), 0.999)
                            let stepped = (f * Double(steps)).rounded() / Double(steps)
                            let new = Self.color(at: stepped)
                            if new != accentHex {
                                accentHex = new
                                Haptics.select()
                            }
                        }
                        .onEnded { _ in withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { dragging = false } }
                )
            }
            .frame(height: 48)
        }
    }
}
