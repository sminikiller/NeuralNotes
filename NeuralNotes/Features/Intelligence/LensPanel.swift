import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
struct LensPanel: View {
    @Bindable var model: EditorViewModel
    let notebook: Notebook
    @AppStorage("ai.backendURL") private var endpoint = ""
    @AppStorage("ai.lens.remote") private var remote = false
    @State private var configuring = false
    @State private var consent = false
    @State private var token = ""
    @State private var question = ""
    @State private var turns: [AIConversationTurn] = []
    @State private var sources: [IndexedChunk] = []
    @State private var partial = ""
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 10) {
            HStack { Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.headline).accessibilityIdentifier("lensPanelTitle"); Spacer(); settings }.padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(remote ? "Risposte sulle fonti selezionate, con riferimenti." : "Modalità offline: estratti delle fonti, senza modello generativo.").font(.caption).foregroundStyle(.secondary)
                    Text("\(sources.count) fonti · area cerchiata o selezione; altrimenti la pagina corrente").font(.caption)
                    ForEach(turns) { turn in
                        Text(turn.question).font(.headline)
                        Text(turn.answer.text).textSelection(.enabled)
                        HStack {
                            Button("Inserisci", systemImage: "text.badge.plus") { insert(turn.answer) }
                            Button("Flashcard", systemImage: "rectangle.on.rectangle") {
                                guard let reference = turn.answer.references.first else { return }
                                Task {
                                    do { try await model.workspace.addStudyCards([StudyCard(question: turn.question, answer: turn.answer.text, source: reference)]) }
                                    catch { self.error = error.localizedDescription }
                                }
                            }
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
                HStack { ForEach(["Spiega", "Definisci", "Semplifica", "Traduci in italiano", "Fai un esempio"], id: \.self) { prompt in Button(prompt) { question = prompt; send() }.buttonStyle(.bordered).disabled(busy || sources.isEmpty) } }.padding(.horizontal)
            }
            HStack {
                TextField("Chiedi sulle fonti…", text: $question, axis: .vertical).lineLimit(1...4)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(busy || question.isEmpty || sources.isEmpty).accessibilityLabel("Invia alla Lente AI")
                if busy { Button("Stop") { job?.cancel() } }
            }.padding()
        }.task(id: model.lensRequest) { await load() }
            .onDisappear { job?.cancel() }
    }
    private var settings: some View {
        Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }
            .popover(isPresented: $configuring) {
                NavigationStack {
                    Form {
                        Toggle("Usa il backend AI", isOn: $remote)
                        TextField("Endpoint HTTPS", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Token del backend", text: $token)
                        Toggle("Consento l’invio delle fonti selezionate", isOn: $consent)
                        Text("Le chiavi del provider restano sul server. Senza connessione resta disponibile l’estrazione offline.").font(.caption)
                        Button("Aggiorna selezione") { Task { await loadSources() } }
                    }.navigationTitle("Connessione AI")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { configuring = false } } }
                }.frame(width: 340, height: 420)
            }
    }
    private func load() async {
        job?.cancel()
        token = BackendCredentials.load()
        turns = (try? await model.workspace.catalog().conversation) ?? []
        await loadSources()
    }
    private func loadSources() async {
        guard await model.flush(), let page = model.page else { return }
        do {
            var text = page.texts.filter { model.selectedIDs.isEmpty || model.selectedIDs.contains($0.id) }.map(\.text).joined(separator: "\n")
            let area = model.lensArea ?? (model.selectionIncludesInk ? model.selectionBounds : nil)
            if let area, !area.isNull, area.width > 3, area.height > 3 {
                let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 1600)
                let box = area.intersection(CGRect(x: 0, y: 0, width: page.width, height: page.height))
                let pixel = CGRect(x: box.minX * image.scale, y: box.minY * image.scale, width: box.width * image.scale, height: box.height * image.scale)
                if let cropped = image.cgImage?.cropping(to: pixel), let data = UIImage(cgImage: cropped).pngData() {
                    text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n")
                }
            } else if model.selectedIDs.isEmpty {
                text += "\n" + page.recognizedText
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 1600)
                    if let data = image.pngData() { text = try await VisionOCRService().recognize(image: data).map(\.text).joined(separator: "\n") }
                }
            }
            sources = text.split(separator: "\n").prefix(20).map { IndexedChunk(text: String($0.prefix(4000)), reference: SourceReference(documentID: notebook.documentID, pageID: page.id, pageRevision: page.revision)) }
            if sources.isEmpty { error = "Nessun testo riconoscibile nella selezione. Seleziona testo o un’area più leggibile." } else { error = nil }
        } catch { self.error = error.localizedDescription }
    }
    private func send() {
        guard !busy, !sources.isEmpty else { return }
        let prompt = String(question.prefix(1000)); question = ""; error = nil; partial = ""; busy = true
        job = Task {
            defer { busy = false; partial = "" }
            do {
                let context = turns.suffix(2).map { "Domanda: \($0.question.prefix(300))\nRisposta precedente: \($0.answer.text.prefix(500))" }.joined(separator: "\n")
                let request = AIRequest(task: .chat, question: "\(context)\nDomanda attuale: \(prompt)", sources: sources)
                let answer: AIArtifact
                if remote {
                    guard consent, let url = URL(string: endpoint) else { throw AIConnectionFailure.configuration }
                    try BackendCredentials.save(token)
                    answer = try await RemoteAIProvider(endpoint: url, sessionToken: token).generateStreaming(request) { partial += $0 }
                } else { answer = try await ExtractiveStudyProvider().generate(request) }
                try Task.checkCancellation()
                let turn = AIConversationTurn(question: prompt, answer: answer)
                try await model.workspace.saveConversationTurn(turn); turns = Array((turns + [turn]).suffix(20))
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; question = prompt }
        }
    }
    private func insert(_ artifact: AIArtifact) {
        var text = TextElement(text: artifact.text); text.fontSize = 18
        model.mutatePage("Inserisci risposta AI") { $0.texts.append(text) }
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
