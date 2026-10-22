import SwiftUI
import CryptoKit
import PencilKit
import NeuralNotesCore

@MainActor
struct LensPanel: View {
    @Bindable var model: EditorViewModel
    let notebook: Notebook
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var glossary = false
    @State private var lookup = false
    @State private var question = ""
    @State private var turns: [AIConversationTurn] = []
    @State private var sources: [IndexedChunk] = []
    @State private var partial = ""
    @State private var busy = false
    @State private var sourcesLoading = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @State private var jobGeneration = UUID()
    @State private var lastAutomaticKey: String?
    @State private var cardDrafts: [FlashcardDraft] = []
    @State private var discardedCards: Set<UUID> = []
    @State private var cardsProvider = ""
    @State private var cardsSheet = false
    @State private var lastNote: TermExplanation?
    @AppStorage("lens.autoAnnotate") private var autoAnnotate = true
    var body: some View {
        VStack(spacing: 10) {
            HStack { Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.headline).accessibilityIdentifier("lensPanelTitle"); Spacer(); Button { glossary = true } label: { Image(systemName: "character.book.closed") }.accessibilityLabel("Glossario"); settings }.padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(configuration.engine != .offline ? "Risposte sulle fonti selezionate, con riferimenti." : "Modalità offline: estratti delle fonti, senza modello generativo.").font(.caption).foregroundStyle(.secondary)
                    Text("\(sources.count) fonti · area cerchiata o selezione; altrimenti la pagina corrente").font(.caption)
                    if sourcesLoading { ProgressView("Lettura della selezione…") }
                    if sourcesChanged { Button("Pagina modificata: aggiorna le fonti", systemImage: "arrow.clockwise") { Task { await load() } }.font(.caption) }
                    if configuration.engine != .offline && consentKey != configuration.consentKey { Text("Attiva questa connessione AI dal pulsante delle impostazioni prima di inviare le fonti.").font(.caption).foregroundStyle(.secondary) }
                    Toggle("Spiega e annota da sola i termini sottolineati con la Lente", isOn: $autoAnnotate).font(.caption)
                    if let lastNote {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nota inserita · \(lastNote.term)").font(.caption.bold())
                            Text(lastNote.noteBody).font(.caption).textSelection(.enabled)
                            Text(lastNote.origin).font(.caption2).foregroundStyle(.secondary)
                            Button("Annulla la nota", systemImage: "arrow.uturn.backward") { Task { await model.performUndo(); self.lastNote = nil } }.font(.caption)
                        }.padding(8).background(Color.yellow.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                    }
                    ForEach(turns) { turn in
                        Text(turn.question).font(.headline)
                        CitedAnswer(artifact: turn.answer)
                        HStack {
                            Button("Inserisci", systemImage: "text.badge.plus") { insert(turn.answer) }.disabled(model.hasActiveStroke || model.navigating || model.loading)
                            Button("Glossario", systemImage: "character.book.closed") {
                                Task {
                                    do { try await model.workspace.saveGlossaryEntry(GlossaryEntry(term: String(turn.question.prefix(120)), definition: String(turn.answer.text.prefix(16000)), references: turn.answer.references)); glossary = true }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
                            Button("Flashcard", systemImage: "rectangle.on.rectangle") { makeCards(turn) }
                                .disabled(busy || turn.answer.references.isEmpty)
                        }.buttonStyle(.bordered).font(.caption)
                        ForEach(Array(turn.answer.references.enumerated()), id: \.offset) { item in
                            Button(sourceTitle(item.element)) { Task { await open(item.element) } }.font(.caption)
                        }
                        Divider()
                    }
                    if busy {
                        if partial.isEmpty { ProgressView("Elaborazione…") } else { Text(partial); Text("Risposta in corso · riferimenti verificati al termine").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.padding()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Spiega e annota", systemImage: "note.text.badge.plus") { if let request = termRequest(strict: false) { annotate(request) } }
                        .buttonStyle(.borderedProminent).disabled(!canSend || termRequest(strict: false) == nil || !configuration.supportsStructuredStudy)
                    Button("Scheda definizione", systemImage: "character.book.closed") { lookup = true }.buttonStyle(.bordered).disabled(busy || sourcesLoading || sourcesChanged || sources.isEmpty)
                    ForEach(["Spiega", "Definisci", "Semplifica", "Traduci in italiano", "Fai un esempio"], id: \.self) { prompt in Button(prompt) { question = prompt; send(continuation: false) }.buttonStyle(.bordered).disabled(!canSend) }
                }.padding(.horizontal)
            }
            HStack {
                TextField("Chiedi sulle fonti…", text: $question, axis: .vertical).lineLimit(1...4)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(!canSend || question.isEmpty).accessibilityLabel("Invia alla Lente AI")
                if busy { Button("Stop") { job?.cancel() } }
            }.padding()
        }.sheet(isPresented: $glossary) { GlossaryPanel(model: model) }
        .sheet(isPresented: $lookup) { LookupPanel(model: model, sources: sources, configuration: configuration, consentKey: consentKey) }
        .sheet(isPresented: $cardsSheet) { cardsReview }
        .task(id: selectionKey) { await load() }
            .onChange(of: configuration) { _, _ in job?.cancel() }
            .onDisappear { jobGeneration = UUID(); job?.cancel() }
    }
    private var selectionKey: String {
        let objects = model.selectedIDs.map(\.uuidString).sorted().joined(separator: ",")
        let strokes = (model.selectedStrokeIndices ?? []).sorted().map(String.init).joined(separator: ",")
        return "\(model.page?.id.uuidString ?? "")|\(objects)|\(strokes)|\(model.selectionIncludesInk)|\(String(describing: model.lensArea))|\(model.lensTextSelection ?? "")|\(model.lensRequest)|\(configuration.consentKey)"
    }
    private var sourcesChanged: Bool {
        !sources.isEmpty && (model.dirty || sources.contains { $0.reference.pageID != model.page?.id || $0.reference.pageRevision != model.page?.revision })
    }
    private var canSend: Bool { !busy && !sourcesLoading && !sourcesChanged && !sources.isEmpty && (configuration.engine == .offline || consentKey == configuration.consentKey) }
    private var settings: some View {
        Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }
            .accessibilityLabel("Connessione AI").accessibilityIdentifier("aiConnectionSettings")
            .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
    }
    private func load() async {
        jobGeneration = UUID(); job?.cancel(); busy = false; partial = ""; sources = []; error = nil; sourcesLoading = true
        let key = selectionKey
        defer { if key == selectionKey { sourcesLoading = false } }
        if consentKey == nil { consentKey = await AIEngineRouter.restoredConsent(configuration) }
        turns = (try? await model.workspace.catalog().conversation) ?? []
        guard !Task.isCancelled, key == selectionKey else { return }
        await loadSources(key: key)
        guard !Task.isCancelled, key == selectionKey else { return }
        sourcesLoading = false
        // An underlined or circled term with the Lente tool gets an explaining note
        // by itself, when the student enabled it and approved the AI connection.
        if model.lensPrefersPopup, model.lensArea != nil, autoAnnotate, canSend, lastAutomaticKey != key,
           configuration.supportsStructuredStudy, let request = termRequest(strict: true) {
            lastAutomaticKey = key; annotate(request); return
        }
        // Only an intentional Lente gesture and an already approved managed
        // account can start a request automatically. Ordinary ink is untouched.
        if model.lensPrefersPopup, canSend, lastAutomaticKey != key,
           await ManagedAIAccount.isManaged(configuration) {
            lastAutomaticKey = key; question = "Spiega brevemente il testo selezionato, usando le fonti disponibili."
            send(continuation: false)
        }
    }
    private func loadSources(key: String) async {
        guard await model.flush(), let page = model.page else { return }
        do {
            try Task.checkCancellation(); guard key == selectionKey else { return }
            let exact = model.lensTextSelection
            var text = exact ?? page.texts.filter { model.selectedIDs.isEmpty || model.selectedIDs.contains($0.id) }.map(\.text).joined(separator: "\n")
            let visual = model.selectionIncludesInk || page.images.contains(where: { model.selectedIDs.contains($0.id) })
                || (page.shapes ?? []).contains(where: { model.selectedIDs.contains($0.id) })
            let area = model.lensArea ?? (visual ? model.selectionBounds : nil)
            if exact == nil, let area, !area.isNull, area.width > 3, area.height > 3 {
                let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 1600)
                let box = area.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
                let pixel = CGRect(x: box.minX * image.scale, y: box.minY * image.scale, width: box.width * image.scale, height: box.height * image.scale)
                if let cropped = image.cgImage?.cropping(to: pixel), let data = UIImage(cgImage: cropped).pngData() {
                    text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
                }
            } else if exact == nil && model.selectedIDs.isEmpty {
                text += "\n" + page.recognizedText
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, page.pdfFile != nil {
                    text = try await DocumentServices.pdfText(page: page, workspace: model.workspace)
                }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 1600)
                    if let data = image.pngData() { text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n") }
                }
            }
            try Task.checkCancellation()
            guard key == selectionKey, model.page?.id == page.id else { return }
            let chunks = text.split(separator: "\n").prefix(20).map { IndexedChunk(text: String($0.prefix(4000)), reference: SourceReference(documentID: notebook.documentID, pageID: page.id, pageRevision: page.revision)) }
            sources = SourceContext.select(chunks, maximumSources: 20, maximumPerSource: 4000).sources
            if sources.isEmpty { error = "Nessun testo riconoscibile nella selezione. Seleziona testo o un’area più leggibile." } else { error = nil }
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func send(continuation: Bool = true) {
        guard canSend else { return }
        let prompt = String(question.prefix(1000)); question = ""; error = nil; partial = ""; busy = true
        let selectedSources = sources, selectedConfiguration = configuration, selectedConsent = consentKey, previousTurns = turns
        let key = selectionKey, generation = UUID(); jobGeneration = generation
        job = Task {
            defer { if jobGeneration == generation { busy = false; partial = "" } }
            do {
                let scope = try await AIEngineRouter.cacheScope(selectedConfiguration)
                let context = (continuation ? Array(previousTurns.suffix(2)) : []).map { "Domanda: \($0.question.prefix(300))\nRisposta precedente: \($0.answer.text.prefix(500))" }.joined(separator: "\n")
                let request = AIRequest(task: .chat, question: "\(context)\nDomanda attuale: \(prompt)", sources: selectedSources)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                var identity = try encoder.encode(request); identity.append(Data(selectedConfiguration.consentKey.utf8))
                identity.append(Data("|account:\(scope)".utf8))
                let cacheKey = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
                let answer: AIArtifact
                if let cached = try? await model.workspace.cachedLensAnswer(key: cacheKey) { answer = cached }
                else {
                    answer = try await AIEngineRouter.generate(request, configuration: selectedConfiguration, consentKey: selectedConsent) { delta in
                        if jobGeneration == generation && key == selectionKey { partial += delta }
                    }
                    try Task.checkCancellation()
                    guard jobGeneration == generation, key == selectionKey,
                          try await AIEngineRouter.cacheScope(selectedConfiguration) == scope else { throw CancellationError() }
                    try? await model.workspace.cacheLensAnswer(key: cacheKey, artifact: answer)
                }
                try Task.checkCancellation()
                guard jobGeneration == generation, key == selectionKey,
                      try await AIEngineRouter.cacheScope(selectedConfiguration) == scope else { throw CancellationError() }
                let turn = AIConversationTurn(question: prompt, answer: answer)
                turns = Array((turns + [turn]).suffix(20))
                do { try await model.workspace.saveConversationTurn(turn) }
                catch { self.error = "Risposta visibile, ma non salvata: \(error.localizedDescription)" }
            } catch is CancellationError { }
            catch { if jobGeneration == generation && key == selectionKey { self.error = error.localizedDescription; question = prompt } }
        }
    }
    /// The selection is a term (a name, a date, a technical word), not a paragraph.
    private func termRequest(strict: Bool) -> TermExplanationRequest? {
        let request = TermExplanationRequest(term: sources.map(\.text).joined(separator: " "), subject: notebook.title)
        return (strict ? request.isTerm : request.isValid) ? request : nil
    }
    /// Explains the term with the model's general knowledge, using the page only to
    /// choose the meaning, then places a sticky note beside the underline.
    private func annotate(_ base: TermExplanationRequest) {
        guard !busy, let page = model.page else { return }
        busy = true; error = nil
        let area = model.lensArea, key = selectionKey, generation = UUID(); jobGeneration = generation
        let selected = configuration, consent = consentKey
        job = Task {
            defer { if jobGeneration == generation { busy = false } }
            do {
                var pageText = page.texts.map(\.text).joined(separator: "\n") + "\n" + page.recognizedText
                if page.pdfFile != nil, let pdf = try? await DocumentServices.pdfText(page: page, workspace: model.workspace) { pageText = pdf + "\n" + pageText }
                let request = TermExplanationRequest(term: base.term, context: TermExplanationRequest.context(for: base.term, in: pageText), subject: base.subject)
                let value = try await AIEngineRouter.explain(request, configuration: selected, consentKey: consent)
                try Task.checkCancellation()
                guard jobGeneration == generation, key == selectionKey, model.page?.id == page.id else { return }
                lastNote = value
                if model.insertTermNote(value, near: area) { model.status = "Nota della Lente inserita: \(value.term)" }
                else { error = "Spiegazione pronta, ma il foglio è occupato: riprova dopo aver finito il tratto." }
            } catch is CancellationError { }
            catch { if jobGeneration == generation { self.error = error.localizedDescription } }
        }
    }
    private var cardsReview: some View {
        NavigationStack {
            List {
                FlashcardDraftsEditor(drafts: $cardDrafts, discarded: $discardedCards, title: cardsProvider, busy: busy) { kept in
                    Task {
                        do {
                            try await model.workspace.addStudyCards(kept.compactMap { $0.card() })
                            model.status = "\(kept.count) flashcard salvate"; cardsSheet = false
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }.navigationTitle("Flashcard dalla risposta")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { cardsSheet = false } } }
        }
    }
    /// Cards from a Lens answer: generated with the chosen engine when possible,
    /// otherwise one local card asking about the selected subject.
    private func makeCards(_ turn: AIConversationTurn) {
        guard !busy, let reference = turn.answer.references.first else { return }
        let subject = sources.first?.text ?? turn.question
        let fallback = FlashcardDraft.local(subject: subject, answer: turn.answer.text, reference: reference)
        guard configuration.supportsStructuredStudy, consentKey == configuration.consentKey else {
            cardDrafts = [fallback]; discardedCards = []; cardsProvider = "Bozza locale"; cardsSheet = true; return
        }
        let cited = sources.filter { turn.answer.references.contains($0.reference) }.prefix(10)
        let request = FlashcardRequest(sources: [IndexedChunk(text: String(turn.answer.text.prefix(8000)), reference: reference)] + cited,
                                       count: 3, focus: String(turn.question.prefix(300)).replacingOccurrences(of: "\n", with: " "))
        let selected = configuration, consent = consentKey
        busy = true; error = nil
        job = Task {
            defer { busy = false }
            do {
                let set = try await AIEngineRouter.flashcards(request, configuration: selected, consentKey: consent)
                try Task.checkCancellation()
                cardDrafts = set.cards; cardsProvider = set.provider
            } catch is CancellationError { return }
            catch { cardDrafts = [fallback]; cardsProvider = "Bozza locale · \(error.localizedDescription)" }
            discardedCards = []; cardsSheet = true
        }
    }
    private func insert(_ artifact: AIArtifact) {
        _ = model.insertAIAnswer(artifact)
    }
    private func sourceTitle(_ source: SourceReference) -> String {
        if let id = source.pageID, let index = model.pages.firstIndex(where: { $0.id == id }) { return "Fonte · pagina \(index + 1)" }
        return "Fonte · \(TranscriptText.clock(source.seconds ?? 0))"
    }
    private func open(_ source: SourceReference) async {
        if let id = source.pageID, let page = model.pages.first(where: { $0.id == id }) { await model.select(page) }
        else if let id = source.audioSessionID, let session = model.audio?.sessions.first(where: { $0.id == id }) { await model.audio?.play(session, at: source.seconds ?? 0) }
    }
}
