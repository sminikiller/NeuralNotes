import SwiftUI
import NeuralNotesCore

@MainActor
struct EditorQuickToolbar: View {
    @Bindable var model: EditorViewModel
    let photo: () -> Void, camera: () -> Void, text: () -> Void, edit: () -> Void, crop: () -> Void
    let workspace: () -> Void
    var lens = LensBarActions()
    @State private var paletteOpen = false
    @State private var selectionOpen = false
    @State private var lensOpen = false
    @State private var optionsTool: WorkspaceTool?
    private var vertical: Bool { model.currentWorkspace.dock.vertical }
    private var popoverEdge: Edge {
        switch model.currentWorkspace.dock { case .trailing: return .trailing; case .leading: return .leading; case .bottom: return .bottom; case .top: return .top }
    }
    private var hasSelection: Bool { !model.selectedIDs.isEmpty || model.selectionIncludesInk }
    private var selectedImage: Bool {
        model.selectedIDs.count == 1 && !model.selectionIncludesInk && model.page?.images.contains(where: { $0.id == model.selectedObjectID }) == true
    }
    var body: some View {
        VStack(spacing: 8) {
            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
                layout {
                    ForEach(model.currentWorkspace.favorites, id: \.self) { item in toolButton(item) }
                    Menu {
                        ForEach(WorkspaceTool.allCases, id: \.self) { item in
                            Button(item.title, systemImage: item.icon) { model.chooseTool(item) }
                        }
                    } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Tutti gli strumenti")
                    Button { Task { await model.performUndo() } } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                        .disabled(!model.canUndo).keyboardShortcut("z", modifiers: .command).accessibilityLabel("Annulla").accessibilityIdentifier("editorUndo")
                    Button { Task { await model.performRedo() } } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                        .disabled(!model.canRedo).keyboardShortcut("z", modifiers: [.command, .shift]).accessibilityLabel("Ripristina").accessibilityIdentifier("editorRedo")
                    Button(action: text) { Image(systemName: "text.badge.plus").frame(width: 44, height: 44) }
                        .accessibilityLabel("Inserisci testo").accessibilityIdentifier("editorAddText")
                    Menu {
                        Button("Inserisci foto", systemImage: "photo.badge.plus", action: photo)
                        Button("Scatta foto", systemImage: "camera", action: camera)
                        Button("Post-it", systemImage: "note.text") { model.addStickyNote() }
                        Button("Nastro per il ripasso", systemImage: "rectangle.fill") { model.addStudyTape() }
                        Menu("Timbri", systemImage: "seal") {
                            ForEach(["★ Importante", "Definizione", "Domanda per il prof", "Da ripassare"], id: \.self) { label in Button(label) { model.addStickyNote(label) } }
                        }
                        ForEach(ShapeKind.allCases, id: \.self) { kind in
                            Button(kind.title, systemImage: kind.icon) { model.chooseShape(kind) }
                        }
                    } label: { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Inserisci foto o forma")
                    if !vertical && usesInk {
                        ForEach(Array(quickColors.enumerated()), id: \.offset) { row in colorButton(row.element) }
                    }
                    if usesInk { Button { paletteOpen = true } label: {
                        Image(systemName: "paintpalette").frame(width: 44, height: 44)
                            .overlay(alignment: .bottomTrailing) { Circle().fill(model.ink).frame(width: 10, height: 10).padding(5) }
                    }.accessibilityLabel("Colori e spessori di \(model.tool.rawValue)")
                        .popover(isPresented: $paletteOpen, arrowEdge: popoverEdge) { ToolPalettePanel(model: model).padding().frame(width: 310).presentationCompactAdaptation(.popover) } }
                    verticalExtras
                    Button(action: workspace) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Workspace \(model.currentWorkspace.name)").accessibilityIdentifier("editorWorkspace")
                }.padding(6)
            }
            .frame(maxWidth: vertical ? 56 : 900, maxHeight: vertical ? 560 : 56)
            .accessibilityIdentifier("editorToolbarScroll")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            if model.tool == .objects && !vertical { selectionBar.padding(6).frame(maxWidth: 700).background(.regularMaterial, in: Capsule()) }
            // The Lens commands sit right under the toolbar, not over the page.
            if model.tool == .lens && !vertical { LensModeBar(model: model, actions: lens) }
        }.buttonStyle(EditorIconButtonStyle())
    }
    /// With the toolbar on a side, selection and Lens commands open from one button each.
    @ViewBuilder private var verticalExtras: some View {
        if vertical && model.tool == .objects {
            Button { selectionOpen = true } label: { Image(systemName: "selection.pin.in.out").frame(width: 44, height: 44) }
                .accessibilityLabel("Azioni sulla selezione")
                .popover(isPresented: $selectionOpen, arrowEdge: popoverEdge) { selectionBar.frame(width: 310, height: 64).presentationCompactAdaptation(.popover) }
        }
        if vertical && model.tool == .lens {
            Button { lensOpen = true } label: { Image(systemName: "sparkle.magnifyingglass").frame(width: 44, height: 44) }
                .accessibilityLabel("Comandi della Lente")
                .popover(isPresented: $lensOpen, arrowEdge: popoverEdge) { lensPopover }
        }
    }
    private var lensPopover: some View {
        LensModeBar(model: model, actions: lens).padding().frame(width: 460).presentationCompactAdaptation(.popover)
    }
    private var usesInk: Bool { model.tool == .pen || model.tool == .marker || model.tool == .shape }
    private var quickColors: [InkColor] {
        let palette = model.activePalette
        return Array((palette.recentColors + palette.favorites.filter { !palette.recentColors.contains($0) }).prefix(3))
    }
    private func toolButton(_ item: WorkspaceTool) -> some View {
        let selected = item == .ruler ? model.rulerActive : item.shape != nil ? model.tool == .shape && model.shapeKind == item.shape : model.tool.workspaceTool == item
        return Button { model.chooseTool(item) } label: { Image(systemName: item.icon).frame(width: 44, height: 44) }
            .background(selected ? Brand.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(selected ? Brand.accent : .primary)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityLabel(item.title).help(item.title).accessibilityIdentifier("tool-\(item.title)")
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                model.chooseTool(item); optionsTool = item
            })
            .popover(isPresented: Binding(get: { optionsTool == item }, set: { if !$0 { optionsTool = nil } }), arrowEdge: popoverEdge) {
                ToolOptionsPopover(model: model, tool: item)
            }
    }
    private func colorButton(_ color: InkColor) -> some View {
        Button { model.chooseInk(color.color) } label: {
            Circle().fill(color.color).frame(width: 22, height: 22).overlay(Circle().stroke(.gray.opacity(0.4)))
                .padding(5).overlay(Circle().stroke(InkColor(model.ink) == color ? Brand.accent : .clear, lineWidth: 2))
        }.accessibilityLabel("Colore \(color.hex)").accessibilityAddTraits(InkColor(model.ink) == color ? .isSelected : [])
    }
    private var selectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Toggle(isOn: $model.multiSelection) { Image(systemName: "checkmark.circle") }.toggleStyle(.button).accessibilityLabel("Selezione multipla")
                Toggle(isOn: Binding(get: { model.selectRectangle }, set: { model.selectRectangle = $0; if $0 { model.selectFreehand = false } })) { Image(systemName: "rectangle.dashed") }.toggleStyle(.button).accessibilityLabel("Seleziona con un rettangolo")
                Button { model.selectAll() } label: { Image(systemName: "checkmark.square") }.accessibilityLabel("Seleziona tutto")
                Text("\(model.selectedIDs.count + (model.selectionIncludesInk ? 1 : 0)) selezionati").font(.caption).foregroundStyle(.secondary)
                SelectionAlignmentMenu(model: model)
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Modifica selezione")
                Button { model.shapeStyleRequest += 1 } label: { Image(systemName: "paintbrush.pointed") }
                    .accessibilityLabel("Stile forme").accessibilityIdentifier("selectionShapeStyle").disabled(model.selectedShapes.isEmpty)
                Menu {
                    Button("Porta davanti", systemImage: "square.3.layers.3d.top.filled") { model.arrangeSelection(front: true) }
                    Button("Chiedi alla Lente AI", systemImage: "sparkles") { model.lensAskAboutSelection() }
                    Button("Converti in testo", systemImage: "text.viewfinder") { Task { await model.convertSelectionToText() } }
                    Button("Copia area come immagine", systemImage: "photo.on.rectangle") { model.copySelectionImage() }
                    Button("Porta dietro", systemImage: "square.3.layers.3d.bottom.filled") { model.arrangeSelection(front: false) }
                    Button("Blocca oggetti", systemImage: "lock") { model.lockSelection() }
                    Button("Sblocca tutti gli oggetti", systemImage: "lock.open") { model.unlockObjects() }
                    Button("Ingrandisci 10%") { model.transformSelection(scale: 1.1) }
                    Button("Riduci 10%") { model.transformSelection(scale: 1 / 1.1) }
                    Button("Ruota a destra 15°") { model.transformSelection(degrees: 15) }
                    Button("Ruota a sinistra 15°") { model.transformSelection(degrees: -15) }
                    Button("Applica il colore corrente") { model.recolorSelection(InkColor(model.ink)) }
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Trasforma selezione").disabled(!hasSelection)
                Button(action: crop) { Image(systemName: "crop") }.accessibilityLabel("Ritaglia immagine").disabled(!selectedImage)
                Button { model.imageStraightenRequest += 1 } label: { Image(systemName: "viewfinder") }
                    .accessibilityLabel("Raddrizza immagine").disabled(!selectedImage)
                Button { model.rotateSelectedImage() } label: { Image(systemName: "rotate.right") }.accessibilityLabel("Ruota immagine").disabled(!selectedImage)
                Button { model.copySelection() } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copia selezione").keyboardShortcut("c", modifiers: .command).disabled(!hasSelection)
                MoveSelectionMenu(model: model).labelStyle(.iconOnly)
                Button { Task { await model.pasteSelection() } } label: { Image(systemName: "doc.on.clipboard") }.accessibilityLabel("Incolla").keyboardShortcut("v", modifiers: .command)
                Button { model.duplicateSelectedObject() } label: { Image(systemName: "plus.square.on.square") }.accessibilityLabel("Duplica selezione").disabled(!hasSelection)
                Button(role: .destructive) { model.deleteSelectedObject() } label: { Image(systemName: "trash") }.accessibilityLabel("Elimina selezione").disabled(!hasSelection)
            }.frame(minHeight: 44).padding(.horizontal, 16)
        }
    }
}

private struct EditorIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.55 : 1) : 0.35)
    }
}
