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
    var body: some View {
        NavigationStack {
            Form {
                accountSection
                engineSection
                consentSection
                Section("Account ChatGPT") {
                    Text("Sign in with ChatGPT richiede una registrazione dell’integrazione. Non ancora configurato per questa app; resta disponibile la connessione API personale.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.disabled(saving).navigationTitle("Connessione AI")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { Task { await save() } }.disabled(saving) }
                }
                .task { draft = configuration; credential = EngineCredentials.load(draft.engine); consent = consentKey == draft.consentKey }
                .onChange(of: draft.engine) { _, engine in credential = EngineCredentials.load(engine); consent = false }
                .onChange(of: draft.model) { _, _ in consent = false }
                .onChange(of: draft.endpoint) { _, _ in consent = false }
                .onChange(of: draft.workspaceID) { _, _ in consent = false }
        }
    }
    private var accountSection: some View {
        Section("NeuralNotes AI") {
            NavigationLink {
                ManagedAIAccountPanel(initial: draft) { value in draft = value; credential = ""; consent = false }
            } label: { Label("Accedi o gestisci account", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("managedAIAccount")
            Text("Collega l’account per usare i modelli del servizio senza inserire chiavi API. Le connessioni personali sotto restano facoltative.").font(.caption)
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
                Text("Destinazione: \(draft.destination)").font(.caption).textSelection(.enabled)
                Text("Le chiavi sono conservate nel portachiavi di questo dispositivo. Le API personali possono avere costi sul tuo account; il modello deve supportare risposte JSON strutturate.").font(.caption)
            }
        }.textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    @ViewBuilder
    private var consentSection: some View {
        if draft.engine != .offline {
            Section("Fonti di questo quaderno") {
                Toggle("Consento l’invio al motore indicato", isOn: $consent)
                Text("Per l’account NeuralNotes la scelta viene ricordata per questo account e servizio. Le fonti vengono inviate solo quando avvii un’azione AI; cambiare destinazione richiede un nuovo consenso.").font(.caption)
            }
        }
    }
    private func save() async {
        guard !saving else { return }; saving = true; defer { saving = false }
        do {
            if draft.engine != .offline {
                guard draft.url != nil, draft.engine == .backend || !draft.model.isEmpty else { throw AIWireFailure.configuration }
                if await ManagedAIAccount.isManaged(draft) { _ = try await AIEngineRouter.cacheScope(draft) }
                else {
                    guard !credential.isEmpty else { throw AIWireFailure.configuration }
                    try EngineCredentials.save(credential, for: draft.engine)
                }
            }
            try await AIEngineRouter.rememberConsent(draft, allowed: consent)
            try AIEngineStore.save(draft)
            configuration = draft; consentKey = consent ? draft.consentKey : nil; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
