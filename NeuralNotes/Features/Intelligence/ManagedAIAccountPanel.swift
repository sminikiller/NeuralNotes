import SwiftUI
import NeuralNotesCore

@MainActor
struct ManagedAIAccountPanel: View {
    let initial: AIEngineConfiguration
    let connected: (AIEngineConfiguration) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var sentAt: Date?
    @State private var account: ManagedAISession?
    @State private var overview: ManagedAccountOverview?
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    var body: some View {
        Form {
            Section {
                Label("NeuralNotes AI", systemImage: "sparkles").font(.headline)
                Text("Accedi con un codice email. Modelli e chiavi sono gestiti dal servizio; gli appunti restano sul dispositivo finché scegli un’azione AI.").font(.caption)
            }
            if let account {
                Section("Account") {
                    Label(account.email ?? "Account collegato", systemImage: "person.crop.circle.badge.checkmark")
                    Button("Usa questo account per l’AI") { use(account) }.accessibilityIdentifier("managedAIUseAccount")
                    Button("Esci da questo dispositivo", role: .destructive) { signOut() }
                }
                Section("Piano e consumi") {
                    if let overview {
                        LabeledContent("Piano", value: overview.planTitle)
                        LabeledContent("Crediti AI oggi", value: "\(overview.usedToday) di \(overview.dailyLimit)")
                        LabeledContent("Crediti AI questo mese", value: "\(overview.usedThisMonth) di \(overview.monthlyLimit)")
                        LabeledContent("Spazio cloud", value: ByteCountFormatter.string(fromByteCount: overview.storageLimit, countStyle: .file))
                        Text(overview.remaining == 0 ? "Crediti esauriti per ora: le funzioni locali restano disponibili." : "Ancora \(overview.remaining) crediti disponibili. Una spiegazione usa almeno un credito, una ricerca web otto.").font(.caption).foregroundStyle(.secondary)
                    } else { Text("Consumi non ancora letti.").font(.caption).foregroundStyle(.secondary) }
                    Button("Aggiorna consumi", systemImage: "arrow.clockwise") { refreshOverview() }.disabled(busy)
                }
            } else { login }
            if endpoint.isEmpty {
                Section { Text("Il servizio online non è ancora attivato in questo pacchetto. La scrittura e le funzioni locali sono disponibili.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("managedAINotConfigured") }
            }
            DisclosureGroup("Configurazione del servizio · avanzate") {
                TextField("URL HTTPS /v1/study", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy || account != nil)
                Text("Nella versione distribuita l’indirizzo viene impostato dallo sviluppatore. Nessuna chiave del provider va inserita qui.").font(.caption)
            }
            if busy { ProgressView("Connessione…") }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Account NeuralNotes")
            .task {
                account = await ManagedAIAccount.client.snapshot()
                endpoint = account?.service.studyURL.absoluteString ?? ManagedAIAccount.bundledStudyURL?.absoluteString ?? (initial.engine == .backend ? initial.endpoint : "")
                if account != nil { overview = try? await ManagedAIAccount.overview() }
            }
            .onDisappear { job?.cancel() }
    }
    private var login: some View {
        Section("Accesso con email") {
            TextField("Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy)
                .accessibilityIdentifier("managedAIEmail")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(60 - context.date.timeIntervalSince(sentAt ?? .distantPast))))
                Button(sentTo == nil ? "Invia codice" : remaining > 0 ? "Nuovo codice fra \(remaining) s" : "Invia un nuovo codice") { sendCode() }
                    .disabled(busy || endpoint.isEmpty || remaining > 0).accessibilityIdentifier("managedAISendCode")
            }
            if let sentTo {
                Text("Se l’indirizzo è abilitato riceverai un codice su \(sentTo).").font(.caption)
                TextField("Codice email", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode).disabled(busy)
                    .accessibilityIdentifier("managedAICode")
                Button("Accedi") { verify() }.disabled(busy || code.isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines) != sentTo)
                    .accessibilityIdentifier("managedAIVerify")
            }
        }
    }
    private func sendCode() {
        guard let url = URL(string: endpoint), !busy else { return }; busy = true; error = nil
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        job = Task {
            defer { busy = false }
            do {
                _ = try await ManagedAIAccount.client.connect(studyURL: url)
                try await ManagedAIAccount.client.requestCode(email: address)
                try Task.checkCancellation(); sentTo = address; sentAt = Date(); code = ""
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func verify() {
        guard !busy, let address = sentTo else { return }; busy = true; error = nil
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines)
        job = Task {
            defer { busy = false }
            do { account = try await ManagedAIAccount.client.verify(email: address, code: value); code = "" }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func refreshOverview() {
        guard !busy else { return }; busy = true; error = nil
        job = Task {
            defer { busy = false }
            do { overview = try await ManagedAIAccount.overview() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func use(_ account: ManagedAISession) {
        var config = AIEngineConfiguration(); config.engine = .backend; config.endpoint = account.service.studyURL.absoluteString
        UserDefaults.standard.set(config.endpoint, forKey: "ai.managed.endpoint")
        connected(config); dismiss()
    }
    private func signOut() {
        guard !busy else { return }; busy = true; error = nil
        job = Task {
            defer { busy = false }
            do { try await ManagedAIAccount.client.signOut(); account = nil; sentTo = nil; code = "" }
            catch { account = await ManagedAIAccount.client.snapshot(); self.error = error.localizedDescription }
        }
    }
}
