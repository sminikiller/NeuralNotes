import SwiftUI
import NeuralNotesCore

@MainActor
struct PracticePanel: View {
    let model: EditorViewModel
    let notebook: Notebook
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [StudyCard] = []
    @State private var revealed = false
    @State private var busy = false
    @State private var error: String?
    @State private var reviewed = 0
    @State private var manualQuestion = ""
    @State private var manualAnswer = ""
    @State private var statistics = false
    @State private var quiz = false
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var focus = ""
    @State private var draftCount = 8
    @State private var wholeNotebook = false
    @State private var drafts: [FlashcardDraft] = []
    @State private var discarded: Set<UUID> = []
    @State private var draftProvider = ""
    @State private var studentAnswer = ""
    @State private var feedback: AIArtifact?
    @State private var job: Task<Void, Never>?

    private var due: [StudyCard] { cards.filter { $0.dueAt <= Date() }.sorted { $0.dueAt < $1.dueAt } }
    private var aiReady: Bool { configuration.engine != .offline && consentKey == configuration.consentKey }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(due.count) da ripassare · \(cards.count) totali · \(reviewed) ripassate ora")
                    Button("Crea esercizi dalle fonti", systemImage: "rectangle.stack.badge.plus") { Task { await generate() } }
                    Button("Quiz e simulazione d’esame", systemImage: "checkmark.seal") { quiz = true }
                    Text("Esercizi di completamento estratti dal testo salvato, dai PDF, dall’OCR e dalle trascrizioni. Nessun modello generativo.").font(.caption).foregroundStyle(.secondary)
                }
                if let card = due.first { review(card) }
                else if !cards.isEmpty {
                    Section {
                        Label("Ripasso completato per ora", systemImage: "checkmark.circle")
                        if let next = cards.map(\.dueAt).min() { Text("Prossimo ripasso: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                    }
                }
                generator
                if !drafts.isEmpty {
                    FlashcardDraftsEditor(drafts: $drafts, discarded: $discarded, title: "Bozze · \(draftProvider)", busy: busy) { saveDrafts($0) }
                }
                Section("Crea una flashcard personale") {
                    TextField("Domanda", text: $manualQuestion, axis: .vertical)
                    TextField("Risposta", text: $manualAnswer, axis: .vertical)
                    Button("Salva flashcard") {
                        Task {
                            do {
                                let source = SourceReference(documentID: notebook.documentID, pageID: model.page?.id, pageRevision: model.page?.revision)
                                try await model.workspace.addStudyCards([StudyCard(question: manualQuestion, answer: manualAnswer, source: source)])
                                manualQuestion = ""; manualAnswer = ""; await reload()
                            } catch { self.error = error.localizedDescription }
                        }
                    }.disabled(manualQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manualAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Tutte le flashcard · scorri a sinistra per eliminare") {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.question).lineLimit(3)
                            Text("\(card.reviewCount) ripassi · \(card.dueAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Elimina", role: .destructive) {
                                Task {
                                    do { try await model.workspace.removeStudyCard(card.id); await reload() }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView(); Button("Annulla") { job?.cancel() } }
            }
            .navigationTitle("Flashcard e ripasso")
            .task {
                await reload()
                if consentKey == nil { consentKey = await AIEngineRouter.restoredConsent(configuration) }
            }
            .sheet(isPresented: $statistics) { StudyStatisticsPanel(model: model) }
            .sheet(isPresented: $quiz) { QuizPanel(model: model) }
            .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
            .onChange(of: configuration) { _, _ in job?.cancel() }
            .onDisappear { job?.cancel() }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Statistiche", systemImage: "chart.bar") { statistics = true } } }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }

    @ViewBuilder
    private func review(_ card: StudyCard) -> some View {
        Section("Ripasso") {
            Text(card.question).font(.title3).padding(.vertical)
            if revealed {
                Text(card.answer).font(.title2.bold()).foregroundStyle(Brand.accent)
                if let feedback, let verdict = TutorCheck.verdict(feedback.text) {
                    Text("Suggerimento dalla verifica: \(label(TutorCheck.suggestedRating(verdict)))").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    rating("Ancora", .again, card)
                    rating("Difficile", .hard, card)
                    rating("Bene", .good, card)
                    rating("Facile", .easy, card)
                }.buttonStyle(.bordered).disabled(busy)
            } else {
                TextField("Interrogami: scrivi o detta la tua risposta", text: $studentAnswer, axis: .vertical).lineLimit(2...6).disabled(busy)
                HStack {
                    Button("Verifica con l’AI", systemImage: "graduationcap") { check(card) }
                        .disabled(busy || !aiReady || TutorCheck.request(card: card, answer: studentAnswer, context: []) == nil)
                    Button("Mostra risposta") { revealed = true }.buttonStyle(.borderedProminent)
                }
                if configuration.engine == .offline || consentKey != configuration.consentKey {
                    Text("Per la verifica serve un motore AI con consenso attivo: Connessione AI qui sotto.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let feedback {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Correzione · \(feedback.provider)").font(.caption).foregroundStyle(.secondary)
                    Text(feedback.text).textSelection(.enabled)
                    ForEach(Array(feedback.references.enumerated()), id: \.offset) { row in
                        Button("Fonte [\(row.offset + 1)]") { Task { await open(row.element) } }.font(.caption)
                    }
                }
            }
            Button("Apri la fonte", systemImage: "doc.text.magnifyingglass") { Task { await open(card.source) } }
            if let id = card.source.pageID, let revision = card.source.pageRevision,
               model.pages.first(where: { $0.id == id })?.revision != revision {
                Text("La pagina è cambiata dopo la creazione dell’esercizio. Controlla la fonte.").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var generator: some View {
        Section("Flashcard generate dall’AI") {
            TextField("Argomento (facoltativo)", text: $focus).disabled(busy)
            Stepper("\(draftCount) carte al massimo", value: $draftCount, in: 3...20).disabled(busy)
            Picker("Fonti", selection: $wholeNotebook) {
                Text("Pagina corrente").tag(false); Text("Tutto il quaderno").tag(true)
            }.pickerStyle(.segmented).disabled(busy)
            Button("Genera flashcard con l’AI", systemImage: "sparkles") { generateDrafts() }
                .disabled(busy || !configuration.supportsStructuredStudy || consentKey != configuration.consentKey)
            Button("Connessione AI", systemImage: "slider.horizontal.3") { configuring = true }.disabled(busy)
            Text("Le carte proposte restano bozze: le controlli, le modifichi e salvi solo quelle che vuoi. Ognuna conserva la fonte. Motore: \(configuration.engine.title).").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func label(_ rating: ReviewRating) -> String {
        switch rating { case .again: return "Ancora"; case .hard: return "Difficile"; case .good: return "Bene"; case .easy: return "Facile" }
    }

    private func rating(_ label: String, _ rating: ReviewRating, _ card: StudyCard) -> some View {
        Button(label) {
            guard !busy else { return }; busy = true
            Task {
                defer { busy = false }
                do { try await model.workspace.reviewCard(card.id, rating: rating); reviewed += 1; await reload() }
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func check(_ card: StudyCard) {
        guard !busy else { return }; busy = true; error = nil; feedback = nil
        let answer = studentAnswer, selected = configuration, consent = consentKey
        job = Task {
            defer { busy = false }
            do {
                let context = (try? await model.workspace.indexedChunks()) ?? []
                guard let request = TutorCheck.request(card: card, answer: answer, context: context) else { return }
                let result = try await AIEngineRouter.generate(request, configuration: selected, consentKey: consent)
                try Task.checkCancellation()
                guard due.first?.id == card.id else { return }
                feedback = result; revealed = true
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func generateDrafts() {
        guard !busy else { return }; busy = true; error = nil
        let selected = configuration, consent = consentKey, topic = focus, count = draftCount, notebookWide = wholeNotebook, pageID = model.page?.id
        job = Task {
            defer { busy = false }
            do {
                guard await model.flush() else { return }
                let chunks = try await model.workspace.indexedChunks()
                let scoped = notebookWide ? chunks : chunks.filter { $0.reference.pageID == pageID }
                guard !scoped.isEmpty else { error = "Nessun testo nella pagina: aggiungi testo, esegui OCR o scegli Tutto il quaderno."; return }
                let selection = SourceContext.select(scoped, spread: true)
                let set = try await AIEngineRouter.flashcards(FlashcardRequest(sources: selection.sources, count: count, focus: topic), configuration: selected, consentKey: consent)
                try Task.checkCancellation()
                drafts = set.cards; discarded = []; draftProvider = set.provider
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    private func saveDrafts(_ kept: [FlashcardDraft]) {
        guard !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                try await model.workspace.addStudyCards(kept.compactMap { $0.card() })
                model.status = "\(kept.count) flashcard salvate"
                drafts = []; discarded = []; await reload()
            } catch { self.error = error.localizedDescription }
        }
    }

    private func reload() async {
        try? await model.workspace.setAdaptiveReview(true)
        do { cards = try await model.workspace.catalog().studyCards ?? []; revealed = false; feedback = nil; studentAnswer = "" }
        catch { self.error = error.localizedDescription }
    }

    private func generate() async {
        busy = true; defer { busy = false }
        guard await model.flush() else { return }
        do {
            let chunks = try await FileDocumentIndexingService(workspace: model.workspace, id: notebook.documentID).index(documentID: notebook.documentID)
            let generated = StudyCardBuilder.make(from: chunks)
            guard !generated.isEmpty else { error = "Aggiungi testo o esegui OCR/trascrizione prima di creare gli esercizi."; return }
            try await model.workspace.addStudyCards(generated); await reload()
        } catch { self.error = error.localizedDescription }
    }

    private func open(_ source: SourceReference) async {
        if let id = source.pageID, let page = model.pages.first(where: { $0.id == id }) { await model.select(page); dismiss() }
        else if let id = source.audioSessionID, let session = model.audio?.sessions.first(where: { $0.id == id }) {
            await model.audio?.play(session, at: source.seconds ?? 0)
        }
    }
}
