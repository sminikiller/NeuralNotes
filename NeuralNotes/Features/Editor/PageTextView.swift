import UIKit
import UniformTypeIdentifiers

/// Keep formatting shortcuts with the actual text responder. Canvas shortcuts
/// must not consume typed letters or use a second, disconnected text editor.
@MainActor
final class PageTextView: UITextView {
    var formattingCommand: ((PageTextAction) -> Void)?
    var pasteCommand: ((Bool) -> Bool)?
    override var keyCommands: [UIKeyCommand]? {
        let commands: [(String, UIKeyModifierFlags, String)] = [
            ("b", .command, "Grassetto"), ("i", .command, "Corsivo"), ("u", .command, "Sottolineato"),
            ("=", .command, "Pedice"), ("=", [.command, .shift], "Apice"),
            ("v", [.command, .shift], "Incolla senza formattazione")
        ]
        return commands.map { input, flags, title in
            let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(nnTextKey(_:)))
            command.discoverabilityTitle = title; command.wantsPriorityOverSystemBehavior = true; return command
        } + (super.keyCommands ?? [])
    }
    @objc private func nnTextKey(_ command: UIKeyCommand) {
        switch command.input {
        case "b": formattingCommand?(.bold)
        case "i": formattingCommand?(.italic)
        case "u": formattingCommand?(.underline)
        case "=": formattingCommand?(command.modifierFlags.contains(.shift) ? .superscript : .subscriptText)
        case "v": _ = pasteCommand?(true)
        default: break
        }
    }
    override func paste(_ sender: Any?) { if pasteCommand?(false) != true { super.paste(sender) } }
}

@MainActor
enum TextPasteboard {
    /// Bound external rich text before parsing it. Plain paste inherits the
    /// destination's typing style rather than importing the source's formatting.
    static func read(plain: Bool, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString? {
        let board = UIPasteboard.general
        if !plain, let data = board.data(forPasteboardType: UTType.rtf.identifier), data.count <= 2 * 1024 * 1024,
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           value.length <= 100_000 {
            return RichTextScript.restoreMetadata(in: value, from: data)
        }
        guard let string = board.string, string.utf16.count <= 100_000 else { return nil }
        return NSAttributedString(string: string, attributes: attributes)
    }
}
