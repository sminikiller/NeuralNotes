import SwiftUI
import NeuralNotesCore

struct SelectionPageDropDelegate: DropDelegate {
    let model: EditorViewModel
    let pageID: UUID
    @Binding var targeted: Bool
    func validateDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            model.selectionPageDragMode && !model.selectionDropPending && pageID != model.page?.id &&
                info.hasItemsConforming(to: [SelectionPageDragPayload.type.identifier])
        }
    }
    func dropEntered(info: DropInfo) { MainActor.assumeIsolated { targeted = true } }
    func dropExited(info: DropInfo) { MainActor.assumeIsolated { targeted = false } }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated { DropProposal(operation: model.selectionDragCopy ? .copy : .move) }
    }
    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            targeted = false
            return model.receiveSelectionPageDrop(info.itemProviders(for: [SelectionPageDragPayload.type.identifier]), to: pageID)
        }
    }
}

@MainActor
struct SelectionPageDropRail: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.selectionDropPending ? "Trasferimento…" : "Trascina la selezione su una miniatura").font(.callout).lineLimit(2)
                Spacer(minLength: 4)
                Picker("Operazione", selection: $model.selectionDragCopy) { Text("Sposta").tag(false); Text("Copia").tag(true) }
                    .pickerStyle(.menu).disabled(model.selectionDropPending)
                Button { model.selectionPageDragMode = false; model.activeSelectionPageDrag = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Chiudi miniature di destinazione").disabled(model.selectionDropPending)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(model.pages.enumerated()).filter { $0.element.id != model.page?.id }, id: \.element.id) { row in
                        SelectionPageDropThumbnail(model: model, page: row.element, number: row.offset + 1)
                    }
                }.padding(.horizontal, 4)
            }.frame(height: 120)
            if model.pages.count < 2 { Text("Aggiungi una pagina oppure usa Copia o sposta per crearla.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 12).padding(.bottom, 10)
            .frame(maxWidth: 800).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.secondary.opacity(0.25)))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .accessibilityIdentifier("selectionPageDropRail")
    }
}

@MainActor
private struct SelectionPageDropThumbnail: View {
    @Bindable var model: EditorViewModel
    let page: PageSnapshot
    let number: Int
    @State private var targeted = false
    var body: some View {
        Button { transferByTap() } label: {
            VStack(spacing: 4) {
                PageThumbnail(page: page, workspace: model.workspace, maxDimension: 160).frame(width: 70, height: 90).clipped()
                Text("\(number)").font(.caption.monospacedDigit())
            }.padding(4).background(targeted ? Brand.accent.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(model.selectionDropPending)
            .accessibilityLabel("Pagina \(number), \(model.selectionDragCopy ? "copia" : "sposta") la selezione")
            .accessibilityIdentifier("selectionPageDrop-\(number)")
            .onDrop(of: [SelectionPageDragPayload.type.identifier], delegate: SelectionPageDropDelegate(model: model, pageID: page.id, targeted: $targeted))
    }
    private func transferByTap() {
        guard !model.selectionDropPending, let payload = model.makeSelectionPageDrag(),
              let data = try? JSONEncoder().encode(payload) else { return }
        model.selectionDropPending = true
        Task {
            defer { model.selectionDropPending = false }
            do { try await model.completeSelectionPageDrop(data, to: page.id, copy: model.selectionDragCopy) }
            catch { if model.error == nil { model.error = error.localizedDescription } }
        }
    }
}
