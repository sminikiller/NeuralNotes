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
    init(host: CanvasHost, model: EditorViewModel) {
        self.host = host; self.model = model; super.init()
        view.delegate = self; view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.isEditable = true; view.isSelectable = true; view.isScrollEnabled = true
        view.overrideUserInterfaceStyle = .light
        view.layer.borderWidth = 1; view.layer.borderColor = UIColor.systemTeal.cgColor
        view.accessibilityIdentifier = "pageTextInput"; view.accessibilityLabel = "Testo sul foglio"
        let toolbar = UIToolbar()
        let done = UIBarButtonItem(title: "Fine", style: .done, target: self, action: #selector(finishEditing))
        done.accessibilityIdentifier = "pageTextDone"
        toolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
        toolbar.sizeToFit(); view.inputAccessoryView = toolbar
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
            shownID = id; view.text = text.text; view.isHidden = false
            view.font = .systemFont(ofSize: CGFloat(text.fontSize))
            view.becomeFirstResponder()
        } else if view.text != text.text && view.markedTextRange == nil { view.text = text.text }
        let tone = page.appearance?.tone ?? .white, rgb = tone.rgb
        view.backgroundColor = page.pdfFile == nil ? UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) : .white
        view.textColor = tone == .slate && page.pdfFile == nil ? .white : .black
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
    func textViewDidChange(_ textView: UITextView) { model?.updateLiveText(textView.text); layout() }
    func textViewDidEndEditing(_ textView: UITextView) { model?.endTextEdit() }
}
