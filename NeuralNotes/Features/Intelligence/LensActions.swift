import UIKit
import NeuralNotesCore

/// Text: underline for an automatic note, circle or drag to ask.
/// Image: the selected area or the touched photo is shown to the model.
enum LensMode: String, CaseIterable { case text, image }

/// Lens preferences shared by the mode bar (AppStorage), the gestures and the panels.
enum LensSettings {
    static let modeKey = "lens.mode", autoNoteKey = "lens.autoAnnotate", floatingKey = "lens.floating", hintKey = "lens.hintSeen"
    static var mode: LensMode { LensMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .text }
    static var autoNote: Bool { UserDefaults.standard.object(forKey: autoNoteKey) as? Bool ?? true }
}

/// The three parts of the Lens side panel.
enum LensTab: String, CaseIterable, Identifiable {
    case selection, notes, page
    var id: String { rawValue }
    var title: String {
        switch self { case .selection: return "Selezione"; case .notes: return "Note"; case .page: return "Pagina" }
    }
}

/// What the Lens conversation works on.
struct LensCardRequest: Identifiable, Equatable {
    let id = UUID()
    var area: CGRect?
    var imageID: UUID?
    var text: String?
    var photo: Data?
    /// The part of the photo chosen before asking.
    var photoCrop: NormalizedCrop?
    /// The selection comes from the PDF opened beside the notebook: notes go to a free spot.
    var fromSidePDF = false
    /// A tap on a word explains it right away instead of waiting for a button.
    var startWithExplain = false
    /// The page of the selection; an answer inserted on another page goes to a free spot there.
    var pageID: UUID?
}

/// A ready-made way to ask about the selection.
struct LensPrompt: Identifiable, Hashable {
    let label: String, prompt: String, icon: String
    var id: String { label }
    static let explainTerm = LensPrompt(label: "Chi è / Cos’è", prompt: "", icon: "person.text.rectangle")
    static let describe = LensPrompt(label: "Descrivi", prompt: "Descrivi cosa mostra l’immagine e cosa è utile sapere per studiarla.", icon: "photo")
    static let study: [LensPrompt] = [
        LensPrompt(label: "Spiega", prompt: "Spiega in modo semplice e chiaro il contenuto selezionato.", icon: "lightbulb"),
        LensPrompt(label: "Riassumi", prompt: "Riassumi il contenuto selezionato in 3-5 punti brevi.", icon: "list.bullet"),
        LensPrompt(label: "Semplifica", prompt: "Riscrivi il contenuto selezionato con parole semplici, come lo spiegheresti a un compagno.", icon: "text.badge.minus"),
        LensPrompt(label: "Esempio", prompt: "Fai un esempio concreto che aiuti a capire il contenuto selezionato.", icon: "sparkles"),
        LensPrompt(label: "Approfondisci", prompt: "Approfondisci il contenuto selezionato: contesto, cause, conseguenze e collegamenti utili per lo studio.", icon: "magnifyingglass"),
        LensPrompt(label: "Domande", prompt: "Scrivi 3 domande di ripasso sul contenuto selezionato, ciascuna con una risposta breve.", icon: "questionmark.bubble"),
        LensPrompt(label: "Traduci", prompt: "Traduci il testo selezionato in italiano; se è già in italiano, traducilo in inglese.", icon: "character.bubble"),
    ]
}

/// A Lens note to open in the editor sheet.
struct LensNoteEditTarget: Identifiable, Equatable { let id: UUID }

/// The outline drawn for a moment around a note or its text after a jump from the list.
struct LensNoteFocus: Equatable {
    let id = UUID()
    var pageID: UUID
    var rect: CGRect
}

@MainActor
extension EditorViewModel {
    /// Starts a Lens conversation about a selection and shows it (side panel or floating window).
    func openLens(_ request: LensCardRequest) {
        var request = request
        if request.pageID == nil, !request.fromSidePDF, request.photo == nil { request.pageID = page?.id }
        lensSession?.cancel()
        let session = LensSession(request: request)
        lensSession = session
        Task { await session.prepare(self) }
        showLensPanel(.selection)
    }

    func showLensPanel(_ tab: LensTab) { lensTab = tab; lensPanelRequest += 1 }

    func closeLensSession() { lensSession?.cancel(); lensSession = nil }

    /// End of a Lens stroke on the page: an underline becomes a note, any other shape opens the conversation.
    func lensGesture(area: CGRect, underline: Bool, anchor: CGRect?) {
        lensAnchor = anchor
        if underline, LensSettings.mode == .text, LensSettings.autoNote { explainUnderline(area: area) }
        else { openLens(LensCardRequest(area: area)) }
    }

    /// A tap with the Lens: a photo is asked about, a word is explained at once.
    func lensTap(at point: CGPoint, anchor: CGRect?) {
        lensAnchor = anchor
        if let image = page?.images.last(where: { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(point) }) {
            openLens(LensCardRequest(imageID: image.id))
        } else {
            openLens(LensCardRequest(area: CGRect(x: point.x - 70, y: point.y - 22, width: 140, height: 44), startWithExplain: LensSettings.mode == .text))
        }
    }

    /// Text selected in a text box or in the PDF opened beside the notebook.
    func lensAsk(text: String, fromSidePDF: Bool = false) {
        lensAnchor = nil
        let request = TermExplanationRequest(term: text, subject: lensSubject)
        if fromSidePDF, request.isTerm, LensSettings.autoNote { explain(term: request.term, near: nil) }
        else { openLens(LensCardRequest(text: text, fromSidePDF: fromSidePDF, startWithExplain: request.isTerm)) }
    }

    /// "Chiedi alla Lente AI" on the current selection; without one, the page chat opens.
    func lensAskAboutSelection() {
        let bounds = selectionBounds
        if !bounds.isNull, bounds.width > 3, bounds.height > 3 { lensAnchor = nil; openLens(LensCardRequest(area: bounds)) }
        else { requestLens() }
    }

    private func explainUnderline(area: CGRect) {
        Task {
            status = "Lente: leggo la sottolineatura…"
            let text = await LensReader.text(in: area, model: self)
            let request = TermExplanationRequest(term: text, subject: lensSubject)
            guard request.isTerm else {
                // Several lines or nothing readable: the conversation shows what was read and asks.
                openLens(LensCardRequest(area: area, text: text)); status = ""; return
            }
            explain(term: request.term, near: area)
        }
    }

    /// Explains a term with the chosen engine and places the note; without an engine
    /// or consent the conversation opens instead and asks once.
    private func explain(term: String, near area: CGRect?) {
        guard hasLease, let pageID = page?.id else { return }
        Task {
            let configuration = AIEngineStore.load()
            guard configuration.supportsStructuredStudy, let consent = await AIEngineRouter.restoredConsent(configuration) else {
                openLens(LensCardRequest(area: area, text: term, fromSidePDF: area == nil, startWithExplain: true)); status = ""; return
            }
            status = "Lente: cerco «\(term)»…"
            do {
                let context = TermExplanationRequest.context(for: term, in: await LensReader.pageText(model: self))
                let request = TermExplanationRequest(term: term, context: context, subject: lensSubject)
                let value = try await AIEngineRouter.explain(request, configuration: configuration, consentKey: consent)
                guard page?.id == pageID else { status = "Nota non inserita: la pagina è cambiata."; return }
                if let id = insertLensNote(value, near: area) {
                    let reduced = page?.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed == true
                    status = reduced ? "Nota su «\(value.term)» ridotta a 💡: toccala per aprirla" : "Nota inserita: \(value.term)"
                } else { status = "Spiegazione pronta, ma il foglio è occupato: riprova." }
            } catch is CancellationError { status = "" }
            catch { status = ""; self.error = "Lente AI: \(error.localizedDescription)" }
        }
    }
}
