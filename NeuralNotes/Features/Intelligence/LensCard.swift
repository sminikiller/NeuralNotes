import SwiftUI
import NeuralNotesCore

/// The card next to a circled area, a touched photo or a selected text: what was
/// read, quick actions, a free question and the answer, ready to become a note.
@MainActor
struct LensCard: View {
    let model: EditorViewModel
    let request: LensCardRequest
    let openChat: () -> Void
    let insertPhoto: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var text = ""
    @State private var picture: String?
    @State private var preview: UIImage?
    @State private var reading = true
    @State private var busy = false
    @State private var question = ""
    @State private var asked = ""
    @State private var answer: TermExplanation?
    @State private var notice: String?
    @State private var error: String?
    @State private var inserted = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.headline)
                    Spacer()
                    Text(configuration.engine == .offline ? "Nessun motore" : configuration.engine.title).font(.caption).foregroundStyle(.secondary)
                    Button("Chiudi", systemImage: "xmark.circle.fill") { dismiss() }.labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
                if !engineReady { setup } else if consentKey != configuration.consentKey { consent }
                if reading { ProgressView("Leggo la selezione…") } else { selection; actions; result }
                Divider()
                Button("Chat sulla pagina", systemImage: "bubble.left.and.text.bubble.right") { dismiss(); openChat() }.font(.caption)
            }.padding(14)
        }
        .frame(width: 380).frame(minHeight: 220, maxHeight: 620)
        .task { await prepare() }
        .onDisappear { job?.cancel() }
        .sheet(isPresented: $configuring, onDismiss: { Task { configuration = AIEngineStore.load(); consentKey = await AIEngineRouter.restoredConsent(configuration) } }) {
            AIConnectionPanel(configuration: $configuration, consentKey: $consentKey)
        }
    }

    private var engineReady: Bool {
        guard configuration.supportsStructuredStudy else { return false }
        return configuration.engine == .backend || !EngineCredentials.load(configuration.engine).isEmpty
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collega un motore AI").font(.subheadline.bold())
            Text("Basta una chiave personale: DeepSeek (economico), OpenAI, Claude o Gemini. Nessun account richiesto.").font(.caption)
            Button("Collega adesso", systemImage: "bolt.fill") { configuring = true }.buttonStyle(.borderedProminent)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inviare la selezione a \(configuration.engine.title)?").font(.subheadline.bold())
            Text("Il testo letto (e l’immagine, se c’è) parte solo quando premi un’azione. La scelta vale per questo motore.").font(.caption)
            HStack {
                Button("Sì, sempre") { grant() }.buttonStyle(.borderedProminent)
                Button("Impostazioni") { configuring = true }.buttonStyle(.bordered)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var selection: some View {
        if let preview {
            Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 150).clipShape(RoundedRectangle(cornerRadius: 8))
            if let photo = request.photo {
                Button("Inserisci la foto nella pagina", systemImage: "photo.badge.plus") { dismiss(); insertPhoto(photo) }.font(.caption)
            }
        }
        TextField(picture == nil ? "Testo selezionato" : "Testo letto nell’immagine (facoltativo)", text: $text, axis: .vertical)
            .lineLimit(1...5).textFieldStyle(.roundedBorder)
        if text.isEmpty && picture == nil { Text("Nessun testo letto: scrivilo qui o cerchia una zona più grande.").font(.caption).foregroundStyle(.secondary) }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    if picture != nil { quick("Descrivi", "Descrivi cosa mostra l’immagine e cosa è utile sapere per studiarla.") }
                    quick("Chi è / Cos’è", "")
                    quick("Spiega", "Spiega in modo semplice e chiaro il contenuto selezionato.")
                    quick("Riassumi", "Riassumi il contenuto selezionato in 3-5 punti brevi.")
                    quick("Traduci", "Traduci in italiano il testo selezionato.")
                }.buttonStyle(.bordered).font(.caption)
            }
            HStack {
                TextField("Chiedi qualcosa su questa selezione…", text: $question, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
                Button { let value = question; question = ""; ask(value) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(!canAsk || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Invia domanda")
            }
        }
    }

    @ViewBuilder private var result: some View {
        if busy { HStack { ProgressView(); Text("Sto chiedendo a \(configuration.engine.title)…").font(.caption); Spacer(); Button("Stop") { job?.cancel() }.font(.caption) } }
        if let answer {
            VStack(alignment: .leading, spacing: 6) {
                Text(asked.isEmpty ? answer.term : asked).font(.subheadline.bold())
                Text(answer.noteBody).textSelection(.enabled)
                Text(answer.origin).font(.caption2).foregroundStyle(.secondary)
                if let notice { Text(notice).font(.caption2).foregroundStyle(.orange) }
                HStack {
                    Button(inserted ? "Nota inserita" : "Inserisci come nota", systemImage: inserted ? "checkmark" : "note.text.badge.plus") { insert(answer) }
                        .buttonStyle(.borderedProminent).disabled(inserted)
                    Button("Copia", systemImage: "doc.on.doc") { UIPasteboard.general.string = "\(answer.term)\n\(answer.noteBody)" }.buttonStyle(.bordered)
                }.font(.caption)
            }.padding(10).background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        if let error { Text(error).font(.caption).foregroundStyle(.red) }
    }

    private var canAsk: Bool {
        !busy && !reading && engineReady && consentKey == configuration.consentKey
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || picture != nil)
    }

    private func quick(_ title: String, _ prompt: String) -> some View {
        Button(title) { ask(prompt) }.disabled(!canAsk)
    }

    private func prepare() async {
        consentKey = await AIEngineRouter.restoredConsent(configuration)
        if let known = request.text { text = known }
        if let photo = request.photo, let image = try? DocumentServices.photoPreview(photo) {
            preview = image; picture = LensReader.jpegBase64(image)
            if text.isEmpty { text = await LensReader.ocr(photo) }
        } else if let id = request.imageID, let image = await LensReader.picture(id, model: model) {
            preview = image; picture = LensReader.jpegBase64(image)
            if text.isEmpty, let png = image.pngData() { text = await LensReader.ocr(png) }
        } else if let area = request.area {
            if text.isEmpty { text = await LensReader.text(in: area, model: model) }
            if LensSettings.mode == .image || text.isEmpty, let crop = LensReader.crop(area, model: model, maxDimension: 1600) {
                preview = crop; picture = LensReader.jpegBase64(crop)
            }
        }
        reading = false
        if request.startWithExplain, canAsk { ask("") }
    }

    private func grant() {
        Task {
            do { try await AIEngineRouter.rememberConsent(configuration, allowed: true); consentKey = configuration.consentKey }
            catch { self.error = error.localizedDescription }
            if request.startWithExplain, answer == nil, canAsk { ask("") }
        }
    }

    /// Short selections are terms; longer ones are passages and get a question even
    /// for "Chi è / Cos’è". The image goes along when there is one; if the engine
    /// cannot read images, the answer is retried with the recognized text only.
    private func ask(_ prompt: String) {
        guard canAsk else { return }
        busy = true; error = nil; notice = nil; answer = nil; inserted = false; asked = prompt
        let selected = configuration, consent = consentKey, subject = model.lensSubject, image = picture
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = words.count <= 120 && words.split(whereSeparator: \.isWhitespace).count <= 12
        let asking = !prompt.isEmpty || short || image != nil ? prompt : "Spiega il contenuto selezionato in modo chiaro."
        job = Task {
            defer { busy = false }
            let pageText = await LensReader.pageText(model: model)
            let context = TermExplanationRequest.context(for: short ? words : String(words.prefix(80)), in: pageText)
            func make(_ image: String?) -> TermExplanationRequest {
                TermExplanationRequest(term: short ? words : "", context: context, subject: subject, selection: short ? "" : words,
                                       question: asking.isEmpty && image != nil && words.isEmpty ? "Descrivi l’immagine." : asking, image: image)
            }
            do {
                answer = try await AIEngineRouter.explain(make(image), configuration: selected, consentKey: consent)
            } catch is CancellationError {
            } catch _ where image != nil && !words.isEmpty {
                do {
                    answer = try await AIEngineRouter.explain(make(nil), configuration: selected, consentKey: consent)
                    notice = "Il motore non ha letto l’immagine: risposta basata sul testo riconosciuto."
                } catch is CancellationError {
                } catch { self.error = error.localizedDescription }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func insert(_ value: TermExplanation) {
        let anchor: CGRect?
        if request.fromSidePDF { anchor = nil }
        else if let id = request.imageID, let image = model.page?.images.first(where: { $0.id == id }) { anchor = CGRect(x: image.x, y: image.y, width: image.width, height: image.height) }
        else { anchor = request.area }
        if model.insertTermNote(value, near: anchor) { inserted = true; model.status = "Nota della Lente inserita" }
        else { error = "Il foglio è occupato: finisci il tratto e riprova." }
    }
}
