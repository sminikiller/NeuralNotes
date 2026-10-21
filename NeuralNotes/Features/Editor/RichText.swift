import SwiftUI
import UIKit
import NeuralNotesCore

@MainActor
enum RichText {
    private final class CachedText {
        let source: TextElement, color: UIColor, value: NSAttributedString
        init(_ source: TextElement, color: UIColor, value: NSAttributedString) { self.source = source; self.color = color; self.value = value }
    }
    private static let cache: NSCache<NSUUID, CachedText> = {
        let cache = NSCache<NSUUID, CachedText>(); cache.totalCostLimit = 8 * 1024 * 1024; cache.countLimit = 256; return cache
    }()
    static func attributed(_ text: TextElement, color: UIColor = .black) -> NSAttributedString {
        if let cached = cache.object(forKey: text.id as NSUUID), cached.source.rtf == text.rtf,
           cached.source.text == text.text, cached.source.fontSize == text.fontSize, cached.color.isEqual(color) { return cached.value }
        let value = decode(text, color: color)
        cache.setObject(CachedText(text, color: color, value: value), forKey: text.id as NSUUID, cost: (text.rtf?.count ?? 0) + value.length * 4)
        return value
    }
    private static func decode(_ text: TextElement, color: UIColor) -> NSAttributedString {
        if let data = text.rtf, data.count <= 2 * 1024 * 1024,
           let value = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           value.string == text.text { return value }
        return NSAttributedString(string: text.text, attributes: [.font: UIFont.systemFont(ofSize: text.fontSize), .foregroundColor: color])
    }
    static func data(_ text: NSAttributedString) -> Data? {
        try? text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
    static func bounds(_ text: TextElement, pageHeight: Double) -> CGRect {
        let measured = attributed(text).boundingRect(with: CGSize(width: text.width, height: max(0, pageHeight - text.y)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return CGRect(x: text.x, y: text.y, width: text.width, height: max(text.fontSize + 4, measured.height))
    }
    static func rotation(_ text: TextElement, pageHeight: Double) -> CGAffineTransform {
        let box = bounds(text, pageHeight: pageHeight)
        return CGAffineTransform(translationX: box.midX, y: box.midY).rotated(by: CGFloat(text.rotation ?? 0) * .pi / 180).translatedBy(x: -box.midX, y: -box.midY)
    }
    static func link(at point: CGPoint, text: TextElement, pageHeight: Double) -> URL? {
        guard let index = characterIndex(at: point, text: text, pageHeight: pageHeight) else { return nil }
        let value = attributed(text)
        if let url = value.attribute(.link, at: index, effectiveRange: nil) as? URL { return url }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            return detector.matches(in: text.text, range: NSRange(location: 0, length: value.length)).first(where: { NSLocationInRange(index, $0.range) })?.url
        }
        return nil
    }
    static func characterIndex(at point: CGPoint, text: TextElement, pageHeight: Double) -> Int? {
        let value = attributed(text), storage = NSTextStorage(attributedString: value), layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: text.width, height: max(1, pageHeight - text.y)))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        let unrotated = point.applying(rotation(text, pageHeight: pageHeight).inverted())
        let local = CGPoint(x: unrotated.x - text.x, y: unrotated.y - text.y)
        guard layout.usedRect(for: container).contains(local) else { return nil }
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil), index = layout.characterIndexForGlyph(at: glyph)
        guard index < value.length else { return nil }
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -3, dy: -3).contains(local) else { return nil }
        return index
    }
}

@MainActor
final class TextFormatting: NSObject, UIGestureRecognizerDelegate {
    weak var view: UITextView?
    var didChange: (() -> Void)?
    init(view: UITextView, didChange: @escaping () -> Void) {
        self.view = view; self.didChange = didChange; super.init()
        let tap = UITapGestureRecognizer(target: self, action: #selector(checklistTapped(_:)))
        tap.cancelsTouchesInView = false; tap.delegate = self; tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(tap)
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    @objc private func checklistTapped(_ gesture: UITapGestureRecognizer) {
        guard let view else { return }
        let point = gesture.location(in: view), local = CGPoint(x: point.x - view.textContainerInset.left, y: point.y - view.textContainerInset.top)
        let layout = view.layoutManager, container = view.textContainer
        guard layout.usedRect(for: container).contains(local) else { return }
        let glyph = layout.glyphIndex(for: local, in: container, fractionOfDistanceThroughGlyph: nil)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -3, dy: -3).contains(local) else { return }
        let index = layout.characterIndexForGlyph(at: glyph)
        guard index < view.attributedText.length else { return }
        let old = (view.text as NSString).substring(with: NSRange(location: index, length: 1))
        guard old == "☐" || old == "☑" else { return }
        let selected = view.selectedRange, value = NSMutableAttributedString(attributedString: view.attributedText)
        value.replaceCharacters(in: NSRange(location: index, length: 1), with: old == "☐" ? "☑" : "☐")
        view.attributedText = value; view.selectedRange = selected; didChange?()
    }
    func replaceNewline(in range: NSRange, replacement: String) -> Bool {
        guard replacement == "\n", range.length == 0, let view, range.location <= view.attributedText.length else { return false }
        let source = view.text as NSString, paragraph = source.paragraphRange(for: range)
        let beforeCaret = source.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
        guard let continuation = TextLists.continuation(of: beforeCaret) else { return false }
        let value = NSMutableAttributedString(attributedString: view.attributedText)
        if continuation.empty {
            value.deleteCharacters(in: NSRange(location: paragraph.location, length: continuation.consumed))
            view.attributedText = value; view.selectedRange = NSRange(location: paragraph.location, length: 0)
        } else {
            let insertion = "\n" + continuation.prefix
            value.insert(NSAttributedString(string: insertion, attributes: view.typingAttributes), at: range.location)
            view.attributedText = value; view.selectedRange = NSRange(location: range.location + insertion.utf16.count, length: 0)
        }
        didChange?(); return true
    }
    func toolbar(doneTarget: Any?, doneAction: Selector?) -> UIToolbar {
        let bar = UIToolbar()
        let actions: [(String, Selector)] = [("B", #selector(bold)), ("I", #selector(italic)), ("U", #selector(underline))]
        bar.items = actions.map { UIBarButtonItem(title: $0.0, style: .plain, target: self, action: $0.1) }
        let styles = [("Titolo 1", 30.0), ("Titolo 2", 24.0), ("Corpo", 18.0)].map { title, size in
            UIAction(title: title) { [weak self] _ in self?.paragraphStyle(size: size, heading: title != "Corpo") }
        }
        bar.items?.append(UIBarButtonItem(title: "Stile", image: nil, primaryAction: nil, menu: UIMenu(children: styles)))
        let colors: [(String, UIColor)] = [("Nero", .black), ("Blu", .systemBlue), ("Rosso", .systemRed), ("Verde", .systemGreen), ("Viola", .systemPurple), ("Bianco", .white)]
        let colorActions = colors.map { name, color in UIAction(title: name, image: UIImage(systemName: "circle.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)) { [weak self] _ in self?.foreground(color) } }
        bar.items?.append(UIBarButtonItem(title: "Colore", image: nil, primaryAction: nil, menu: UIMenu(children: colorActions)))
        let highlights: [(String, UIColor?)] = [("Nessuna", nil), ("Giallo", .systemYellow), ("Verde", .systemGreen), ("Arancione", .systemOrange), ("Rosa", .systemPink)]
        let highlightActions = highlights.map { name, color in UIAction(title: name) { [weak self] _ in self?.highlight(color) } }
        bar.items?.append(UIBarButtonItem(title: "Evidenzia", image: nil, primaryAction: nil, menu: UIMenu(children: highlightActions)))
        let extra: [UIAction] = [UIAction(title: "Elenco puntato") { [weak self] _ in self?.bullet() }, UIAction(title: "Checklist") { [weak self] _ in self?.checklist() }, UIAction(title: "Apice") { [weak self] _ in self?.superscript() }, UIAction(title: "Pedice") { [weak self] _ in self?.subscriptText() }, UIAction(title: "Testo normale") { [weak self] _ in self?.normalBaseline() }, UIAction(title: "Dizionario") { [weak self] _ in self?.dictionary() }]
        bar.items?.append(UIBarButtonItem(title: "Altro", image: nil, primaryAction: nil, menu: UIMenu(children: extra)))
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
    func paragraphStyle(size: Double, heading: Bool) {
        guard let view else { return }
        let font = heading ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        let paragraph = NSMutableParagraphStyle(); paragraph.paragraphSpacing = heading ? 12 : 6
        let selected = view.selectedRange, string = view.text as NSString
        guard selected.location <= string.length, selected.length <= string.length - selected.location else { return }
        let range = string.paragraphRange(for: selected)
        var typing = view.typingAttributes; typing[.font] = font; typing[.paragraphStyle] = paragraph; typing[.baselineOffset] = 0
        if range.length > 0 {
            let value = NSMutableAttributedString(attributedString: view.attributedText)
            value.addAttributes([.font: font, .paragraphStyle: paragraph, .baselineOffset: 0], range: range)
            view.attributedText = value; view.selectedRange = selected
        }
        view.typingAttributes = typing; didChange?()
    }
    func foreground(_ color: UIColor) { apply { $0[.foregroundColor] = color } }
    func highlight(_ color: UIColor?) {
        apply { attrs in
            if let color { attrs[.backgroundColor] = color.withAlphaComponent(0.35) }
            else { attrs.removeValue(forKey: .backgroundColor) }
        }
    }
    private func trait(_ trait: UIFontDescriptor.SymbolicTraits) {
        apply { attrs in
            let font = attrs[.font] as? UIFont ?? UIFont.systemFont(ofSize: 24)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { attrs[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
        }
    }
    @objc func dictionary() {
        guard let view, view.selectedRange.length > 0, NSMaxRange(view.selectedRange) <= (view.text as NSString).length else { return }
        SystemDictionary.open(term: (view.text as NSString).substring(with: view.selectedRange), from: view)
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
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            !(formatting?.replaceNewline(in: range, replacement: text) ?? false)
        }
        @objc func done() { formatting?.view?.resignFirstResponder() }
    }
}
