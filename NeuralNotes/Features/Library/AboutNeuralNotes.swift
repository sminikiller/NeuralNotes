import SwiftUI
import StoreKit
import NeuralNotesCore
import Darwin

@MainActor
struct AboutNeuralNotes: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingGuide = false
    @State private var channel: String?
    @State private var copied = false
    private var information: AppInformation {
        var value = utsname(); uname(&value)
        let machine = withUnsafeBytes(of: &value.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return AppInformation(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            system: UIDevice.current.systemVersion, device: "\(UIDevice.current.model) (\(machine))")
    }
    private var email: String? { AppInformation.feedbackEmail(Bundle.main.object(forInfoDictionaryKey: "NeuralNotesFeedbackEmail") as? String) }
    var body: some View {
        NavigationStack {
            List {
                Section { header }
                Section("Versione installata") {
                    Text(information.versionLabel).accessibilityIdentifier("aboutVersion")
                        .accessibilityValue(colorScheme == .dark ? "Tema scuro" : "Tema chiaro")
                    if let channel { Label(channel, systemImage: "checkmark.seal") }
                    Button(copied ? "Informazioni copiate" : "Copia informazioni", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = information.diagnosticText; copied = true
                    }.accessibilityIdentifier("aboutCopyInformation")
                }
                Section("Sviluppo") { Text("Sviluppata da **Lorenzo Minichilli**") }
                Section("Ringraziamenti") {
                    Text("Grazie agli amici e ai compagni che hanno provato le versioni di prova e segnalato problemi e idee.")
                    ForEach(credits, id: \.self) { Text($0) }
                }
                feedback
                Section("Collegamenti") {
                    publicRow("Assistenza", key: "NeuralNotesSupportURL", icon: "lifepreserver")
                    publicRow("Informativa privacy", key: "NeuralNotesPrivacyURL", icon: "hand.raised")
                    Button("Guida e Novità", systemImage: "questionmark.circle") { showingGuide = true }
                }
                Section("Privacy in breve") {
                    Text("I quaderni si salvano sul dispositivo. Le copie esportate e gli eventuali backup in File o iCloud Drive si gestiscono separatamente.")
                    Text("Quando usi un motore AI online, il contenuto scelto per la richiesta viene inviato al servizio configurato. La sintesi locale funziona senza un provider online.")
                    Text("Accesso email e sincronizzazione inviano i dati necessari al servizio scelto solo quando li utilizzi. Le registrazioni e le foto possono far parte dei quaderni inviati al cloud. La disponibilità di iCloud dipende dalla build installata.")
                }
                Section("Licenze") {
                    NavigationLink("Componenti di terze parti") { ThirdPartyNoticesView() }
                }
                Section { footer }
            }
            .navigationTitle("Informazioni su NeuralNotes")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("aboutNeuralNotes")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
        .sheet(isPresented: $showingGuide) { QuickGuidePanel() }
        .task { await detectChannel() }
    }
    private var header: some View {
        VStack(spacing: 14) {
            Image("AppLogo", bundle: appResourceBundle).resizable().scaledToFit().frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityHidden(true)
            Text("NeuralNotes").font(.largeTitle.bold())
            Text("Scrivi, studia, collega e riorganizza le tue idee.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 20)
    }
    @ViewBuilder private var feedback: some View {
        if let email {
            Section("Contatti e feedback") {
                Button("Invia un feedback", systemImage: "bubble.left.and.text.bubble.right") { send(email, problem: false) }
                Button("Segnala un problema", systemImage: "exclamationmark.bubble") { send(email, problem: true) }
                if channel == "Beta TestFlight" { Text("In TestFlight puoi anche fare uno screenshot e toccare Condividi feedback.").font(.caption).foregroundStyle(.secondary) }
            }
        } else if channel == "Beta TestFlight" {
            Section("Feedback") { Text("In TestFlight puoi anche fare uno screenshot e toccare Condividi feedback.") }
        }
    }
    private func publicRow(_ title: String, key: String, icon: String) -> some View {
        Group {
            if let url = AppInformation.publicLink(Bundle.main.object(forInfoDictionaryKey: key) as? String) {
                Link(destination: url) { Label(title, systemImage: icon) }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(title, systemImage: icon)
                    Text("Non ancora pubblicata in questa versione").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("© 2026 Lorenzo Minichilli")
            Text("Sviluppata anche grazie al supporto di ChatGPT e Claude.")
            Text("I marchi citati appartengono ai rispettivi proprietari.")
        }.font(.footnote).foregroundStyle(.secondary).padding(.vertical, 4)
    }
    private var credits: [String] {
        let data = appResourceBundle.url(forResource: "Credits", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        return AppInformation.credits(data)
    }
    private func send(_ email: String, problem: Bool) {
        if let url = information.mailURL(email: email, problem: problem) { openURL(url) }
    }
    private func detectChannel() async {
        #if SWIFT_PACKAGE
        channel = "Swift Playgrounds"
        #else
        // Require both the sandbox receipt and a verified StoreKit transaction.
        // Xcode builds and indeterminate installations show no beta label.
        #if !DEBUG
        if let result = try? await AppTransaction.shared, case .verified(let transaction) = result,
           transaction.environment == .sandbox,
           Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" { channel = "Beta TestFlight" }
        #endif
        #endif
    }
}

var appResourceBundle: Bundle {
    #if SWIFT_PACKAGE
    return .module
    #else
    return .main
    #endif
}

private struct ThirdPartyNoticesView: View {
    private var notices: String {
        guard let url = appResourceBundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Licenze non disponibili." }
        return text
    }
    var body: some View {
        ScrollView { Text(notices).font(.footnote).textSelection(.enabled).padding().frame(maxWidth: .infinity, alignment: .leading) }
            .navigationTitle("Licenze")
    }
}
