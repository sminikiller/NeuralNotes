import UIKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func beginTextEdit(at point: CGPoint) {
        guard hasLease, !loading, !navigating, let page else { return }
        endTextEdit()
        let hit = page.texts.reversed().first { text in
            let box = RichText.bounds(text, pageHeight: page.height).insetBy(dx: 0, dy: -6)
            return box.contains(point.applying(RichText.rotation(text, pageHeight: page.height).inverted()))
        }
        if let hit { editingTextID = hit.id }
        else {
            var text = TextElement(text: "")
            text.x = max(0, min(Double(point.x), page.width - 40)); text.y = max(0, min(Double(point.y), page.height - 40))
            text.width = max(40, min(480, page.width - text.x - 12))
            mutatePage("Aggiungi testo") { $0.texts.append(text) }; editingTextID = text.id
        }
        selectedObjectID = editingTextID; textEditBefore = captureEdit()
    }
    func updateLiveText(_ value: String) {
        guard let id = editingTextID, let i = page?.texts.firstIndex(where: { $0.id == id }) else { return }
        page?.texts[i].text = value; drawingChanged()
    }
    func updateLiveText(_ value: NSAttributedString) {
        guard let id = editingTextID, let i = page?.texts.firstIndex(where: { $0.id == id }) else { return }
        page?.texts[i].text = value.string; page?.texts[i].rtf = RichText.data(value); drawingChanged()
    }
    func commitTextEdit() {
        guard let before = textEditBefore, before.page.id == page?.id else { return }
        recordEdit(before, label: "Modifica testo"); textEditBefore = captureEdit()
    }
    func endTextEdit() {
        commitTextEdit(); textEditBefore = nil; editingTextID = nil
    }
}

/// A genuine UITextInput on the page: UIKit supplies Scribble, selection,
/// insertion and scratch-to-delete for converted text when enabled in iPadOS.
@MainActor
final class CanvasTextInput: NSObject, UITextViewDelegate {
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    let view = UITextView()
    private var shownID: UUID?
    private var formatting: TextFormatting?
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init()
        view.delegate = self; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.isEditable = true; view.isSelectable = true; view.isScrollEnabled = true
        view.overrideUserInterfaceStyle = .light
        view.backgroundColor = .clear; view.isOpaque = false
        view.layer.borderWidth = 0
        view.accessibilityIdentifier = "pageTextInput"; view.accessibilityLabel = "Testo sul foglio"
        view.allowsEditingTextAttributes = true; view.dataDetectorTypes = [.link, .phoneNumber]
        formatting = TextFormatting(view: view) { [weak self] in
            guard let self else { return }; self.model?.updateLiveText(self.view.attributedText); self.layout()
        }
        view.inputAccessoryView = formatting?.toolbar(doneTarget: self, doneAction: #selector(finishEditing))
        view.isHidden = true; host.addSubview(view)
    }
    @objc private func finishEditing() {
        model?.endTextEdit(); view.resignFirstResponder(); refresh()
        host?.becomeFirstResponder()
    }
    func refresh() {
        guard let host, let model else { return }
        guard model.tool == .text, let id = model.editingTextID,
              let page = model.page, let text = page.texts.first(where: { $0.id == id }) else {
            if !view.isHidden { view.resignFirstResponder(); view.isHidden = true }
            host.surface.hiddenTextID = nil; shownID = nil; return
        }
        let needsFocus = shownID != id
        if needsFocus {
            shownID = id; view.attributedText = RichText.attributed(text); view.isHidden = false
        } else if view.text != text.text && view.markedTextRange == nil { view.attributedText = RichText.attributed(text) }
        let tone = page.appearance?.tone ?? .white
        view.backgroundColor = .clear
        if text.rtf == nil { view.textColor = text.background != nil ? .black : tone == .slate && page.pdfFile == nil ? .white : .black }
        host.surface.hiddenTextID = id
        layout()
        // Establish a real on-page frame before UIKit starts its text-input and
        // accessibility session (a zero-sized first responder can lose its AX children).
        if needsFocus { view.becomeFirstResponder() }
    }
    func layout() {
        guard !view.isHidden, let host, let model, let page = model.page,
              let text = page.texts.first(where: { $0.id == shownID }) else { return }
        let size = view.sizeThatFits(CGSize(width: CGFloat(text.width), height: CGFloat.greatestFiniteMagnitude))
        let height = max(40, min(max(100, Double(size.height) + 32), page.height - text.y))
        view.transform = .identity
        view.bounds = CGRect(origin: view.bounds.origin, size: CGSize(width: text.width, height: height))
        view.transform = CGAffineTransform(scaleX: host.canvas.zoomScale, y: host.canvas.zoomScale)
        view.center = host.surface.convert(CGPoint(x: text.x + text.width / 2, y: text.y + height / 2), to: host)
        host.bringSubviewToFront(view)
    }
    func textViewDidChange(_ textView: UITextView) { model?.updateLiveText(textView.attributedText); layout() }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        !(formatting?.replaceNewline(in: range, replacement: text) ?? false)
    }
    func textViewDidEndEditing(_ textView: UITextView) { model?.endTextEdit() }
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let value = (textView.text ?? "") as NSString
        guard range.location != NSNotFound, range.location >= 0, range.length > 0,
              range.location <= value.length, range.length <= value.length - range.location else { return nil }
        let selected = value.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return nil }
        let lens = UIAction(title: "Apri nella Lente AI", image: UIImage(systemName: "sparkle.magnifyingglass")) { [weak self] _ in
            self?.model?.requestLens(text: selected, compact: true)
        }
        return UIMenu(children: suggestedActions + [lens])
    }
}
