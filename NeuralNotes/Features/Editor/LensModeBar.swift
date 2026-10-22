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
                    Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Brand.accent).padding(.leading, 8).accessibilityHidden(true)
                    Picker("Modo della Lente", selection: $mode) {
                        Text("Testo").tag(LensMode.text.rawValue)
                        Text("Immagine").tag(LensMode.image.rawValue)
                    }.pickerStyle(.segmented).frame(width: 160).accessibilityIdentifier("lensMode")
                    Toggle(isOn: $autoNote) { Image(systemName: "note.text.badge.plus") }
                        .toggleStyle(.button).disabled(mode == LensMode.image.rawValue)
                        .accessibilityLabel("Nota automatica quando sottolinei").accessibilityIdentifier("lensAutoNote")
                    Menu {
                        Button("Scatta, ritaglia e chiedi", systemImage: "camera", action: actions.photo)
                        Button("Scegli da Foto e chiedi", systemImage: "photo.on.rectangle", action: actions.library)
                    } label: { Image(systemName: "camera").frame(width: 44, height: 44) }
                        .accessibilityLabel("Foto e chiedi").accessibilityIdentifier("lensPhoto")
                    Button(action: actions.notes) {
                        Image(systemName: "list.bullet.rectangle.portrait").frame(width: 44, height: 44)
                            .overlay(alignment: .topTrailing) {
                                if notesCount > 0 {
                                    Text("\(notesCount)").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 4)
                                        .background(Brand.accent, in: Capsule()).offset(x: 2, y: 4)
                                }
                            }
                    }.accessibilityLabel("Note della Lente").accessibilityIdentifier("lensNotes")
                    Button(action: actions.chat) { Image(systemName: "bubble.left.and.text.bubble.right").frame(width: 44, height: 44) }
                        .accessibilityLabel("Chat sulla pagina").accessibilityIdentifier("lensOpenChat")
                    Button { help.toggle() } label: { Image(systemName: "questionmark.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Come si usa")
                    Button { configuring = true } label: {
                        Image(systemName: ready ? "slider.horizontal.3" : "exclamationmark.triangle.fill").frame(width: 44, height: 44)
                            .foregroundStyle(ready ? Color.primary : Color.orange)
                    }.accessibilityLabel("Connessione AI").accessibilityIdentifier("lensSettings")
                    Button { model.chooseTool(.pen) } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                        .foregroundStyle(.secondary).accessibilityLabel("Esci dalla Lente").accessibilityIdentifier("lensExit")
                }.padding(.horizontal, 4)
            }
            .frame(maxWidth: 640, minHeight: 48, maxHeight: 52)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18)))
            if !ready || !hintSeen || help {
                HStack(alignment: .top, spacing: 8) {
                    Text(ready ? hint : "Collega un motore AI e consenti l’invio per usare la Lente.").font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !ready { Button("Collega") { configuring = true }.font(.caption.bold()) }
                    else { Button("Ho capito") { hintSeen = true; help = false }.font(.caption.bold()) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: 560)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task { await refresh() }
        .sheet(isPresented: $configuring, onDismiss: { Task { await refresh() } }) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
    }

    private var hint: String {
        if mode == LensMode.image.rawValue { return "Tocca una foto o cerchia una zona: l’AI guarda l’immagine. Con la fotocamera scatti, ritagli e chiedi." }
        return autoNote
            ? "Sottolinea un termine: arriva una nota collegata al testo. Tocca una parola per spiegarla; cerchia per chiedere. Trascina le note per spostarle."
            : "Sottolinea, cerchia o trascina: a destra si apre la conversazione con spiegazione, riassunto, traduzione e domande."
    }

    private func refresh() async {
        configuration = AIEngineStore.load()
        consentKey = await AIEngineRouter.restoredConsent(configuration)
    }
}
