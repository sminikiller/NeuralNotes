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
    var body: some View {
        NavigationStack {
            Form {
                Section("Motore") {
                    Picker("Elaborazione", selection: $draft.engine) { ForEach(AIEngine.allCases, id: \.self) { Text($0.title).tag($0) } }
                    if draft.engine == .offline {
                        Text("Estrazione delle fonti sul dispositivo. Nessun modello generativo e nessun invio.").font(.caption)
                    } else {
                        if draft.engine == .backend || draft.engine == .compatibleResponses {
                            TextField("URL HTTPS completo della richiesta", text: $draft.endpoint).keyboardType(.URL)
                        }
                        if draft.engine != .backend { TextField("Identificativo del modello", text: $draft.model) }
                        if draft.engine == .anthropic { TextField("Workspace ID (se richiesto dalla chiave)", text: $draft.workspaceID) }
                        SecureField(draft.engine == .backend ? "Token del backend" : "Chiave API personale", text: $credential)
                        Text("Destinazione: \(draft.destination)").font(.caption).textSelection(.enabled)
                        Text("Le chiavi sono conservate nel portachiavi di questo dispositivo. Le API personali possono avere costi sul tuo account; il modello deve supportare risposte JSON strutturate.").font(.caption)
                    }
                }.textInputAutocapitalization(.never).autocorrectionDisabled()
                if draft.engine != .offline {
                    Section("Fonti di questo quaderno") {
                        Toggle("Consento l’invio al motore indicato", isOn: $consent)
                        Text("Il consenso vale finché questo pannello di studio resta aperto e cambia se cambi motore, modello o destinazione. Nessuna richiesta parte salvando le impostazioni.").font(.caption)
                    }
                }
                Section("Account ChatGPT") {
                    Text("Sign in with ChatGPT richiede una registrazione dell’integrazione. Non ancora configurato per questa app; resta disponibile la connessione API personale.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Connessione AI")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() } }
                }
                .task { draft = configuration; credential = EngineCredentials.load(draft.engine); consent = consentKey == draft.consentKey }
                .onChange(of: draft.engine) { _, engine in credential = EngineCredentials.load(engine); consent = false }
                .onChange(of: draft.model) { _, _ in consent = false }
                .onChange(of: draft.endpoint) { _, _ in consent = false }
                .onChange(of: draft.workspaceID) { _, _ in consent = false }
        }
    }
    private func save() {
        do {
            if draft.engine != .offline {
                guard draft.url != nil, !credential.isEmpty, draft.engine == .backend || !draft.model.isEmpty else { throw AIWireFailure.configuration }
                try EngineCredentials.save(credential, for: draft.engine)
            }
            try AIEngineStore.save(draft)
            configuration = draft; consentKey = consent ? draft.consentKey : nil; dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
