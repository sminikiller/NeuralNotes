import SwiftUI
import NeuralNotesCore

/// Shown while the Lens tool is active: how it works now and the few choices it needs.
@MainActor
struct LensModeBar: View {
    let model: EditorViewModel
    let openChat: () -> Void
    let photo: () -> Void
    @AppStorage(LensSettings.modeKey) private var mode = LensMode.text.rawValue
    @AppStorage(LensSettings.autoNoteKey) private var autoNote = true
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.headline).labelStyle(.titleAndIcon)
                Picker("Modo", selection: $mode) {
                    Text("Testo").tag(LensMode.text.rawValue)
                    Text("Immagine").tag(LensMode.image.rawValue)
                }.pickerStyle(.segmented).frame(width: 190).accessibilityIdentifier("lensMode")
                Toggle(isOn: $autoNote) { Label("Nota automatica", systemImage: "note.text.badge.plus") }
                    .toggleStyle(.button).disabled(mode == LensMode.image.rawValue).accessibilityIdentifier("lensAutoNote")
                Button(action: photo) { Label("Foto e chiedi", systemImage: "camera") }.accessibilityIdentifier("lensPhoto")
                Button(action: openChat) { Label("Chat pagina", systemImage: "bubble.left.and.text.bubble.right") }.accessibilityIdentifier("lensOpenChat")
                Button { configuring = true } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Connessione AI").accessibilityIdentifier("lensSettings")
                Button { model.chooseTool(.pen) } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(.secondary).accessibilityLabel("Esci dalla Lente").accessibilityIdentifier("lensExit")
            }.labelStyle(.iconOnly).font(.body)
            Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if configuration.engine == .offline || consentKey != configuration.consentKey {
                Button(configuration.engine == .offline ? "Collega un motore AI per usare la Lente" : "Consenti l’invio a \(configuration.engine.title)") { configuring = true }
                    .font(.caption.bold())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).shadow(radius: 6)
        .frame(maxWidth: 760)
        .task { await refresh() }
        .sheet(isPresented: $configuring, onDismiss: { Task { await refresh() } }) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
    }

    private var hint: String {
        if mode == LensMode.image.rawValue { return "Tocca una foto o cerchia una zona: l’AI guarda l’immagine e risponde. Con «Foto e chiedi» scatti e chiedi subito." }
        return autoNote
            ? "Sottolinea un nome, una data o un termine: compare una nota con la spiegazione. Tocca una parola per spiegarla; cerchia o trascina un rettangolo per chiedere."
            : "Sottolinea, cerchia o trascina: si apre la scheda con spiegazione, riassunto, traduzione e domande."
    }

    private func refresh() async {
        configuration = AIEngineStore.load()
        consentKey = await AIEngineRouter.restoredConsent(configuration)
    }
}
