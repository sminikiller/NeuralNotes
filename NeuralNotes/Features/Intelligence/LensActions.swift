import UIKit
import NeuralNotesCore

/// Text: underline for an automatic note, circle or drag to ask.
/// Image: the selected area or the touched photo is shown to the model.
enum LensMode: String, CaseIterable { case text, image }

/// Lens preferences shared by the mode bar (AppStorage), the gestures and the chat panel.
enum LensSettings {
    static let modeKey = "lens.mode", autoNoteKey = "lens.autoAnnotate"
    static var mode: LensMode { LensMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .text }
    static var autoNote: Bool { UserDefaults.standard.object(forKey: autoNoteKey) as? Bool ?? true }
}

/// What the Lens card next to the selection works on.
struct LensCardRequest: Identifiable, Equatable {
    let id = UUID()
    var area: CGRect?
    var imageID: UUID?
    var text: String?
    var photo: Data?
    /// The selection comes from the PDF opened beside the notebook: notes go to a free spot.
    var fromSidePDF = false
    /// A tap on a word explains it right away instead of waiting for a button.
    var startWithExplain = false
}

@MainActor
extension EditorViewModel {
    /// End of a Lens stroke on the page: an underline becomes a note, any other shape opens the card.
    func lensGesture(area: CGRect, underline: Bool, anchor: CGRect?) {
        lensCardAnchor = anchor
        if underline, LensSettings.mode == .text, LensSettings.autoNote { explainUnderline(area: area) }
        else { lensCard = LensCardRequest(area: area) }
    }

    /// A tap with the Lens: a photo is asked about, a word is explained at once.
    func lensTap(at point: CGPoint, anchor: CGRect?) {
        lensCardAnchor = anchor
        if let image = page?.images.last(where: { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(point) }) {
            lensCard = LensCardRequest(imageID: image.id)
        } else {
            lensCard = LensCardRequest(area: CGRect(x: point.x - 70, y: point.y - 22, width: 140, height: 44), startWithExplain: LensSettings.mode == .text)
        }
    }

    /// Text selected in a text box or in the PDF opened beside the notebook.
    func lensAsk(text: String, fromSidePDF: Bool = false) {
        lensCardAnchor = nil
        let request = TermExplanationRequest(term: text, subject: lensSubject)
        if fromSidePDF, request.isTerm, LensSettings.autoNote { explain(term: request.term, near: nil) }
        else { lensCard = LensCardRequest(text: text, fromSidePDF: fromSidePDF, startWithExplain: request.isTerm) }
    }

    /// "Chiedi alla Lente AI" on the current selection; without one, the page chat opens.
    func lensAskAboutSelection() {
        let bounds = selectionBounds
        if !bounds.isNull, bounds.width > 3, bounds.height > 3 { lensCardAnchor = nil; lensCard = LensCardRequest(area: bounds) }
        else { requestLens() }
    }

    private func explainUnderline(area: CGRect) {
        Task {
            status = "Lente: leggo la sottolineatura…"
            let text = await LensReader.text(in: area, model: self)
            let request = TermExplanationRequest(term: text, subject: lensSubject)
            guard request.isTerm else {
                // Several lines or nothing readable: the card shows what was read and asks.
                lensCard = LensCardRequest(area: area, text: text); status = ""; return
            }
            explain(term: request.term, near: area)
        }
    }

    /// Explains a term with the chosen engine and places the note; without an engine
    /// or consent the card opens instead and asks once.
    private func explain(term: String, near area: CGRect?) {
        guard hasLease, let pageID = page?.id else { return }
        Task {
            let configuration = AIEngineStore.load()
            guard configuration.supportsStructuredStudy, let consent = await AIEngineRouter.restoredConsent(configuration) else {
                lensCard = LensCardRequest(area: area, text: term, fromSidePDF: area == nil, startWithExplain: true); status = ""; return
            }
            status = "Lente: cerco «\(term)»…"
            do {
                let context = TermExplanationRequest.context(for: term, in: await LensReader.pageText(model: self))
                let request = TermExplanationRequest(term: term, context: context, subject: lensSubject)
                let value = try await AIEngineRouter.explain(request, configuration: configuration, consentKey: consent)
                guard page?.id == pageID else { status = "Nota non inserita: la pagina è cambiata."; return }
                status = insertTermNote(value, near: area) ? "Nota inserita: \(value.term)" : "Spiegazione pronta, ma il foglio è occupato: riprova."
            } catch is CancellationError { status = "" }
            catch { status = ""; self.error = "Lente AI: \(error.localizedDescription)" }
        }
    }
}
