import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import NeuralNotesCore

@MainActor
struct ManagedAIAccountPanel: View {
    let initial: AIEngineConfiguration
    let connected: (AIEngineConfiguration) -> Void
    var offersAIConfiguration = true
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var account: ManagedAISession?
    @State private var overview: ManagedAccountOverview?
    @State private var busy = false
    @State private var error: String?
    @State private var job: Task<Void, Never>?
    @State private var displayName = ""
    @State private var notice: String?
    @State private var deleteCode = ""
    @State private var deleteCodeSent = false
    @State private var deleteSentAt: Date?
    @State private var confirmDeletion = false
    @State private var exported: AccountExport?
    @AppStorage("account.apple.subject") private var appleSubject = ""
    @State private var appleAuthorized = false
    @State private var appleNonce: String?
    var body: some View {
        Form {
            Section {
                Label("Account NeuralNotes", systemImage: "person.crop.circle").font(.headline)
                Text("Collega i servizi con il tuo Account Apple. Modelli e chiavi sono gestiti dal servizio. I contenuti vengono inviati quando usi l’AI online o colleghi un quaderno al cloud.").font(.caption)
            }
            if let account {
                Section("Account") {
                    Label(account.email ?? "Account collegato", systemImage: "person.crop.circle.badge.checkmark")
                    if offersAIConfiguration { Button("Usa questo account per l’AI") { use(account) }.accessibilityIdentifier("managedAIUseAccount") }
                    Button("Esci da questo dispositivo", role: .destructive) { signOut() }
                }
                profileAndData
                deletion
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
            } else {
                if appleAuthorized {
                    Label("Account Apple collegato", systemImage: "person.crop.circle.badge.checkmark")
                    Button("Esci da questo dispositivo") { appleSubject = ""; appleAuthorized = false }
                }
                if Bundle.main.object(forInfoDictionaryKey: "NNAppleLoginSigned") as? Bool == true,
                   !appleAuthorized || ManagedAIAccount.bundledStudyURL != nil {
                    Section("Account Apple") {
                        SignInWithAppleButton(.signIn) { request in
                            let nonce = UUID().uuidString + UUID().uuidString
                            appleNonce = nonce
                            request.requestedScopes = [.email]
                            request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
                        } onCompletion: { result in finishAppleLogin(result, service: ManagedAIAccount.bundledStudyURL) }
                        .frame(height: 46).disabled(busy)
                    }
                }
            }
            if endpoint.isEmpty {
                Section { Text("Il servizio online non è ancora attivato in questo pacchetto. La scrittura e le funzioni locali sono disponibili.").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("managedAINotConfigured") }
            }
            if ManagedAIAccount.bundledStudyURL == nil { DisclosureGroup("Configurazione del servizio · avanzate") {
                TextField("URL HTTPS /v1/study", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(busy || account != nil)
                Text("Nella versione distribuita l’indirizzo viene impostato dallo sviluppatore. Nessuna chiave del provider va inserita qui.").font(.caption)
            } }
            if busy { ProgressView("Connessione…") }
            if let notice { Text(notice).font(.callout).textSelection(.enabled) }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Account NeuralNotes")
            .task {
                await refreshAppleCredential()
                account = await ManagedAIAccount.client.snapshot()
                endpoint = account?.service.studyURL.absoluteString ?? ManagedAIAccount.bundledStudyURL?.absoluteString ?? (initial.engine == .backend ? initial.endpoint : "")
                if account != nil { overview = try? await ManagedAIAccount.overview(); displayName = overview?.displayName ?? "" }
            }
            .onReceive(NotificationCenter.default.publisher(for: ASAuthorizationAppleIDProvider.credentialRevokedNotification)) { _ in
                Task { await refreshAppleCredential() }
            }
            .interactiveDismissDisabled(busy)
            .sheet(item: $exported, onDismiss: { if let file = exportedFile { try? FileManager.default.removeItem(at: file) }; exportedFile = nil }) { item in AccountExportShare(url: item.url) }
            .confirmationDialog("Eliminare definitivamente l’account NeuralNotes?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Elimina account e copie online", role: .destructive) { deleteAccount() }
                Button("Annulla", role: .cancel) { }
            } message: { Text("Il profilo, le registrazioni caricate e i materiali che hai pubblicato saranno rimossi dal servizio. I quaderni e gli audio salvati sull’iPad restano disponibili. Le copie iCloud appartengono al tuo account Apple e non vengono eliminate qui.") }
            .onDisappear { job?.cancel() }
    }
    @State private var exportedFile: URL?
    private var profileAndData: some View {
        Section("Profilo e dati") {
            TextField("Nome visualizzato", text: $displayName).textContentType(.nickname).disabled(busy)
                .accessibilityIdentifier("managedAccountName")
            Button("Salva nome") { saveProfile() }.disabled(busy || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName.count > 80)
            Button("Esporta dati dell’account", systemImage: "square.and.arrow.up") { exportAccount() }.disabled(busy)
            Text("Esporta profilo, consumi, elenco delle copie cloud e dei materiali condivisi in JSON. I file di appunti e audio si esportano dalla libreria.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var deletion: some View {
        Section {
            DisclosureGroup("Elimina account…") {
                Text("Operazione definitiva per i dati online di NeuralNotes. I quaderni locali restano sull’iPad. Conferma con un nuovo codice email.").font(.caption)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(ceil(60 - context.date.timeIntervalSince(deleteSentAt ?? .distantPast))))
                    Button(remaining > 0 ? "Nuovo codice fra \(remaining) s" : "Invia codice di conferma") { sendDeletionCode() }
                        .disabled(busy || account?.email == nil || remaining > 0)
                }
                if deleteCodeSent {
                    TextField("Codice di conferma", text: $deleteCode).textContentType(.oneTimeCode).keyboardType(.numberPad).disabled(busy)
                    Button("Verifica codice ed elimina…", role: .destructive) { confirmDeletion = true }.disabled(busy || deleteCode.count < 6)
                }
            }
        }
    }
    private func saveProfile() {
        guard !busy, let owner = account else { return }; busy = true; error = nil; notice = nil
        job = Task {
            defer { busy = false }
            do { try await ManagedAIAccount.updateProfile(displayName, owner: owner); overview = try await ManagedAIAccount.overview(); notice = "Nome aggiornato." }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func exportAccount() {
        guard !busy else { return }; busy = true; error = nil; notice = nil
        job = Task {
            defer { busy = false }
            do {
                let file = try await ManagedAIAccount.exportMetadata()
                if Task.isCancelled { try? FileManager.default.removeItem(at: file); return }
                exportedFile = file; exported = AccountExport(url: file)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func sendDeletionCode() {
        guard !busy, let email = account?.email else { return }; busy = true; error = nil; notice = nil
        job = Task {
            defer { busy = false }
            do { try await ManagedAIAccount.client.requestCode(email: email); deleteCodeSent = true; deleteSentAt = Date(); deleteCode = "" }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    private func deleteAccount() {
        guard !busy, let owner = account, let email = owner.email else { return }; busy = true; error = nil; notice = nil
        let value = deleteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        job = Task {
            defer { busy = false }
            do {
                let verified = try await ManagedAIAccount.client.verify(email: email, code: value)
                guard verified.userID == owner.userID, verified.service == owner.service else { throw ManagedAIFailure.signedOut }
                account = verified; deleteCode = ""
                for _ in 0..<100 {
                    try Task.checkCancellation(); notice = "Rimozione delle copie online in corso…"
                    if try await ManagedAIAccount.deleteAccount(owner: owner) {
                        account = nil; overview = nil; deleteCodeSent = false
                        notice = "Account eliminato. I quaderni locali sono conservati."; return
                    }
                }
                notice = "Rimozione ancora in corso. Richiedi un nuovo codice per riprenderla; gli appunti locali sono conservati."
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; notice = "Se la rimozione era già iniziata, richiedi un nuovo codice per riprenderla."; deleteCodeSent = false }
        }
    }
    private func refreshAppleCredential() async {
        let subject = appleSubject
        guard !subject.isEmpty else { appleAuthorized = false; return }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: subject)
            guard appleSubject == subject else { return }
            appleAuthorized = state == .authorized
            if state == .revoked || state == .notFound {
                appleSubject = ""
                try await ManagedAIAccount.client.signOut()
                account = nil; overview = nil; CloudBackupService.shared.accountDidChange()
            }
        } catch { appleAuthorized = false }
    }
    private func finishAppleLogin(_ result: Result<ASAuthorization, Error>, service: URL?) {
        let nonce = appleNonce
        appleNonce = nil
        do {
            let authorization = try result.get()
            guard !busy, let nonce, let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let bytes = credential.identityToken, let token = String(data: bytes, encoding: .utf8) else { throw ManagedAIFailure.response }
            appleSubject = credential.user; appleAuthorized = true
            guard let service else { return }
            busy = true; error = nil
            job = Task {
                defer { busy = false }
                do {
                    _ = try await ManagedAIAccount.client.connect(studyURL: service)
                    try Task.checkCancellation()
                    account = try await ManagedAIAccount.client.verifyApple(identityToken: token, nonce: nonce, studyURL: service)
                    CloudBackupService.shared.accountDidChange()
                    overview = try? await ManagedAIAccount.overview()
                    displayName = overview?.displayName ?? ""
                } catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
        } catch let failure as ASAuthorizationError where failure.code == .canceled { }
        catch { self.error = error.localizedDescription }
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
            do { try await ManagedAIAccount.client.signOut(); appleSubject = ""; appleAuthorized = false; account = nil; overview = nil; CloudBackupService.shared.accountDidChange() }
            catch { account = await ManagedAIAccount.client.snapshot(); self.error = error.localizedDescription }
        }
    }
}


private struct AccountExport: Identifiable { let id = UUID(); let url: URL }
@MainActor private struct AccountExportShare: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
