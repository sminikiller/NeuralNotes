import SwiftUI
import NeuralNotesCore

@MainActor
struct QuickHistoryOverlay: View {
    @Bindable var model: EditorViewModel
    private var busy: Bool { model.loading || model.navigating || model.hasActiveStroke || !model.hasLease }
    var body: some View {
        HStack(spacing: 2) {
            Button { Task { await model.performUndo() } } label: { Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44) }
                .disabled(busy || !model.canUndo).accessibilityLabel("Annulla ultima azione").accessibilityIdentifier("quickUndo")
                .accessibilityHint(model.history.undo?.label ?? "Nessuna azione da annullare")
            Divider().frame(height: 20).accessibilityHidden(true)
            Button { Task { await model.performRedo() } } label: { Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44) }
                .disabled(busy || !model.canRedo).accessibilityLabel("Ripristina ultima azione").accessibilityIdentifier("quickRedo")
                .accessibilityHint(model.history.redo?.label ?? "Nessuna azione da ripristinare")
        }.padding(3).font(.system(size: 17, weight: .medium)).buttonStyle(.plain).foregroundStyle(Brand.accent)
            .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.gray.opacity(0.25)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .fixedSize().accessibilityElement(children: .contain)
    }
}
