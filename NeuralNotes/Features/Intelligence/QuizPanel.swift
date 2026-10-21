import SwiftUI
import NeuralNotesCore

@MainActor
struct QuizPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var run: QuizRun?
    @State private var history: [QuizRun] = []
    @State private var mode = QuizMode.study
    @State private var minutes = 20
    @State private var count = 8
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            List {
                if let run { runView(run) } else { setup }
                if busy { ProgressView("Preparazione e salvataggio…") }
                if let error { Text(error).foregroundStyle(.red) }
                if !history.isEmpty && run == nil { historyView }
            }.navigationTitle("Quiz e simulazione")
                .task { await load() }
                .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
                .onDisappear { job?.cancel() }
                .onChange(of: configuration) { _, _ in job?.cancel() }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() }.disabled(busy) } }
        }
    }
    private var setup: some View {
        Section("Prepara il ripasso") {
            Picker("Modalità", selection: $mode) { Text("Studio").tag(QuizMode.study); Text("Esame").tag(QuizMode.exam) }.pickerStyle(.segmented)
            Stepper("\(count) domande al massimo", value: $count, in: 3...12)
            if mode == .exam { Stepper("\(minutes) minuti", value: $minutes, in: 5...120, step: 5) }
            Text(mode == .exam ? "Risposte e spiegazioni si rivelano alla consegna. Il tempo continua se chiudi il pannello o passi in background." : "Ogni risposta viene salvata e poi mostra la spiegazione. Puoi riprendere il quiz dopo la chiusura.").font(.caption).foregroundStyle(.secondary)
            Button("Quiz locale dalle flashcard", systemImage: "rectangle.stack") { prepare(remote: false) }.disabled(busy)
            Text("Usa le risposte delle flashcard come alternative. Servono almeno quattro risposte diverse; non è una generazione AI.").font(.caption).foregroundStyle(.secondary)
            Button("Connessione AI", systemImage: "slider.horizontal.3") { configuring = true }.disabled(busy)
            Button("Genera quiz con il backend", systemImage: "sparkles") { prepare(remote: true) }
                .disabled(busy || configuration.quizURL == nil || consentKey != configuration.consentKey)
            Text("Il backend riceve fino a 40 estratti del quaderno, entro il limite del contesto. Le domande generate mantengono i riferimenti; la qualità va controllata sulle fonti.").font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder
    private func runView(_ value: QuizRun) -> some View {
        Section(value.bank.title) {
            Text("\(value.bank.provider) · \(value.answeredCount)/\(value.bank.questions.count) risposte").font(.caption).foregroundStyle(.secondary)
            if let submitted = value.submittedAt { Text("Risultato: \(value.score)/\(value.bank.questions.count) · \(submitted.formatted(date: .abbreviated, time: .shortened))").font(.headline) }
            else if let deadline = value.deadline {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Tempo rimasto · \(TranscriptText.clock(max(0, deadline.timeIntervalSince(context.date))))").monospacedDigit()
                        .task(id: Int(context.date.timeIntervalSince1970)) { if value.expired(at: context.date), !busy { update { try $0.submit() } } }
                }
            }
            ProgressView(value: Double(value.cursor + 1), total: Double(value.bank.questions.count))
        }
        let question = value.bank.questions[value.cursor]
        Section("\(value.cursor + 1). \(question.prompt)") {
            ForEach(question.options.indices, id: \.self) { index in
                Button { update { try $0.choose(index, question: value.cursor) } } label: {
                    HStack(alignment: .top) {
                        Image(systemName: value.answers[value.cursor] == index ? "largecircle.fill.circle" : "circle")
                        Text(question.options[index]).foregroundStyle(.primary)
                    }
                }.buttonStyle(.borderless).disabled(busy || value.submittedAt != nil || (value.mode == .study && value.answers[value.cursor] != nil))
            }
            if value.submittedAt != nil || (value.mode == .study && value.answers[value.cursor] != nil) {
                Label(value.answers[value.cursor] == question.correctIndex ? "Risposta corretta" : "Risposta corretta: \(question.options[question.correctIndex])", systemImage: value.answers[value.cursor] == question.correctIndex ? "checkmark.circle" : "info.circle")
                Text(question.explanation).textSelection(.enabled)
                ForEach(Array(question.references.enumerated()), id: \.offset) { row in
                    Button("Fonte \(row.offset + 1)", systemImage: "doc.text.magnifyingglass") { Task { await open(row.element) } }.buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Precedente", systemImage: "chevron.left") { go(value.cursor - 1) }.disabled(value.cursor == 0 || busy)
                Spacer()
                Button("Successiva", systemImage: "chevron.right") { go(value.cursor + 1) }.disabled(value.cursor + 1 == value.bank.questions.count || busy)
            }.buttonStyle(.borderless)
        }
        Section {
            if value.submittedAt == nil {
                Button("Consegna e mostra il risultato", systemImage: "checkmark.seal") { update { try $0.submit() } }.disabled(busy)
                Button("Archivia e prepara un altro quiz") {
                    guard !busy else { return }; busy = true
                    job = Task { defer { busy = false }; do { try await model.workspace.archiveActiveQuiz(); run = nil; await load() } catch { self.error = error.localizedDescription } }
                }.disabled(busy)
            } else {
                Button("Prepara un altro quiz") { run = nil }
                ShareLink("Condividi risultato", item: "\(value.bank.title)\nRisultato: \(value.score)/\(value.bank.questions.count)\n\(value.bank.provider)")
            }
        }
    }
    private var historyView: some View {
        Section("Ultimi quiz · fino a 10") {
            ForEach(history.reversed()) { value in
                Button {
                    if value.submittedAt != nil { run = value }
                    else {
                        guard !busy else { return }; busy = true
                        job = Task { defer { busy = false }; do { run = try await model.workspace.resumeQuiz(value.id) } catch { self.error = error.localizedDescription } }
                    }
                } label: { VStack(alignment: .leading) { Text(value.bank.title); Text(value.submittedAt == nil ? "Da riprendere · \(value.answeredCount) risposte" : "\(value.score)/\(value.bank.questions.count) · \(value.startedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) } }
            }
        }
    }
    private func load() async {
        do { let catalog = try await model.workspace.catalog(); history = catalog.quizHistory ?? []; if run == nil { run = catalog.activeQuiz } }
        catch { self.error = error.localizedDescription }
    }
    private func update(_ mutation: @escaping (inout QuizRun) throws -> Void) {
        guard !busy, var next = run else { return }; busy = true; error = nil
        job = Task {
            defer { busy = false }
            do { try mutation(&next); try await model.workspace.saveQuiz(next); run = next; await load() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func go(_ index: Int) {
        guard let run, run.bank.questions.indices.contains(index) else { return }
        if run.submittedAt != nil { self.run?.cursor = index }
        else { update { $0.cursor = index; $0.revision += 1 } }
    }
    private func prepare(remote: Bool) {
        guard !busy else { return }; busy = true; error = nil
        job = Task {
            defer { busy = false }
            do {
                guard await model.flush() else { return }
                let chunks = try await model.workspace.indexedChunks()
                let bank: QuizBank
                if remote {
                    let selection = SourceContext.select(chunks, spread: true)
                    bank = try await AIEngineRouter.quiz(QuizRequest(sources: selection.sources, count: count), configuration: configuration, consentKey: consentKey)
                } else {
                    let cards = try await model.workspace.catalog().studyCards ?? []
                    guard let local = QuizBuilder.make(cards: cards + StudyCardBuilder.make(from: chunks, limit: 100), limit: count, seed: UInt64.random(in: 0...UInt64.max)) else {
                        error = "Servono almeno quattro risposte diverse nelle flashcard o nei testi salvati."; return
                    }; bank = local
                }
                try Task.checkCancellation()
                run = try await model.workspace.startQuiz(bank, mode: mode, minutes: minutes); await load()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func open(_ reference: SourceReference) async {
        if let page = reference.pageID { await model.openPageLink(PageLinkTarget(documentID: reference.documentID, pageID: page)) }
        else if let session = model.audio?.sessions.first(where: { $0.id == reference.audioSessionID }) { await model.audio?.play(session, at: reference.seconds ?? 0) }
    }
}
