import UIKit
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func requestLens(text: String? = nil, area: CGRect? = nil, compact: Bool = false) {
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return }
        finishInkGesture(); endTextEdit()
        let selected = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        lensTextSelection = selected?.isEmpty == false ? String(selected!.prefix(8000)) : nil
        lensArea = area; lensPrefersPopup = compact; lensRequest += 1
    }
    @discardableResult
    func insertAIAnswer(_ artifact: AIArtifact) -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke, let current = page else { return false }
        let color: UIColor = current.appearance?.tone == .slate && current.pdfFile == nil ? .white : .black
        let rich = NSMutableAttributedString(string: "")
        for run in artifact.citedRuns {
            var attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: color]
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = UIColor.systemBlue; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            rich.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        // Beside the circled area or the selection, clear of typed notes, images and ink.
        let selection = selectionBounds
        let anchor = lensArea ?? (selection.isNull ? nil : selection)
        let frame = LensGeometry.placement(text: rich.string, near: anchor, occupied: occupiedRects(current), pageWidth: current.width, pageHeight: current.height)
        var text = TextElement(text: rich.string); text.fontSize = 16; text.rtf = RichText.data(rich)
        text.x = Double(frame.minX); text.y = Double(frame.minY); text.width = Double(frame.width)
        mutatePage("Inserisci risposta AI con fonti") { $0.texts.append(text) }
        return page?.texts.contains(where: { $0.id == text.id }) == true
    }

    /// "Spiega e annota": a sticky note beside the underlined term, marked as general
    /// knowledge of the model; one undo removes it.
    @discardableResult
    func insertTermNote(_ value: TermExplanation, near area: CGRect?) -> Bool {
        guard hasLease, !loading, !navigating, !hasActiveStroke, let current = page else { return false }
        let rich = NSMutableAttributedString(string: value.term + "\n", attributes: [.font: UIFont.boldSystemFont(ofSize: 15), .foregroundColor: UIColor.black])
        rich.append(NSAttributedString(string: value.noteBody + "\n", attributes: [.font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black]))
        rich.append(NSAttributedString(string: value.origin, attributes: [.font: UIFont.italicSystemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]))
        let selection = selectionBounds
        let anchor = area ?? (selection.isNull ? nil : selection)
        let frame = LensGeometry.placement(text: rich.string, near: anchor, occupied: occupiedRects(current), pageWidth: current.width, pageHeight: current.height,
                                           fontSize: 14, maximumWidth: 260)
        var text = TextElement(text: rich.string); text.fontSize = 14; text.rtf = RichText.data(rich)
        text.background = InkColor(1, 0.94, 0.55)
        text.x = Double(frame.minX); text.y = Double(frame.minY); text.width = Double(frame.width)
        mutatePage("Inserisci nota della Lente") { $0.texts.append(text) }
        return page?.texts.contains(where: { $0.id == text.id }) == true
    }

    private func occupiedRects(_ current: PageSnapshot) -> [CGRect] {
        var occupied = current.texts.map { RichText.bounds($0, pageHeight: current.height) }
        occupied += current.images.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        occupied += (current.shapes ?? []).map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        occupied += canvas.drawing.strokes.map(\.renderBounds)
        return occupied
    }
}
