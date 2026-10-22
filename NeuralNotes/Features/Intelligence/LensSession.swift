import UIKit
import Observation
import NeuralNotesCore

/// One question and its answer in a Lens conversation.
struct LensTurn: Identifiable {
    let id = UUID()
    var label: String
    var icon: String
    /// Title of the note made from this answer.
    var noteTitle: String
    var answer: TermExplanation
    var notice: String?
    var noteID: UUID?
    var notePageID: UUID?
}

/// The conversation about one selection: what was read, the questions asked and
/// the answers, ready to become notes. It lives in the editor model, so the side
/// panel and the floating window show the same conversation.
@MainActor @Observable
final class LensSession: Identifiable {
    let id = UUID()
    let request: LensCardRequest
    var configuration = AIEngineStore.load()
    var consentKey: String?
    var text = ""
    var picture: String?
    var preview: UIImage?
    var reading = true
    var busy = false
    var pending = ""
    var turns: [LensTurn] = []
    var error: String?
    @ObservationIgnored private var job: Task<Void, Never>?

    init(request: LensCardRequest) {
        self.request = request
        text = request.text ?? ""
    }

    var engineReady: Bool {
        guard configuration.supportsStructuredStudy else { return false }
        return configuration.engine == .backend || !EngineCredentials.load(configuration.engine).isEmpty
    }
    var consented: Bool { consentKey == configuration.consentKey }
    private var words: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A name, a date or a term rather than a passage.
    var isShortSelection: Bool { !words.isEmpty && words.count <= 120 && words.split(whereSeparator: \.isWhitespace).count <= 12 }
    var canAsk: Bool { !busy && !reading && engineReady && consented && (!words.isEmpty || picture != nil) }
    /// A few words that name the selection in titles.
    var topic: String {
        if isShortSelection { return words }
        if words.isEmpty { return picture == nil ? "Selezione" : "Immagine" }
        return words.split(whereSeparator: \.isWhitespace).prefix(6).joined(separator: " ") + "…"
    }
    var prompts: [LensPrompt] {
        var list: [LensPrompt] = []
        if picture != nil { list.append(LensPrompt.describe) }
        if isShortSelection { list.append(LensPrompt.explainTerm) }
        return list + LensPrompt.study
    }

    func cancel() { job?.cancel() }

    func refreshEngine() async {
        configuration = AIEngineStore.load()
        consentKey = await AIEngineRouter.restoredConsent(configuration)
    }

    /// Reads the selection: the cropped photo, the touched image or the area of the page.
    func prepare(_ model: EditorViewModel) async {
        await refreshEngine()
        if let photo = request.photo, var image = try? DocumentServices.photoPreview(photo) {
            if let crop = request.photoCrop { image = LensReader.cropped(image, to: crop) }
            preview = image; picture = LensReader.jpegBase64(image)
            if text.isEmpty, let png = image.pngData() { text = await LensReader.ocr(png) }
        } else if let id = request.imageID, let image = await LensReader.picture(id, model: model) {
            preview = image; picture = LensReader.jpegBase64(image)
            if text.isEmpty, let png = image.pngData() { text = await LensReader.ocr(png) }
        } else if let area = request.area, request.pageID == nil || request.pageID == model.page?.id {
            if text.isEmpty { text = await LensReader.text(in: area, model: model) }
            if LensSettings.mode == .image || text.isEmpty, let crop = LensReader.crop(area, model: model, maxDimension: 1600) {
                preview = crop; picture = LensReader.jpegBase64(crop)
            }
        }
        reading = false
        if request.startWithExplain, canAsk { ask(.explainTerm, model: model) }
    }

    func grant(_ model: EditorViewModel) {
        Task {
            do { try await AIEngineRouter.rememberConsent(configuration, allowed: true); consentKey = configuration.consentKey }
            catch { self.error = error.localizedDescription }
            if request.startWithExplain, turns.isEmpty, canAsk { ask(.explainTerm, model: model) }
        }
    }

    func ask(_ prompt: LensPrompt, model: EditorViewModel) {
        let title = prompt.prompt.isEmpty ? topic : "\(prompt.label) · \(topic)"
        ask(label: prompt.prompt.isEmpty ? topic : prompt.label, icon: prompt.icon, noteTitle: title, question: prompt.prompt, model: model)
    }

    func ask(question: String, model: EditorViewModel) {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        ask(label: value, icon: "bubble.left", noteTitle: TermExplanationRequest(term: "", question: value).title, question: value, model: model)
    }

    /// Short selections are terms; longer ones are passages and get a question even for
    /// "Chi è / Cos’è". The last answers travel as context, so follow-up questions work.
    /// The image goes along when there is one; if the engine cannot read images, the
    /// answer is retried with the recognized text only.
    private func ask(label: String, icon: String, noteTitle: String, question prompt: String, model: EditorViewModel) {
        guard canAsk else { return }
        busy = true; error = nil; pending = label
        let selected = configuration, consent = consentKey, subject = model.lensSubject, image = picture
        let words = self.words, short = isShortSelection
        let asking = !prompt.isEmpty || short || image != nil ? prompt : "Spiega il contenuto selezionato in modo chiaro."
        let history = turns.suffix(2).map { "Domanda: \($0.label)\nRisposta: \($0.answer.explanation.prefix(600))" }.joined(separator: "\n\n")
        job = Task {
            defer { busy = false; pending = "" }
            let pageText = await LensReader.pageText(model: model)
            let around = TermExplanationRequest.context(for: short ? words : String(words.prefix(80)), in: pageText)
            let context = history.isEmpty ? around : "Conversazione precedente:\n\(history)\n\nTesto della pagina:\n\(around)"
            func make(_ image: String?) -> TermExplanationRequest {
                TermExplanationRequest(term: short ? words : "", context: context, subject: subject, selection: short ? "" : words,
                                       question: asking.isEmpty && image != nil && words.isEmpty ? "Descrivi l’immagine." : asking, image: image)
            }
            do {
                let answer = try await AIEngineRouter.explain(make(image), configuration: selected, consentKey: consent)
                turns.append(LensTurn(label: label, icon: icon, noteTitle: noteTitle, answer: answer))
            } catch is CancellationError {
            } catch _ where image != nil && !words.isEmpty {
                do {
                    let answer = try await AIEngineRouter.explain(make(nil), configuration: selected, consentKey: consent)
                    turns.append(LensTurn(label: label, icon: icon, noteTitle: noteTitle, answer: answer,
                                          notice: "Il motore non ha letto l’immagine: risposta basata sul testo riconosciuto."))
                } catch is CancellationError {
                } catch { self.error = error.localizedDescription }
            } catch { self.error = error.localizedDescription }
        }
    }

    /// Puts an answer on the page as a Lens note, linked to the selected text.
    func insert(_ turnID: UUID, model: EditorViewModel) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        let turn = turns[index]
        var anchor: CGRect?
        if !request.fromSidePDF, request.pageID == nil || request.pageID == model.page?.id {
            if let id = request.imageID, let image = model.page?.images.first(where: { $0.id == id }) {
                anchor = CGRect(x: image.x, y: image.y, width: image.width, height: image.height)
            } else { anchor = request.area }
        }
        guard let id = model.insertLensNote(turn.answer, title: turn.noteTitle, near: anchor, useSelection: false) else {
            error = "Il foglio è occupato: finisci il tratto e riprova."; return
        }
        turns[index].noteID = id; turns[index].notePageID = model.page?.id
        let reduced = model.page?.texts.first(where: { $0.id == id })?.lensNote?.isCollapsed == true
        model.status = reduced ? "Nota inserita come 💡 accanto al testo: toccala per aprirla" : "Nota della Lente inserita"
    }
}
