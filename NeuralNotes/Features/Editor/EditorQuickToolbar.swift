import SwiftUI
import NeuralNotesCore

@MainActor
struct EditorQuickToolbar: View {
    @Bindable var model: EditorViewModel
    let photo: () -> Void, camera: () -> Void, text: () -> Void, edit: () -> Void, crop: () -> Void
    let workspace: () -> Void
    @State private var paletteOpen = false
    @State private var selectionOpen = false
    private var vertical: Bool { model.currentWorkspace.dock.vertical }
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
                        ForEach(ShapeKind.allCases, id: \.self) { kind in
                            Button(kind.title, systemImage: kind.icon) { model.shapeKind = kind; model.tool = .shape; model.configureTool() }
                        }
                    } label: { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Inserisci foto o forma")
                    if !vertical && usesInk {
                        ForEach(Array(quickColors.enumerated()), id: \.offset) { row in colorButton(row.element) }
                    }
                    if usesInk { Button { paletteOpen = true } label: {
                        Image(systemName: "paintpalette").frame(width: 44, height: 44)
                            .overlay(alignment: .bottomTrailing) { Circle().fill(model.ink).frame(width: 10, height: 10).padding(5) }
                    }.accessibilityLabel("Colori e spessori di \(model.tool.rawValue)")
                        .popover(isPresented: $paletteOpen) { ToolPalettePanel(model: model).padding().frame(width: 330) } }
                    if vertical && model.tool == .objects {
                        Button { selectionOpen = true } label: { Image(systemName: "selection.pin.in.out").frame(width: 44, height: 44) }
                            .accessibilityLabel("Azioni sulla selezione")
                            .popover(isPresented: $selectionOpen) { selectionBar.frame(width: 500, height: 64) }
                    }
                    Button(action: workspace) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .accessibilityLabel("Workspace \(model.currentWorkspace.name)").accessibilityIdentifier("editorWorkspace")
                }.padding(6)
            }
            .frame(maxWidth: vertical ? 56 : 900, maxHeight: vertical ? 560 : 56)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            if model.tool == .objects && !vertical { selectionBar.padding(6).frame(maxWidth: 700).background(.regularMaterial, in: Capsule()) }
        }.buttonStyle(EditorIconButtonStyle())
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
            .accessibilityLabel(item.title).help(item.title).accessibilityIdentifier("tool-\(item.title)")
    }
    private func colorButton(_ color: InkColor) -> some View {
        Button { model.chooseInk(color.color) } label: {
            Circle().fill(color.color).frame(width: 22, height: 22).overlay(Circle().stroke(.gray.opacity(0.4)))
                .padding(5).overlay(Circle().stroke(InkColor(model.ink) == color ? Brand.accent : .clear, lineWidth: 2))
        }.accessibilityLabel("Colore recente o preferito")
    }
    private var selectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Toggle(isOn: $model.multiSelection) { Image(systemName: "checkmark.circle") }.toggleStyle(.button).accessibilityLabel("Selezione multipla")
                Toggle(isOn: $model.selectRectangle) { Image(systemName: "rectangle.dashed") }.toggleStyle(.button).accessibilityLabel("Seleziona con un rettangolo")
                Button { model.selectAll() } label: { Image(systemName: "checkmark.square") }.accessibilityLabel("Seleziona tutto")
                Text("\(model.selectedIDs.count + (model.selectionIncludesInk ? 1 : 0)) selezionati").font(.caption).foregroundStyle(.secondary)
                Button(action: edit) { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Modifica selezione")
                Menu {
                    Button("Ingrandisci 10%") { model.transformSelection(scale: 1.1) }
                    Button("Riduci 10%") { model.transformSelection(scale: 1 / 1.1) }
                    Button("Ruota a destra 15°") { model.transformSelection(degrees: 15) }
                    Button("Ruota a sinistra 15°") { model.transformSelection(degrees: -15) }
                    Button("Applica il colore corrente") { model.recolorSelection(InkColor(model.ink)) }
                } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Trasforma selezione").disabled(!hasSelection)
                Button(action: crop) { Image(systemName: "crop") }.accessibilityLabel("Ritaglia immagine").disabled(!selectedImage)
                Button { model.rotateSelectedImage() } label: { Image(systemName: "rotate.right") }.accessibilityLabel("Ruota immagine").disabled(!selectedImage)
                Button { model.copySelection() } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copia selezione").keyboardShortcut("c", modifiers: .command).disabled(!hasSelection)
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
