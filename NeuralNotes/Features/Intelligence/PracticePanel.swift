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

    private var due: [StudyCard] { cards.filter { $0.dueAt <= Date() }.sorted { $0.dueAt < $1.dueAt } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(due.count) da ripassare · \(cards.count) totali · \(reviewed) ripassate ora")
                    Button("Crea esercizi dalle fonti", systemImage: "rectangle.stack.badge.plus") { Task { await generate() } }
                    Button("Quiz e simulazione d’esame", systemImage: "checkmark.seal") { quiz = true }
                    Text("Esercizi di completamento estratti dal testo salvato, dai PDF, dall’OCR e dalle trascrizioni. Nessun modello generativo.").font(.caption).foregroundStyle(.secondary)
                }
                if let card = due.first {
                    Section("Ripasso") {
                        Text(card.question).font(.title3).padding(.vertical)
                        if revealed {
                            Text(card.answer).font(.title2.bold()).foregroundStyle(Brand.accent)
                            HStack {
                                rating("Ancora", .again, card)
                                rating("Bene", .good, card)
                                rating("Facile", .easy, card)
                            }.buttonStyle(.bordered)
                        } else { Button("Mostra risposta") { revealed = true }.buttonStyle(.borderedProminent) }
                        Button("Apri la fonte", systemImage: "doc.text.magnifyingglass") { Task { await open(card.source) } }
                        if let id = card.source.pageID, let revision = card.source.pageRevision,
                           model.pages.first(where: { $0.id == id })?.revision != revision {
                            Text("La pagina è cambiata dopo la creazione dell’esercizio. Controlla la fonte.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                } else if !cards.isEmpty {
                    Section {
                        Label("Ripasso completato per ora", systemImage: "checkmark.circle")
                        if let next = cards.map(\.dueAt).min() { Text("Prossimo ripasso: \(next.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                    }
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
                if busy { ProgressView() }
            }
            .disabled(busy)
            .navigationTitle("Flashcard e ripasso")
            .task { await reload() }
            .sheet(isPresented: $statistics) { StudyStatisticsPanel(model: model) }
            .sheet(isPresented: $quiz) { QuizPanel(model: model) }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Statistiche", systemImage: "chart.bar") { statistics = true } } }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
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

    private func reload() async {
        try? await model.workspace.setAdaptiveReview(true)
        do { cards = try await model.workspace.catalog().studyCards ?? []; revealed = false }
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
