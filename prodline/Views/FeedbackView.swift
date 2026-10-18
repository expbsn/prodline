import SwiftUI
import PhotosUI
import MessageUI
import UIKit

// MARK: - Feedback
//
// Bugs and ideas go to the support address by email, with screenshots attached and the app version,
// build, iOS version and device added at the bottom. Opened from the Dash header, or from the prompt
// that shows up right after a screenshot is taken in the app (that screen is attached already).

enum Feedback {
    static let address = "kianpal731@gmail.com"

    static var subject: String { "Prodline feedback (\(version))" }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// "iPhone16,2"-style model identifier.
    static var model: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    static var details: String {
        #if DEBUG
        let build = "Debug"
        #else
        let build = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "TestFlight" : "App Store"
        #endif
        return "Prodline \(version) · \(build) · iOS \(UIDevice.current.systemVersion) · \(model)"
    }

    static func body(_ message: String) -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text.isEmpty ? "" : text + "\n\n") + "—\n" + details
    }

    /// The app's current screen as an image (the key window, drawn as it is right now).
    @MainActor
    static func captureScreen() -> UIImage? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    }

    /// Without a Mail account: a plain mailto link (no attachments).
    static func mailtoURL(_ message: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        c.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body(message))]
        return c.url
    }
}

struct FeedbackSheet: View {
    /// A screen captured when the sheet was opened from the screenshot prompt.
    var screenshot: UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(CelebrationCenter.self) private var celebration
    @State private var message = ""
    @State private var images: [UIImage] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var composing = false
    @FocusState private var focused: Bool

    private let maxImages = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Send feedback").display(30, 750).foregroundStyle(Theme.ink)
                    Text("Bugs, ideas, anything that felt off. It goes straight to the developer.")
                        .font(.ui(15)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(.bottom, 22)

            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What happened, or what would make Prodline better?")
                        .font(.ui(17)).foregroundStyle(Theme.tertiary)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $message)
                    .font(.ui(17)).foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .focused($focused)
            }
            .frame(height: 170)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(focused ? Theme.ink : Theme.line, lineWidth: 2))

            Text("Screenshots").eyebrow().padding(.top, 22).padding(.bottom, 10)
            HStack(spacing: 10) {
                ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 72, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                Haptics.tap()
                                images.remove(at: i)
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.inverse)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(Theme.ink))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove screenshot")
                        }
                }
                if images.count < maxImages {
                    PhotosPicker(selection: $picks, maxSelectionCount: maxImages - images.count, matching: .screenshots) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                            Text("Add").font(.ui(12, .semibold))
                        }
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 72, height: 110)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.inset))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.tertiary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .accessibilityLabel("Add screenshots")
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 24)

            Text(Feedback.details).font(.ui(12)).foregroundStyle(Theme.tertiary).padding(.bottom, 12)
            Button("Send") { send() }
                .buttonStyle(.chunky)
                .environment(\.accent, .neutral)
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
        .onAppear {
            if let screenshot, images.isEmpty { images = [screenshot] }
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
                       images.count < maxImages {
                        images.append(img)
                    }
                }
                picks = []
            }
        }
        .sheet(isPresented: $composing) {
            MailComposer(message: message, images: images) { sent in
                composing = false
                if sent {
                    dismiss()
                    celebration.fire(title: "Thanks!", subtitle: "Your feedback is on its way", confetti: false)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func send() {
        focused = false
        if MFMailComposeViewController.canSendMail() {
            composing = true
        } else if let url = Feedback.mailtoURL(message) {
            // No Mail account on this phone: hand off to whatever handles mailto (screenshots can't come along).
            openURL(url)
            dismiss()
        }
    }
}

/// Apple's mail sheet, pre-filled.
private struct MailComposer: UIViewControllerRepresentable {
    let message: String
    let images: [UIImage]
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([Feedback.address])
        vc.setSubject(Feedback.subject)
        vc.setMessageBody(Feedback.body(message), isHTML: false)
        for (i, img) in images.enumerated() {
            if let data = img.jpegData(compressionQuality: 0.8) {
                vc.addAttachmentData(data, mimeType: "image/jpeg", fileName: "screenshot-\(i + 1).jpg")
            }
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            done(result == .sent)
        }
    }
}

/// Shown for a few seconds after a screenshot: send that screen as feedback.
struct ScreenshotFeedbackPrompt: View {
    var onSend: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 1) {
                Text("Something off on this screen?").font(.ui(14, .semibold)).foregroundStyle(Theme.ink)
                Text("Send it as feedback").font(.ui(12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("Send") { onSend() }
                .buttonStyle(.chunky(.accent, height: 38, fullWidth: false))
                .environment(\.accent, .neutral)
            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .padding(.horizontal, 16)
    }
}
