import SwiftUI
import NeuralNotesCore

/// Lens commands that need the editor view: camera, photo library, notes and page chat.
struct LensBarActions {
    var photo: () -> Void = {}
    var library: () -> Void = {}
    var notes: () -> Void = {}
    var chat: () -> Void = {}
}

/// Shown under the toolbar while the Lens tool is active: one compact row, never
/// over the middle of the page. The short guide appears until it is dismissed and
/// comes back from the question mark.
@MainActor
struct LensModeBar: View {
    let model: EditorViewModel
    var actions = LensBarActions()
    @AppStorage(LensSettings.modeKey) private var mode = LensMode.text.rawValue
    @AppStorage(LensSettings.autoNoteKey) private var autoNote = true
    @AppStorage(LensSettings.hintKey) private var hintSeen = false
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    @State private var help = false

    private var ready: Bool { configuration.engine != .offline && consentKey == configuration.consentKey }
    private var notesCount: Int { model.page?.texts.filter { $0.lensNote != nil }.count ?? 0 }

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    modeControls
                    askControls
                    panelControls
                }.padding(.horizontal, 4)
            }
            .frame(maxWidth: 640, minHeight: 48, maxHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
            if !ready || !hintSeen || help { hintRow }
        }
        .task { await refresh() }
        .sheet(isPresented: $configuring, onDismiss: { Task { await refresh() } }) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
    }

    // Small parts keep each expression quick for the Swift Playgrounds type checker.
    private var modeControls: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Brand.accent).padding(.leading, 8).accessibilityHidden(true)
            Picker("Strumento della Lente", selection: $mode) {
                ForEach(LensMode.allCases, id: \.self) { item in Text(item.title).tag(item.rawValue) }
            }.pickerStyle(.segmented).frame(width: 240).accessibilityIdentifier("lensMode")
            Toggle(isOn: $autoNote) { Image(systemName: "note.text.badge.plus") }
                .toggleStyle(.button).disabled(mode != LensMode.text.rawValue)
                .accessibilityLabel("Nota automatica quando sottolinei").accessibilityIdentifier("lensAutoNote")
        }
    }

    private var askControls: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Scatta, ritaglia e chiedi", systemImage: "camera", action: actions.photo)
                Button("Scegli da Foto e chiedi", systemImage: "photo.on.rectangle", action: actions.library)
            } label: { Image(systemName: "camera").frame(width: 44, height: 44) }
                .accessibilityLabel("Foto e chiedi").accessibilityIdentifier("lensPhoto")
            Button(action: actions.notes) { notesIcon }
                .accessibilityLabel("Note della Lente").accessibilityIdentifier("lensNotes")
            Button(action: actions.chat) { Image(systemName: "bubble.left.and.text.bubble.right").frame(width: 44, height: 44) }
                .accessibilityLabel("Chat sulla pagina").accessibilityIdentifier("lensOpenChat")
        }
    }

    private var notesIcon: some View {
        let count = notesCount
        return Image(systemName: "list.bullet.rectangle.portrait").frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    Text("\(count)").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 4)
                        .background(Brand.accent, in: Capsule()).offset(x: 2, y: 4)
                }
            }
    }

    private var panelControls: some View {
        let icon: String = ready ? "slider.horizontal.3" : "exclamationmark.triangle.fill"
        let tint: Color = ready ? Color.primary : Color.orange
        return HStack(spacing: 4) {
            Button { help.toggle() } label: { Image(systemName: "questionmark.circle").frame(width: 44, height: 44) }
                .accessibilityLabel("Come si usa")
            Button { configuring = true } label: { Image(systemName: icon).frame(width: 44, height: 44).foregroundStyle(tint) }
                .accessibilityLabel("Connessione AI").accessibilityIdentifier("lensSettings")
            Button { model.chooseTool(.pen) } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                .foregroundStyle(.secondary).accessibilityLabel("Esci dalla Lente").accessibilityIdentifier("lensExit")
        }
    }

    private var hintRow: some View {
        let text: String = ready ? hint : "Collega un motore AI e consenti l’invio per usare la Lente."
        return HStack(alignment: .top, spacing: 8) {
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            if !ready { Button("Collega") { configuring = true }.font(.caption.bold()) }
            else { Button("Ho capito") { hintSeen = true; help = false }.font(.caption.bold()) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var hint: String {
        switch LensMode(rawValue: mode) ?? .text {
        case .image:
            return "Immagine: tocca una foto o cerchia una zona, l’AI guarda l’immagine. Con la fotocamera scatti, ritagli e chiedi."
        case .area:
            return "Area: cerchia o trascina un rettangolo attorno alle parole; si scelgono parole intere e accanto compaiono Spiega, Chiedi, Cerca e Copia."
        case .text:
            return autoNote
                ? "Parole: tocca una parola per sapere cos’è. Passaci sopra come un evidenziatore: un termine breve diventa subito una nota, un brano più lungo apre Spiega, Chiedi, Cerca e Copia."
                : "Parole: tocca una parola per sapere cos’è. Passaci sopra come un evidenziatore: accanto compaiono Spiega, Chiedi, Cerca e Copia."
        }
    }

    private func refresh() async {
        configuration = AIEngineStore.load()
        consentKey = await AIEngineRouter.restoredConsent(configuration)
    }
}
