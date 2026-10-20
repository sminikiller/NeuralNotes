import UIKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func beginTextEdit(at point: CGPoint) {
        guard hasLease, !loading, !navigating, let page else { return }
        endTextEdit()
        let hit = page.texts.reversed().first { text in
            let size = (text.text as NSString).boundingRect(with: CGSize(width: text.width, height: max(1, page.height - text.y)),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: text.fontSize)], context: nil)
            return CGRect(x: text.x, y: text.y, width: text.width, height: max(60, size.height + 16)).contains(point)
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
    }
    func refresh() {
        guard let host, let model else { return }
        guard model.tool == .text, let id = model.editingTextID,
              let page = model.page, let text = page.texts.first(where: { $0.id == id }) else {
            if !view.isHidden { view.resignFirstResponder(); view.isHidden = true }
            host.surface.hiddenTextID = nil; shownID = nil; return
        }
        if shownID != id {
            shownID = id; view.attributedText = RichText.attributed(text); view.isHidden = false
            view.becomeFirstResponder()
        } else if view.text != text.text && view.markedTextRange == nil { view.attributedText = RichText.attributed(text) }
        let tone = page.appearance?.tone ?? .white
        view.backgroundColor = .clear
        if text.rtf == nil { view.textColor = tone == .slate && page.pdfFile == nil ? .white : .black }
        host.surface.hiddenTextID = id
        layout()
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
    func textViewDidEndEditing(_ textView: UITextView) { model?.endTextEdit() }
}
