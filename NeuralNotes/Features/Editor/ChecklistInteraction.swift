import UIKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    func checklistHit(at point: CGPoint) -> (UUID, Int)? {
        guard let page else { return nil }
        for text in page.texts.reversed() where text.text.contains("☐") || text.text.contains("☑") {
            if let index = RichText.characterIndex(at: point, text: text, pageHeight: page.height) {
                let char = (text.text as NSString).substring(with: NSRange(location: index, length: 1))
                if char == "☐" || char == "☑" { return (text.id, index) }
            }
        }
        return nil
    }
    @discardableResult func toggleChecklist(at point: CGPoint) -> Bool {
        guard let (id, index) = checklistHit(at: point) else { return false }
        mutatePage("Spunta checklist") { page in
            guard let i = page.texts.firstIndex(where: { $0.id == id }) else { return }
            let value = NSMutableAttributedString(attributedString: RichText.attributed(page.texts[i]))
            let old = (value.string as NSString).substring(with: NSRange(location: index, length: 1))
            value.replaceCharacters(in: NSRange(location: index, length: 1), with: old == "☐" ? "☑" : "☐")
            page.texts[i].text = value.string; page.texts[i].rtf = RichText.data(value)
        }
        return true
    }
}
