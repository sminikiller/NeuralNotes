import SwiftUI
import NeuralNotesCore

@MainActor
struct FocusToolButton: View {
    @Bindable var model: EditorViewModel
    let item: WorkspaceTool
    @State private var options = false
    var body: some View {
        Button { model.chooseTool(item) } label: { Image(systemName: item.icon).frame(width: 44, height: 44) }
            .accessibilityLabel(item.title).accessibilityIdentifier("focusTool-\(item.rawValue)")
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                if item == .ruler { if !model.rulerActive { model.chooseTool(item) } }
                else if item == .protractor { if !model.protractorActive { model.chooseTool(item) } }
                else { model.chooseTool(item) }
                options = true
            })
            // The floating bar can be moved to any edge. Let UIKit choose
            // a fitting arrow rather than forcing the popover off screen.
            .popover(isPresented: $options) { ToolOptionsPopover(model: model, tool: item) }
    }
}

@MainActor
struct FocusSelectionActions: View {
    @Bindable var model: EditorViewModel
    @State private var transfer = false
    private var hasSelection: Bool { !model.selectedIDs.isEmpty || model.selectionIncludesInk }
    var body: some View {
        Menu {
            Button("Seleziona tutto", systemImage: "checkmark.square") { model.selectAll() }
            Section {
                Button("Copia o sposta in un’altra pagina", systemImage: "doc.on.doc") { transfer = true }
                Button("Trascina sulle miniature", systemImage: "rectangle.grid.1x2") { model.selectionPageDragMode.toggle() }
                Button("Copia come immagine", systemImage: "photo.on.rectangle") { model.copySelectionImage() }
                Button("Condividi immagine", systemImage: "square.and.arrow.up") { model.selectionImageShareRequest += 1 }
            }.disabled(!hasSelection)
        } label: { Image(systemName: "selection.pin.in.out").frame(width: 44, height: 44) }
            .accessibilityLabel("Azioni sulla selezione").accessibilityIdentifier("focusSelectionActions")
            .sheet(isPresented: $transfer) { SelectionDestinationPanel(model: model) }
    }
}
