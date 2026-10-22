import SwiftUI
import NeuralNotesCore

@MainActor
struct AIConnectionPanel: View {
    @Binding var configuration: AIEngineConfiguration
    @Binding var consentKey: String?
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AIEngineConfiguration()
    @State private var credential = ""
    @State private var consent = false
    @State private var error: String?
    @State private var saving = false
    /// False while this build has no online NeuralNotes service and no signed-in account.
    @State private var serviceReady = true
    @State private var testing = false
    @State private var testResult: String?
    @State private var testPassed = false
    var body: some View {
        NavigationStack {
            Form {
                if serviceReady { accountSection } else { quickStartSection }
                engineSection
                consentSection
                if !serviceReady { accountSection }
                Section("Account ChatGPT") {
                    Text("Sign in with ChatGPT richiede una registrazione dell’integrazione. Non ancora configurato per questa app; resta disponibile la connessione API personale.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving).navigationTitle("Connessione AI")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { Task { await save() } }.disabled(saving) }
                }
                .task {
                    draft = configuration; credential = EngineCredentials.load(draft.engine); consent = consentKey == draft.consentKey
                    let account = await ManagedAIAccount.client.snapshot()
                    serviceReady = ManagedAIAccount.bundledStudyURL != nil || account != nil
                }
                .onChange(of: draft.engine) { _, engine in credential = EngineCredentials.load(engine); consent = false; testResult = nil }
                .onChange(of: draft.model) { _, _ in consent = false; testResult = nil }
                .onChange(of: draft.endpoint) { _, _ in consent = false; testResult = nil }
                .onChange(of: draft.workspaceID) { _, _ in consent = false }
                .onChange(of: credential) { _, _ in testResult = nil }
        }
    }
    private var quickStartSection: some View {
        Section("Prova subito con la tua chiave") {
            Text("L’accesso con account NeuralNotes non è ancora attivo in questa versione: per usare le funzioni AI basta una chiave API personale. Nessun login richiesto.").font(.caption)
            Button("Usa DeepSeek (deepseek-flash, il più economico)", systemImage: "bolt.fill") { draft.engine = .deepSeek; draft.model = "deepseek-flash" }
                .disabled(draft.engine == .deepSeek).accessibilityIdentifier("quickStartDeepSeek")
            Text("1. Crea la chiave su platform.deepseek.com. 2. Incollala in «Chiave API personale» qui sotto. 3. Premi «Prova la connessione». 4. Attiva il consenso e premi Salva.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var accountSection: some View {
        Section("NeuralNotes AI · account") {
            NavigationLink {
                ManagedAIAccountPanel(initial: draft) { value in draft = value; credential = ""; consent = false }
            } label: { Label("Accedi o gestisci account", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("managedAIAccount")
            Text(serviceReady ? "Collega l’account per usare i modelli del servizio senza inserire chiavi API. Le connessioni personali restano facoltative."
                 : "Disponibile dopo l’attivazione del servizio online. Per provare ora usa la chiave personale qui sopra.").font(.caption)
        }
    }
    private var engineSection: some View {
        Section("Motore") {
            Picker("Elaborazione", selection: $draft.engine) { ForEach(AIEngine.allCases, id: \.self) { Text($0.title).tag($0) } }
            if draft.engine == .offline {
                Text("Estrazione delle fonti sul dispositivo. Nessun modello generativo e nessun invio.").font(.caption)
            } else {
                if draft.engine == .backend || draft.engine == .compatibleResponses {
                    TextField("URL HTTPS completo della richiesta", text: $draft.endpoint).keyboardType(.URL)
                }
                if draft.engine != .backend { TextField("Identificativo del modello", text: $draft.model) }
                if draft.engine == .deepSeek {
                    Text("Modello consigliato: deepseek-flash (veloce ed economico); deepseek-v4-pro per risposte più accurate. Chiave da platform.deepseek.com.").font(.caption)
                    if draft.model.isEmpty { Button("Usa deepseek-flash") { draft.model = "deepseek-flash" }.font(.caption) }
                }
                if draft.engine == .anthropic { TextField("Workspace ID (se richiesto dalla chiave)", text: $draft.workspaceID) }
                if draft.engine == .backend && credential.isEmpty {
                    Text("Per il servizio gestito usa Accedi o gestisci account. Per un backend personale puoi inserire un token qui sotto.").font(.caption)
                }
                SecureField(draft.engine == .backend ? "Token personale (non serve con account)" : "Chiave API personale", text: $credential)
                if draft.engine != .backend {
                    Button(testing ? "Prova in corso…" : "Prova la connessione", systemImage: "checkmark.seal") { Task { await testConnection() } }
                        .disabled(testing || credential.isEmpty || draft.model.trimmingCharacters(in: .whitespaces).isEmpty || draft.url == nil)
                    if let testResult { Text(testResult).font(.caption).foregroundStyle(testPassed ? Color.green : Color.red).textSelection(.enabled) }
                }
                Text("Destinazione: \(draft.destination)").font(.caption).textSelection(.enabled)
                Text("Le chiavi sono conservate nel portachiavi di questo dispositivo. Le API personali possono avere costi sul tuo account; il modello deve supportare risposte JSON strutturate.").font(.caption)
            }
        }.textInputAutocapitalization(.never).autocorrectionDisabled()
            // DeepSeek's fastest and cheapest model is the default; the student can still change it.
            .onChange(of: draft.engine) { _, engine in if engine == .deepSeek && draft.model.isEmpty { draft.model = "deepseek-flash" } }
    }
    @ViewBuilder
    private var consentSection: some View {
        if draft.engine != .offline {
            Section("Fonti di questo quaderno") {
                Toggle("Consento l’invio al motore indicato", isOn: $consent)
                Text("Necessario per usare la Lente, la sbobina e le flashcard con l’AI. Le fonti vengono inviate solo quando avvii un’azione AI; cambiare motore o destinazione richiede un nuovo consenso.").font(.caption)
            }
        }
    }
    /// A tiny synthetic request: it checks key, model and response format without sending notes.
    private func testConnection() async {
        guard !testing else { return }; testing = true; defer { testing = false }
        let source = IndexedChunk(text: "Questo è un controllo del collegamento di NeuralNotes.", reference: SourceReference(documentID: UUID()))
        let request = AIRequest(task: .chat, question: "Conferma in una frase che il collegamento funziona, citando la fonte.", sources: [source])
        do {
            let answer = try await DirectAIProvider(configuration: draft, credential: credential.trimmingCharacters(in: .whitespacesAndNewlines)).generate(request)
            testPassed = true; testResult = "Collegamento riuscito con \(answer.provider) · \(draft.model). Ora attiva il consenso e premi Salva."
        } catch {
            testPassed = false; testResult = "Collegamento non riuscito: \(error.localizedDescription)"
        }
    }
    private func save() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do {
            if draft.engine != .offline {
                guard draft.url != nil, draft.engine == .backend || !draft.model.isEmpty else { throw AIWireFailure.configuration }
                if await ManagedAIAccount.isManaged(draft) { _ = try await AIEngineRouter.cacheScope(draft) }
                else {
                    let key = credential.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { throw AIWireFailure.configuration }
                    try EngineCredentials.save(key, for: draft.engine)
                }
            }
            try await AIEngineRouter.rememberConsent(draft, allowed: consent)
            try AIEngineStore.save(draft)
            configuration = draft; consentKey = consent ? draft.consentKey : nil; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
