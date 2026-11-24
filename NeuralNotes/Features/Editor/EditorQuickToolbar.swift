import SwiftUI
import NeuralNotesCore

@MainActor
struct EditorQuickToolbar: View {
    @Bindable var model: EditorViewModel
    let photo: () -> Void, camera: () -> Void, text: () -> Void, edit: () -> Void, crop: () -> Void
    let workspace: () -> Void
    let study: () -> Void
    var lens = LensBarActions()
    @State private var paletteOpen = false
    @State private var rowWidth: CGFloat = 0
    @State private var selectionOpen = false
    @State private var lensOpen = false
    @State private var optionsTool: WorkspaceTool?
    @State private var allToolsOpen = false
    @State private var openStudyAfterCatalog = false
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
                    Button { allToolsOpen = true } label: { Image(systemName: "plus.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Tutti gli strumenti").accessibilityIdentifier("allWritingTools")
                        .popover(isPresented: $allToolsOpen, arrowEdge: popoverEdge) {
                            ToolCatalogPanel(model: model, openStudy: {
                                openStudyAfterCatalog = true
                                allToolsOpen = false
                            }).onDisappear {
                                if openStudyAfterCatalog {
                                    openStudyAfterCatalog = false
                                    study()
                                }
                            }
                        }
                    Button(action: text) { Image(systemName: "text.badge.plus").frame(width: 44, height: 44) }
                        .accessibilityLabel("Inserisci testo").accessibilityIdentifier("editorAddText")
                    Menu {
                        Button("Inserisci foto", systemImage: "photo.badge.plus", action: photo)
                        Button("Scatta foto", systemImage: "camera", action: camera)
                        Button("Studio: schemi, scotch e capitoli", systemImage: "point.3.connected.trianglepath.dotted", action: study).accessibilityIdentifier("openStudyKit")
                        Button("Post-it", systemImage: "note.text") { model.addStickyNote() }
                        Button("Nastro per il ripasso", systemImage: "rectangle.fill") { model.addStudyTape() }
                        Menu("Timbri", systemImage: "seal") {
                            ForEach(["★ Importante", "Definizione", "Domanda per il prof", "Da ripassare"], id: \.self) { label in Button(label) { model.addStickyNote(label) } }
                        }
                        ForEach(ShapeKind.allCases, id: \.self) { kind in
                            Button(kind.title, systemImage: kind.icon) { model.chooseShape(kind) }
                        }
                    } label: { Image(systemName: "photo.badge.plus").frame(width: 44, height: 44) }.accessibilityLabel("Inserisci").accessibilityIdentifier("editorInsertMenu")
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
                }.padding(4)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            }
            .frame(maxWidth: vertical ? 56 : (rowWidth > 0 ? rowWidth : 900), maxHeight: vertical ? 560 : 52)
            .accessibilityIdentifier("editorToolbarScroll")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.18)))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            if let name = model.activeLayerName {
                Text(name).font(.caption2).lineLimit(1).truncationMode(.middle).frame(maxWidth: vertical ? 72 : 180)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(.regularMaterial, in: Capsule())
                    .accessibilityLabel("Livello attivo: \(name)").accessibilityIdentifier("activeLayerBadge")
            }
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
        Array(model.currentWorkspace.displayedColors(for: model.tool.workspaceTool).prefix(3))
    }
    private func toolButton(_ item: WorkspaceTool) -> some View {
        let selected = isSelected(item)
        return Button { model.chooseTool(item) } label: { Image(systemName: item.icon).frame(width: 44, height: 44) }
            .background(selected ? Brand.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(selected ? Brand.accent : .primary)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityLabel(item.title).help(item.title).accessibilityIdentifier("tool-\(item.title)")
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                model.openToolOptions(item)
                optionsTool = item
            })
            .popover(isPresented: Binding(get: { optionsTool == item }, set: { if !$0 { optionsTool = nil } }), arrowEdge: popoverEdge) {
                ToolOptionsPopover(model: model, tool: item)
            }
    }
    private func isSelected(_ item: WorkspaceTool) -> Bool {
        if let kind = item.draftingKind { return model.rulerActive && model.rulerGuide.kind == kind }
        if item == .lasso { return model.tool == .lasso || (model.tool == .objects && model.selectFreehand) }
        if item == .objects { return model.tool == .objects && !model.selectFreehand }
        if item == .protractor { return model.protractorActive }
        if let shape = item.shape { return model.tool == .shape && model.shapeKind == shape }
        return model.tool.workspaceTool == item
    }
    private func colorButton(_ color: InkColor) -> some View {
        Button { model.chooseInk(color.color) } label: {
            Circle().fill(color.color).frame(width: 22, height: 22).overlay(Circle().stroke(.gray.opacity(0.4)))
                .padding(5).overlay(Circle().stroke(InkColor(model.ink) == color ? Brand.accent : .clear, lineWidth: 2))
        }.accessibilityLabel("Colore \(color.hex)").accessibilityAddTraits(InkColor(model.ink) == color ? .isSelected : [])
    }
    private var selectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { model.selectAll() } label: { Image(systemName: "checkmark.square") }.accessibilityLabel("Seleziona tutto")
                if hasSelection {
                    Button("Copia", systemImage: "doc.on.doc") { model.copySelection() }
                        .accessibilityLabel("Copia selezione")
                }
                Button("Incolla", systemImage: "doc.on.clipboard") { Task { await model.pasteSelection() } }
                MoveSelectionMenu(model: model).labelStyle(.iconOnly)
                if model.arrangementCount >= 2 { SelectionAlignmentMenu(model: model) }
                if !model.selectedShapes.isEmpty || model.selectedConnector != nil {
                    Button("Stile", systemImage: "slider.horizontal.3") { model.editSelection() }
                        .accessibilityIdentifier("selectionShapeStyle")
                }
                if model.selectionIncludesInk { HandwritingMenu(model: model) }
                Menu {
                    if hasSelection {
                        Section {
                            SelectionEditButtons(model: model)
                            if model.selectedIDs.count == 1, model.selectedShapes.isEmpty, model.selectedConnector == nil {
                                Button("Modifica oggetto", systemImage: "pencil") { model.editSelection() }
                            }
                            Button("Trascina sulle miniature", systemImage: "rectangle.grid.1x2") {
                                selectionOpen = false; model.selectionPageDragMode.toggle()
                            }.accessibilityIdentifier("selectionPageDrag")
                        }
                        Menu("Dimensioni e rotazione") {
                            Button("Ingrandisci 10%") { model.transformSelection(scale: 1.1) }
                            Button("Riduci 10%") { model.transformSelection(scale: 1 / 1.1) }
                            Button("Ruota a destra 15°") { model.transformSelection(degrees: 15) }
                            Button("Ruota a sinistra 15°") { model.transformSelection(degrees: -15) }
                        }
                        if selectedImage {
                            Button("Ritaglia immagine", systemImage: "crop", action: crop)
                            Button("Raddrizza immagine", systemImage: "viewfinder") { model.imageStraightenRequest += 1 }
                            Button("Ruota immagine", systemImage: "rotate.right") { model.rotateSelectedImage() }
                        }
                        if model.selectedIDs.count == 1, let id = model.selectedObjectID {
                            if model.page?.shapes?.contains(where: { $0.id == id }) == true {
                                Button("Testo nella forma", systemImage: "textformat") { model.editDiagramLabel(id) }
                                    .accessibilityIdentifier("selectionDiagramLabel")
                            }
                            if model.page?.tapes?.contains(where: { $0.id == id }) == true {
                                Button("Stile scotch", systemImage: "rectangle.fill", action: study)
                            }
                            if let note = model.page?.texts.first(where: { $0.id == id }), let style = note.studyNote {
                                Button(style.collapsed == true ? "Apri post-it" : "Richiudi post-it") { model.toggleStudyNote(id) }
                                Button("Post-it del quaderno", action: study)
                            }
                        }
                        Menu("Ordine e colore") {
                            Button("Porta davanti") { model.arrangeSelection(front: true) }
                            Button("Porta dietro") { model.arrangeSelection(front: false) }
                            Button("Applica il colore corrente") { model.recolorSelection(InkColor(model.ink)) }
                            if !model.selectedIDs.isEmpty { Button("Blocca oggetti") { model.lockSelection() } }
                        }
                        Menu("Usa la selezione") {
                            Button("Chiedi alla Lente AI") { model.lensAskAboutSelection() }
                            if model.selectionIncludesInk { Button("Converti in testo") { Task { await model.convertSelectionToText() } } }
                            Button("Copia come immagine") { model.copySelectionImage() }
                            Button("Condividi immagine") { model.selectionImageShareRequest += 1 }
                        }
                    }
                    Section("Selezione") {
                        Toggle("Selezione multipla", isOn: $model.multiSelection)
                        Toggle("Seleziona con un rettangolo", isOn: Binding(get: { model.selectRectangle }, set: {
                            model.selectRectangle = $0; if $0 { model.selectFreehand = false }
                        }))
                        if model.page?.lockedObjects?.isEmpty == false { Button("Sblocca tutti gli oggetti") { model.unlockObjects() } }
                    }
                } label: { Label("Azioni", systemImage: "ellipsis.circle") }
                    .accessibilityIdentifier("selectionMoreActions")
            }.frame(minHeight: 44).padding(.horizontal, 16)
        }.accessibilityIdentifier("selectionActionsScroll")
    }
}

struct SelectionEditButtons: View {
    let model: EditorViewModel
    var body: some View {
        Group {
            Button("Taglia", systemImage: "scissors") { model.cutSelection() }.accessibilityLabel("Taglia selezione")
            Button("Duplica", systemImage: "plus.square.on.square") { model.duplicateSelectedObject() }.accessibilityLabel("Duplica selezione")
            Button("Elimina", systemImage: "trash", role: .destructive) { model.deleteSelectedObject() }.accessibilityLabel("Elimina selezione")
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
