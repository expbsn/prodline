import SwiftUI
import SwiftData
import PhotosUI

/// Square cover photo + accent color. The photo's dominant color becomes the accent unless overridden.
struct CoverPicker: View {
    @Binding var imageData: Data?
    @Binding var accentHex: Int
    let initial: String

    @State private var item: PhotosPickerItem?
    @State private var extractedHex: Int?
    @State private var loading = false

    private var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }

    var body: some View {
        VStack(spacing: 22) {
            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 34, style: .continuous).fill(.white)
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Choose a square cover").font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                            Text("We'll match the colors to it").font(.ui(13)).foregroundStyle(Theme.secondary)
                        }
                    }
                    if loading { ProgressView().tint(Theme.ink) }
                }
                .frame(width: 190, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .strokeBorder(image == nil ? Theme.tertiary : .white,
                                      style: StrokeStyle(lineWidth: 2, dash: image == nil ? [8, 7] : []))
                )
                .shadow(color: .black.opacity(image == nil ? 0 : 0.15), radius: 16, y: 8)
            }
            .buttonStyle(PressableStyle())

            if image != nil {
                Button {
                    Haptics.soft()
                    withAnimation(.spring) { imageData = nil; extractedHex = nil; item = nil }
                } label: {
                    Label("Remove photo", systemImage: "xmark").font(.ui(14, .semibold)).foregroundStyle(Theme.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(image == nil ? "Or pick a color" : "Accent color").eyebrow()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 12) {
                    if let extractedHex {
                        swatch(extractedHex, label: "photo")
                    }
                    ForEach(Theme.swatches, id: \.self) { swatch($0) }
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: accentHex) },
                        set: { accentHex = $0.hex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 44, height: 44)
                }
            }
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            loading = true
            Task {
                defer { loading = false }
                guard let raw = try? await new.loadTransferable(type: Data.self),
                      let square = ImageTools.squareJPEG(from: raw),
                      let img = UIImage(data: square) else { return }
                let hex = ImageTools.dominantAccentHex(img)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    imageData = square
                    extractedHex = hex
                    if let hex { accentHex = hex }
                }
                Haptics.success()
            }
        }
    }

    private func swatch(_ hex: Int, label: String? = nil) -> some View {
        let selected = accentHex == hex
        return Button {
            Haptics.select()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { accentHex = hex }
        } label: {
            ZStack {
                Circle().fill(Color(hex: hex))
                if label != nil {
                    Image(systemName: "photo").font(.system(size: 13, weight: .bold)).foregroundStyle(Accent(hex: hex).on)
                }
            }
            .frame(width: 44, height: 44)
            .padding(4)
            .overlay(Circle().strokeBorder(selected ? Theme.ink : .clear, lineWidth: 2.5))
            .scaleEffect(selected ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == nil ? "Color" : "Color from photo")
    }
}

/// Four short steps with the card building itself at the top.
struct CreateProjectFlow: View {
    let profile: Profile
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(CelebrationCenter.self) private var celebration
    @Query private var projects: [Project]

    @State private var step = 0
    @State private var name = ""
    @State private var imageData: Data?
    @State private var accentHex = Theme.swatches[0]
    @State private var startDate = Date.now.startOfDay
    @State private var buildDays = 14
    @State private var endpoint = ""
    @State private var apiKey = ""
    @State private var probe: ProbeState = .idle
    @FocusState private var nameFocused: Bool

    private let steps = 4
    private var accent: Accent { Accent(hex: accentHex) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var initial: String { trimmedName.first.map { String($0).uppercased() } ?? "?" }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: 26) {
                    ProjectCardFace(name: trimmedName, initial: initial, accent: accent,
                                    cover: imageData.flatMap(UIImage.init(data:)),
                                    cornerLabel: "Day", cornerValue: "1",
                                    footnote: "Building · \(buildDays)d")
                        .frame(width: step == 0 ? 190 : 128)
                        .rotation3DEffect(.degrees(step.isMultiple(of: 2) ? -4 : 4), axis: (0, 1, 0), perspective: 0.5)
                        .shadow(color: accent.base.opacity(0.3), radius: 22, y: 12)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: step)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: accentHex)
                        .padding(.top, 8)

                    Group {
                        switch step {
                        case 0: nameStep
                        case 1: coverStep
                        case 2: scheduleStep
                        default: connectStep
                        }
                    }
                    .id(step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .background(Theme.background.ignoresSafeArea())
        .environment(\.accent, accent)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(!trimmedName.isEmpty)
        .onAppear {
            buildDays = profile.buildDays
            startDate = max(ScheduleEngine.nextProjectDate(projects: projects, profile: profile), .now.startOfDay)
            let used = Set(projects.map(\.accentHex))
            accentHex = Theme.swatches.first { !used.contains($0) } ?? Theme.swatches[projects.count % Theme.swatches.count]
            nameFocused = true
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                Haptics.soft()
                if step == 0 { dismiss() } else { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step -= 1 } }
            } label: {
                Image(systemName: step == 0 ? "xmark" : "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 36, height: 36)
            }
            ChunkyProgressBar(value: Double(step + 1) / Double(steps), height: 14)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button(step == steps - 1 ? "Create project" : "Continue", action: next)
                .buttonStyle(.chunky)
                .disabled(step == 0 && trimmedName.isEmpty)
            if step == 1 && imageData == nil {
                Text("A photo makes it yours. You can add one later.").font(.ui(13)).foregroundStyle(Theme.secondary)
            }
            if step == steps - 1 && endpoint.isEmpty {
                Text("No endpoint yet? You'll see sample data until you connect.").font(.ui(13)).foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Steps

    private func stepTitle(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).eyebrow(accent.text)
            Text(title).font(.display(32, 750)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle("Step 1 of 4", "What are you building?")
            TextField("Project name", text: $name)
                .font(.display(28, 650))
                .focused($nameFocused)
                .submitLabel(.continue)
                .onSubmit(next)
                .padding(.horizontal, 18)
                .frame(height: 66)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(nameFocused ? accent.base : Theme.line, lineWidth: 2))
        }
    }

    private var coverStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 2 of 4", "Give it a face")
            CoverPicker(imageData: $imageData, accentHex: $accentHex, initial: initial)
                .frame(maxWidth: .infinity)
        }
    }

    private var scheduleStep: some View {
        let draft = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                            buildDays: buildDays, observeDays: profile.observeDays)
        let ms = ScheduleEngine.makeMilestones(for: draft, weekdayMask: profile.milestoneWeekdayMask)
        return VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 3 of 4", "Set the clock")
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Starts").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().tint(accent.base)
                }
                Divider()
                HStack {
                    Text("Build phase").font(.ui(17, .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(buildDays.durationText).font(.display(20, 700)).foregroundStyle(accent.text)
                        .contentTransition(.numericText())
                }
                ChunkySlider(value: $buildDays, range: 3...42)
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Your deadlines").eyebrow()
                ForEach(ms, id: \.id) { m in
                    HStack {
                        Image(systemName: m.isLaunch ? "flag.checkered" : (m.title == "Traction review" ? "chart.line.uptrend.xyaxis" : "checkmark.circle"))
                            .foregroundStyle(accent.text)
                            .frame(width: 22)
                        Text(m.title).font(.ui(15, .semibold)).foregroundStyle(Theme.ink)
                        Spacer()
                        Text(m.dueDate.shortDay).font(.ui(14)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            .card()
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle("Step 4 of 4", "Connect your numbers")
            ConnectionFields(endpoint: $endpoint, apiKey: $apiKey, probe: $probe)
        }
    }

    // MARK: Actions

    private func next() {
        guard !(step == 0 && trimmedName.isEmpty) else { return }
        if step < steps - 1 {
            nameFocused = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { step += 1 }
        } else {
            create()
        }
    }

    private func create() {
        let p = Project(name: trimmedName, accentHex: accentHex, startDate: startDate,
                        buildDays: buildDays, observeDays: profile.observeDays)
        p.coverImage = imageData
        p.endpoint = endpoint.trimmingCharacters(in: .whitespaces)
        Keychain.set(apiKey.trimmingCharacters(in: .whitespaces), for: p.id.uuidString)
        ScheduleEngine.createProject(p, profile: profile, context: context)
        if profile.remindersEnabled { Task { _ = await Notifier.requestAuth() } }
        celebration.fire(title: "\(p.name) is live", subtitle: "Build phase: \(buildDays.durationText). Let's ship.", accent: p.accent)
        onCreated(p.id)
        dismiss()
    }
}
