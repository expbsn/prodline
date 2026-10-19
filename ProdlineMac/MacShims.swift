import SwiftUI
import AppKit

// The iOS screens compile on the Mac with these stand-ins for UIKit-only API. They do the closest Mac
// thing, or nothing where the Mac has no equivalent (keyboard types, autocapitalization).

typealias UIImage = NSImage

extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }

    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    var cgImage: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
}

enum TextInputAutocapitalization { case never, words, sentences, characters }
enum UIKeyboardType { case `default`, URL, emailAddress, numberPad, decimalPad, asciiCapable, webSearch, phonePad, numbersAndPunctuation }

extension View {
    func textInputAutocapitalization(_ style: TextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
}
