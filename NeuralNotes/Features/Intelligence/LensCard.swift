import SwiftUI
import NeuralNotesCore

/// The Lens conversation about a selection: what was read (editable), ready-made
/// questions, the answers one under the other and a box for follow-up questions.
/// Each answer can become a note linked to the selected text.
@MainActor
struct LensSessionView: View {
    let model: EditorViewModel
    @Bindable var session: LensSession
    let insertPhoto: (Data, NormalizedCrop) -> Void
    @State private var question = ""
    @State private var configuring = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in conversation(proxy) }
            Divider()
            composer
        }
        .sheet(isPresented: $configuring, onDismiss: { Task { await session.refreshEngine() } }) {
            AIConnectionPanel(configuration: $session.configuration, consentKey: $session.consentKey)
        }
    }

    // Small parts keep each expression quick for the Swift Playgrounds type checker.
    private func conversation(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                engineNotice
                selection
                if !session.reading { prompts }
                ForEach(session.turns) { turn in answer(turn).id(turn.id) }
                if session.busy { busyRow.id("lensBusy") }
                if let error = session.error { Text(error).font(.caption).foregroundStyle(.red) }
            }.padding(14)
        }
        .onChange(of: session.turns.count) { _, _ in scrollToLast(proxy) }
        .onChange(of: session.busy) { _, busy in if busy { scrollToBusy(proxy) } }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let last = session.turns.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .top) }
    }

    private func scrollToBusy(_ proxy: ScrollViewProxy) {
        withAnimation { proxy.scrollTo("lensBusy", anchor: .bottom) }
    }

    @ViewBuilder private var engineNotice: some View {
        if !session.engineReady { setup } else if !session.consented { consent }
    }

    private var busyRow: some View {
        let label = "\(session.pending) · chiedo a \(session.configuration.engine.title)…"
        return HStack {
            ProgressView()
            Text(label).font(.caption).lineLimit(2)
            Spacer()
            Button("Stop") { session.cancel() }.font(.caption)
        }
    }

    private var composer: some View {
        let placeholder: String = session.turns.isEmpty ? "Chiedi qualcosa su questa selezione…" : "Fai un’altra domanda…"
        let empty = question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $question, axis: .vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder).accessibilityIdentifier("lensQuestion")
            Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .disabled(!session.canAsk || empty)
                .accessibilityLabel("Invia domanda").accessibilityIdentifier("lensSend")
        }.padding(10)
    }

    private func send() {
        let value = question
        question = ""
        session.ask(question: value, model: model)
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Collega un motore AI").font(.subheadline.bold())
            Text("Basta una chiave personale: DeepSeek (economico), OpenAI, Claude o Gemini. Nessun account richiesto.").font(.caption)
            Button("Collega adesso", systemImage: "bolt.fill") { configuring = true }.buttonStyle(.borderedProminent)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inviare la selezione a \(session.configuration.engine.title)?").font(.subheadline.bold())
            Text("Il testo letto (e l’immagine, se c’è) parte solo quando premi una domanda. La scelta vale per questo motore.").font(.caption)
            HStack {
                Button("Sì, sempre") { session.grant(model) }.buttonStyle(.borderedProminent)
                Button("Impostazioni") { configuring = true }.buttonStyle(.bordered)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var selection: some View {
        if session.reading {
            HStack { ProgressView(); Text("Leggo la selezione…").font(.caption).foregroundStyle(.secondary) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Selezione").font(.caption.bold()).foregroundStyle(.secondary)
                if let preview = session.preview { photoPreview(preview) }
                TextField(selectionPlaceholder, text: $session.text, axis: .vertical)
                    .lineLimit(1...6).textFieldStyle(.roundedBorder)
                if session.text.isEmpty && session.picture == nil {
                    Text("Nessun testo letto: scrivilo qui o cerchia una zona più grande.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var selectionPlaceholder: String {
        session.picture == nil ? "Testo selezionato" : "Testo letto nell’immagine (facoltativo)"
    }

    @ViewBuilder private func photoPreview(_ preview: UIImage) -> some View {
        Image(uiImage: preview).resizable().scaledToFit().frame(maxHeight: 160).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        if let photo = session.request.photo {
            Button("Inserisci la foto nella pagina", systemImage: "photo.badge.plus") { insertPhoto(photo, session.request.photoCrop ?? .full) }
                .font(.caption)
        }
    }

    private var prompts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(session.prompts) { prompt in promptButton(prompt) }
        }
    }

    private func promptButton(_ prompt: LensPrompt) -> some View {
        Button { session.ask(prompt, model: model) } label: {
            Label(prompt.label, systemImage: prompt.icon).font(.caption).lineLimit(1).frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).disabled(!session.canAsk)
    }

    private func answer(_ turn: LensTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(turn.label, systemImage: turn.icon).font(.subheadline.bold()).lineLimit(3)
            Text(turn.answer.noteBody).textSelection(.enabled)
            Text(turn.answer.origin).font(.caption2).foregroundStyle(.secondary)
            if let notice = turn.notice { Text(notice).font(.caption2).foregroundStyle(.orange) }
            answerActions(turn)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func answerActions(_ turn: LensTurn) -> some View {
        HStack {
            if let noteID = turn.noteID {
                Button("Vai alla nota", systemImage: "arrow.right.circle") { Task { await model.focusLensNote(noteID, pageID: turn.notePageID) } }
                    .buttonStyle(.bordered)
            } else {
                Button("Inserisci come nota", systemImage: "note.text.badge.plus") { session.insert(turn.id, model: model) }
                    .buttonStyle(.borderedProminent)
            }
            Button("Copia", systemImage: "doc.on.doc") { copy(turn) }.buttonStyle(.bordered)
        }.font(.caption)
    }

    private func copy(_ turn: LensTurn) {
        UIPasteboard.general.string = turn.noteTitle + "\n" + turn.answer.noteBody
    }
}

/// What the Lens does, shown before the first selection.
@MainActor
struct LensGuide: View {
    let model: EditorViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Come si usa la Lente").font(.headline)
                Label("Sottolinea un nome, una data o un termine: arriva una nota con la spiegazione.", systemImage: "underline")
                Label("Tocca una parola per spiegarla.", systemImage: "hand.tap")
                Label("Cerchia o trascina un rettangolo: qui puoi chiedere, riassumere, tradurre e continuare a domandare.", systemImage: "lasso")
                Label("Con la fotocamera scatti, ritagli la parte che ti serve e chiedi.", systemImage: "camera")
                Label("Le note si spostano trascinandole. Il cerchietto in alto le riduce a 💡; tocca 💡 per riaprirle.", systemImage: "note.text")
                if model.tool != .lens {
                    Button("Attiva la Lente", systemImage: "sparkle.magnifyingglass") { model.chooseTool(.lens) }.buttonStyle(.borderedProminent)
                }
            }.font(.callout).padding()
        }
    }
}

/// The Lens on the right of the page: the conversation about the selection,
/// the list of notes and the chat about the whole page.
@MainActor
struct LensSidePanel: View {
    @Bindable var model: EditorViewModel
    let notebook: Notebook
    let close: () -> Void
    let undock: () -> Void
    let insertPhoto: (Data, NormalizedCrop) -> Void
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Picker("Lente AI", selection: $model.lensTab) {
                ForEach(LensTab.allCases) { tab in Text(tab.title).tag(tab) }
            }.pickerStyle(.segmented).accessibilityIdentifier("lensTabs")
            if model.lensTab == .selection && model.lensSession != nil { undockButton }
            Button("Chiudi pannello", systemImage: "xmark", action: close).labelStyle(.iconOnly).accessibilityIdentifier("closeStudyInspector")
        }.padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var undockButton: some View {
        Button(action: undock) { Image(systemName: "rectangle.on.rectangle") }
            .accessibilityLabel("Finestra mobile").help("Sposta la conversazione in una finestra mobile")
    }

    @ViewBuilder private var content: some View {
        switch model.lensTab {
        case .selection:
            if let session = model.lensSession { LensSessionView(model: model, session: session, insertPhoto: insertPhoto).id(session.id) }
            else { LensGuide(model: model) }
        case .notes: LensNotesList(model: model)
        case .page: LensPanel(model: model, notebook: notebook)
        }
    }
}

/// The conversation as a window above the page: drag it by its top bar; it never
/// leaves the visible area and keeps clear of the toolbar.
@MainActor
struct LensFloatingCard: View {
    let model: EditorViewModel
    let session: LensSession
    let dock: () -> Void
    let insertPhoto: (Data, NormalizedCrop) -> Void
    @AppStorage("lens.floating.x") private var savedX = -1.0
    @AppStorage("lens.floating.y") private var savedY = -1.0
    @State private var drag = CGSize.zero

    var body: some View {
        GeometryReader { geometry in window(in: geometry.size) }
            .accessibilityIdentifier("lensFloatingCard")
    }

    private func cardSize(in area: CGSize) -> CGSize {
        CGSize(width: min(380, max(240, area.width - 24)), height: min(520, max(220, area.height - 24)))
    }

    private func window(in area: CGSize) -> some View {
        let size = cardSize(in: area)
        let base = origin(in: area, card: size)
        let shown = clamp(CGPoint(x: base.x + drag.width, y: base.y + drag.height), in: area, card: size)
        return VStack(spacing: 0) {
            header.gesture(move(from: base, in: area, card: size))
            Divider()
            LensSessionView(model: model, session: session, insertPhoto: insertPhoto).id(session.id)
        }
        .frame(width: size.width, height: size.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.25)))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
        .offset(x: shown.x, y: shown.y)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            Label("Lente AI", systemImage: "sparkle.magnifyingglass").font(.headline)
            Spacer()
            Button(action: dock) { Image(systemName: "sidebar.right") }.accessibilityLabel("Aggancia a destra")
            Button { model.closeLensSession() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .accessibilityLabel("Chiudi")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func move(from base: CGPoint, in area: CGSize, card: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in drag = value.translation }
            .onEnded { value in
                let end = clamp(CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height), in: area, card: card)
                savedX = Double(end.x); savedY = Double(end.y); drag = .zero
            }
    }

    /// The toolbar edge stays free; the first time the window opens on the side away from the selection.
    private var insets: EdgeInsets {
        switch model.currentWorkspace.dock {
        case .top: return EdgeInsets(top: 132, leading: 12, bottom: 12, trailing: 12)
        case .bottom: return EdgeInsets(top: 12, leading: 12, bottom: 132, trailing: 12)
        case .leading: return EdgeInsets(top: 12, leading: 80, bottom: 12, trailing: 12)
        case .trailing: return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 80)
        }
    }

    private func origin(in area: CGSize, card: CGSize) -> CGPoint {
        if savedX >= 0, savedY >= 0 { return CGPoint(x: savedX, y: savedY) }
        let away = (model.lensAnchor?.midX ?? 0) > area.width / 2
        let x: CGFloat = away ? insets.leading : area.width - card.width - insets.trailing
        return CGPoint(x: x, y: insets.top)
    }

    private func clamp(_ point: CGPoint, in area: CGSize, card: CGSize) -> CGPoint {
        let maxX: CGFloat = max(12, area.width - card.width - insets.trailing)
        let maxY: CGFloat = max(12, area.height - card.height - insets.bottom)
        let x: CGFloat = min(max(min(insets.leading, maxX), point.x), maxX)
        let y: CGFloat = min(max(min(insets.top, maxY), point.y), maxY)
        return CGPoint(x: x, y: y)
    }
}
