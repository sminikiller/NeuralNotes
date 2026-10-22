import UIKit
import NeuralNotesCore

/// Parole (text): tap a word, or pass over words like a highlighter; a closed loop
/// still works as a lasso. Area: circle or drag a rectangle around whole words.
/// Immagine: the selected area or the touched photo is shown to the model.
enum LensMode: String, CaseIterable {
    case text, area, image
    var title: String {
        switch self { case .text: return "Parole"; case .area: return "Area"; case .image: return "Immagine" }
    }
}

/// Words picked on the page with the Lens, waiting for a command from the bar beside them.
struct LensPick: Equatable {
    let id = UUID()
    var pageID: UUID
    var text: String
    var rects: [CGRect]
    var area: CGRect { rects.reduce(CGRect.null) { $0.union($1) } }
}

/// The words the Lens is working on, highlighted on the page.
struct LensHighlight: Equatable {
    var pageID: UUID
    var rects: [CGRect]
}

/// Lens preferences shared by the mode bar (AppStorage), the gestures and the panels.
enum LensSettings {
    static let modeKey = "lens.mode", autoNoteKey = "lens.autoAnnotate", floatingKey = "lens.floating", hintKey = "lens.hintSeen.2"
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

    func closeLensSession() { lensSession?.cancel(); lensSession = nil; lensHighlight = nil }

    /// End of a Lens stroke without words to pick (handwriting before its OCR, image mode):
    /// an underline becomes a note, any other shape opens the conversation.
    func lensGesture(area: CGRect, underline: Bool, anchor: CGRect?) {
        lensAnchor = anchor; lensPick = nil
        if underline, LensSettings.mode == .text, LensSettings.autoNote { explainUnderline(area: area) }
        else { openLens(LensCardRequest(area: area)) }
    }

    /// Words picked with a tap, a highlighter stroke or a lasso. A tap explains the word
    /// at once; a short pick makes a note when "Nota automatica" is on; otherwise a bar
    /// beside the words offers Spiega, Chiedi, Cerca and Copia.
    func lensPicked(text: String, rects: [CGRect], tap: Bool, anchor: CGRect?) {
        guard let pageID = page?.id else { return }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        lensAnchor = anchor
        lensHighlight = LensHighlight(pageID: pageID, rects: rects)
        let pick = LensPick(pageID: pageID, text: words, rects: rects)
        if tap { lensPick = nil; openLens(LensCardRequest(area: pick.area, text: words, startWithExplain: true)); return }
        let probe = TermExplanationRequest(term: words, subject: lensSubject)
        if LensSettings.mode == .text, LensSettings.autoNote, probe.isTerm { lensPick = nil; annotate(words, near: pick.area); return }
        lensPick = pick
    }

    // Commands of the bar beside picked words.
    func lensPickExplain() {
        guard let pick = lensPick else { return }
        lensPick = nil; annotate(pick.text, near: pick.area)
    }
    func lensPickAsk() {
        guard let pick = lensPick else { return }
        lensPick = nil; openLens(LensCardRequest(area: pick.area, text: pick.text))
    }
    func lensPickSearch() {
        guard let pick = lensPick else { return }
        lensPick = nil; lensHighlight = nil
        pendingSearchQuery = String(pick.text.prefix(200)); searchRequest += 1
    }
    func lensPickCopy() {
        guard let pick = lensPick else { return }
        UIPasteboard.general.string = pick.text; status = "Testo copiato"
        lensPick = nil; lensHighlight = nil
    }
    func lensPickDismiss() { lensPick = nil; lensHighlight = nil }

    /// Reads the words of the page ahead, so taps and strokes pick exact words.
    func prepareLensWords() {
        guard let page else { return }
        PageWordIndex.shared.prepare(page, model: self)
    }

    /// A tap with the Lens: a photo is asked about; a word is picked exactly and explained.
    func lensTap(at point: CGPoint, anchor: CGRect?, tolerance: CGFloat = 6) {
        lensAnchor = anchor
        if let image = page?.images.last(where: { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height).contains(point) }) {
            lensPick = nil; openLens(LensCardRequest(imageID: image.id)); return
        }
        guard let current = page else { return }
        if LensSettings.mode != .image {
            let groups = PageWordIndex.shared.groups(for: current)
            for words in groups {
                guard let index = PageWords.word(at: point, in: words, tolerance: tolerance) else { continue }
                let word = words[index]
                let trimmed = word.text.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces))
                lensPicked(text: trimmed.isEmpty ? word.text : trimmed, rects: [word.rect], tap: true, anchor: anchor)
                return
            }
            if PageWordIndex.shared.isReady(current) {
                lensPick = nil; lensHighlight = nil
                status = "Nessuna parola qui: tocca una parola, passaci sopra o cerchiala."
                return
            }
            prepareLensWords()
        }
        lensPick = nil
        let area = CGRect(x: point.x - 70, y: point.y - 22, width: 140, height: 44)
        openLens(LensCardRequest(area: area, startWithExplain: LensSettings.mode != .image))
    }

    /// Text selected in a text box or in the PDF opened beside the notebook.
    func lensAsk(text: String, fromSidePDF: Bool = false) {
        lensAnchor = nil
        let request = TermExplanationRequest(term: text, subject: lensSubject)
        if fromSidePDF, request.isTerm, LensSettings.autoNote { annotate(request.term, near: nil) }
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
            annotate(request.term, near: area)
        }
    }

    /// Explains a term or a short passage with the chosen engine and puts the note beside
    /// it; without an engine or consent the conversation opens instead and asks once.
    private func annotate(_ text: String, near area: CGRect?) {
        guard hasLease, let pageID = page?.id else { return }
        let probe = TermExplanationRequest(term: text, subject: lensSubject)
        let term = probe.isTerm
        Task {
            let configuration = AIEngineStore.load()
            guard configuration.supportsStructuredStudy, let consent = await AIEngineRouter.restoredConsent(configuration) else {
                openLens(LensCardRequest(area: area, text: text, fromSidePDF: area == nil, startWithExplain: true)); status = ""; return
            }
            status = term ? "Lente: cerco «\(probe.term)»…" : "Lente: spiego il brano…"
            do {
                let pageText = await LensReader.pageText(model: self)
                guard page?.id == pageID else { status = ""; return }
                let request: TermExplanationRequest
                if term {
                    request = TermExplanationRequest(term: probe.term, context: TermExplanationRequest.context(for: probe.term, in: pageText), subject: lensSubject)
                } else {
                    let context = TermExplanationRequest.context(for: String(text.prefix(80)), in: pageText)
                    request = TermExplanationRequest(term: "", context: context, subject: lensSubject, selection: text,
                                                     question: "Spiega in modo chiaro e ordinato il brano selezionato.")
                }
                let value = try await AIEngineRouter.explain(request, configuration: configuration, consentKey: consent)
                guard page?.id == pageID else { status = "Nota non inserita: la pagina è cambiata."; return }
                let title = term ? value.term : "Spiegazione · " + EditorViewModel.lensTopic(text)
                if let id = insertLensNote(value, title: title, near: area) {
                    let reduced = page?.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed == true
                    status = reduced ? "Nota ridotta a 💡 accanto al testo: toccala per aprirla" : "Nota inserita: \(title)"
                } else { status = "Spiegazione pronta, ma il foglio è occupato: riprova." }
            } catch is CancellationError { status = "" }
            catch { status = ""; self.error = "Lente AI: \(error.localizedDescription)" }
        }
    }

    /// A few words that name a passage in a note title.
    static func lensTopic(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        return words.prefix(6).joined(separator: " ") + (words.count > 6 ? "…" : "")
    }
}
