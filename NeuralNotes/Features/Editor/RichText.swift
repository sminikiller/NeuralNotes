import SwiftUI
import UIKit
import NeuralNotesCore

@MainActor
enum RichText {
    static func attributed(_ text: TextElement, color: UIColor = .black) -> NSAttributedString {
        if let data = text.rtf, data.count <= 2 * 1024 * 1024,
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           value.string == text.text { return value }
        return NSAttributedString(string: text.text, attributes: [.font: UIFont.systemFont(ofSize: text.fontSize), .foregroundColor: color])
    }
    static func data(_ text: NSAttributedString) -> Data? {
        try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}

@MainActor
final class TextFormatting: NSObject {
    weak var view: UITextView?
    var didChange: (() -> Void)?
    init(view: UITextView, didChange: @escaping () -> Void) { self.view = view; self.didChange = didChange; super.init() }
    func toolbar(doneTarget: Any?, doneAction: Selector?) -> UIToolbar {
        let bar = UIToolbar()
        let actions: [(String, Selector)] = [("B", #selector(bold)), ("I", #selector(italic)), ("U", #selector(underline)), ("•", #selector(bullet)), ("☐", #selector(checklist)), ("x²", #selector(superscript)), ("x₂", #selector(subscriptText)), ("A", #selector(normalBaseline))]
        bar.items = actions.map { UIBarButtonItem(title: $0.0, style: .plain, target: self, action: $0.1) }
        if let doneAction {
            let done = UIBarButtonItem(title: "Fine", style: .done, target: doneTarget, action: doneAction)
            done.accessibilityIdentifier = "pageTextDone"
            bar.items?.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)); bar.items?.append(done)
        }
        bar.sizeToFit(); return bar
    }
    private func apply(_ edit: (inout [NSAttributedString.Key: Any]) -> Void) {
        guard let view else { return }
        let range = view.selectedRange
        if range.length == 0 { var attrs = view.typingAttributes; edit(&attrs); view.typingAttributes = attrs; return }
        let value = NSMutableAttributedString(attributedString: view.attributedText)
        value.enumerateAttributes(in: range) { attrs, subrange, _ in
            var attrs = attrs; edit(&attrs); value.setAttributes(attrs, range: subrange)
        }
        view.attributedText = value; view.selectedRange = range; didChange?()
    }
    private func trait(_ trait: UIFontDescriptor.SymbolicTraits) {
        apply { attrs in
            let font = attrs[.font] as? UIFont ?? UIFont.systemFont(ofSize: 24)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
        }
    }
    @objc func bold() { trait(.traitBold) }
    @objc func italic() { trait(.traitItalic) }
    @objc func underline() { apply { $0[.underlineStyle] = ($0[.underlineStyle] as? Int == 1) ? 0 : 1 } }
    @objc func superscript() { baseline(8) }
    @objc func subscriptText() { baseline(-5) }
    @objc func normalBaseline() { baseline(0) }
    private func baseline(_ offset: CGFloat) { apply { $0[.baselineOffset] = offset } }
    private func prefix(_ value: String) {
        guard let view else { return }
        let paragraph = (view.text as NSString).paragraphRange(for: view.selectedRange)
        let result = NSMutableAttributedString(attributedString: view.attributedText)
        result.insert(NSAttributedString(string: value, attributes: view.typingAttributes), at: paragraph.location)
        view.attributedText = result; view.selectedRange = NSRange(location: paragraph.location + value.utf16.count, length: 0); didChange?()
    }
    @objc func bullet() { prefix("• ") }
    @objc func checklist() { prefix("☐ ") }
}

@MainActor
struct RichTextEditor: UIViewRepresentable {
    @Binding var text: TextElement
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.delegate = context.coordinator; view.allowsEditingTextAttributes = true
        view.attributedText = RichText.attributed(text); view.accessibilityLabel = "Testo formattato"
        context.coordinator.formatting = TextFormatting(view: view) { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.textViewDidChange(view) }
        }
        view.inputAccessoryView = context.coordinator.formatting?.toolbar(doneTarget: context.coordinator, doneAction: #selector(Coordinator.done))
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text.text { view.attributedText = RichText.attributed(text) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditor
        var formatting: TextFormatting?
        init(_ parent: RichTextEditor) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text.text = textView.text; parent.text.rtf = RichText.data(textView.attributedText) }
        @objc func done() { formatting?.view?.resignFirstResponder() }
    }
}
