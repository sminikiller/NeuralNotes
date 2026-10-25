import SwiftUI
import NeuralNotesCore

private enum AccountServiceSheet: String, Identifiable {
    case account, cloud, ai, privacy
    var id: String { rawValue }
}

@MainActor
struct AccountServicesPanel: View {
    let library: LibraryViewModel
    @Bindable private var cloud = CloudBackupService.shared
    @Bindable private var iCloud = CloudNotebookSync.shared
    @State private var account: ManagedAISession?
    @State private var configuration = AIEngineStore.load()
    @State private var consent: String?
    @State private var sheet: AccountServiceSheet?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    serviceButton("Account NeuralNotes", detail: account?.email ?? (account == nil ? "Accesso non effettuato" : "Collegato"), icon: "person.crop.circle", target: .account)
                }
                Section("I tuoi quaderni") {
                    serviceButton("Centro sincronizzazione", detail: cloudDetail, icon: "arrow.triangle.2.circlepath.icloud", target: .cloud)
                    serviceButton("iCloud", detail: iCloud.status, icon: "icloud", target: .cloud)
                }
                Section("Intelligenza artificiale") {
                    serviceButton("Motore AI", detail: configuration.engine == .offline ? "Sintesi locale · offline" : "\(configuration.engine.title) · configura e prova la connessione", icon: "sparkles", target: .ai)
                }
                Section("Informazioni") {
                    serviceButton("Privacy e assistenza", detail: "Dati locali, servizi online e contatti", icon: "hand.raised", target: .privacy)
                }
            }.navigationTitle("Account e servizi")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }.task { await refresh() }
            .sheet(item: $sheet, onDismiss: { Task { await refresh() } }) { selected in
                switch selected {
                case .account:
                    NavigationStack {
                        ManagedAIAccountPanel(initial: configuration, connected: { value in configuration = value }, offersAIConfiguration: false)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { sheet = nil } } }
                    }
                case .cloud: CloudSyncPanel(library: library)
                case .ai: AIConnectionPanel(configuration: $configuration, consentKey: $consent)
                case .privacy: PrivacyAndSupportPanel()
                }
            }
    }
    private var cloudDetail: String {
        if !cloud.accountConnected { return "Accedi per collegare il cloud" }
        return "\(cloud.queue.jobs.count) in coda · \(cloud.conflicts.count) conflitti"
    }
    private func serviceButton(_ title: String, detail: String, icon: String, target: AccountServiceSheet) -> some View {
        Button { sheet = target } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 30).foregroundStyle(Brand.accent)
                VStack(alignment: .leading, spacing: 4) { Text(title).foregroundStyle(.primary); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 6)
        }.accessibilityIdentifier("services-\(target.rawValue)")
    }
    private func refresh() async {
        account = await ManagedAIAccount.client.snapshot(); configuration = AIEngineStore.load()
        consent = await AIEngineRouter.restoredConsent(configuration)
        await cloud.prepareAccount()
        if cloud.accountConnected { await cloud.refresh() }
    }
}

@MainActor
private struct PrivacyAndSupportPanel: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Sul tuo iPad") {
                    Text("Puoi scrivere e gestire i quaderni senza un account. I file locali restano sull’iPad; esporta un backup nativo prima di cambiare installazione.")
                }
                Section("Account e cloud") {
                    Text("L’accesso email utilizza un codice. Se colleghi un quaderno al cloud, il servizio conserva il profilo, i file inviati e le relative versioni. I quaderni possono contenere testo, immagini e registrazioni.")
                    Text("Da Account NeuralNotes puoi esportare i dati dell’account o richiederne la cancellazione. Le copie locali e quelle nel tuo account Apple si gestiscono separatamente.")
                }
                Section("Intelligenza artificiale") {
                    Text("Le funzioni AI online inviano al servizio il contenuto scelto per la richiesta. Le risposte possono contenere errori: controlla le fonti prima di usarle. La sintesi locale funziona senza un provider online.")
                }
                Section("Privacy e contatti") {
                    if let privacy = publicLink("NeuralNotesPrivacyURL") {
                        Link("Leggi l’informativa completa", destination: privacy).accessibilityIdentifier("privacyPolicyLink")
                    } else {
                        Text("L’informativa pubblica dei servizi online non è ancora configurata in questa build di collaudo.").foregroundStyle(.secondary)
                    }
                    if let support = publicLink("NeuralNotesSupportURL") {
                        Link("Apri assistenza", destination: support).accessibilityIdentifier("supportLink")
                    }
                }
            }.navigationTitle("Privacy e assistenza")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
    private func publicLink(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
