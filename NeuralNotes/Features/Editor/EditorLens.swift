import UIKit
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
        guard hasLease, !loading, !navigating, !hasActiveStroke else { return false }
        let color: UIColor = page?.appearance?.tone == .slate && page?.pdfFile == nil ? .white : .black
        let rich = NSMutableAttributedString(string: "")
        for run in artifact.citedRuns {
            var attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: color]
            if let link = run.link { attributes[.link] = link; attributes[.foregroundColor] = UIColor.systemBlue; attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            rich.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        var text = TextElement(text: rich.string); text.fontSize = 18; text.rtf = RichText.data(rich)
        mutatePage("Inserisci risposta AI con fonti") { $0.texts.append(text) }
        return page?.texts.contains(where: { $0.id == text.id }) == true
    }
}
