import SwiftUI
import NeuralNotesCore

@MainActor
struct EraserTargetOptions: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Cancella", selection: Binding(get: { model.writingOptions.effectiveEraserTarget }, set: { target in
                model.editWriting { $0.eraserTarget = target; $0.markerOnly = target == .marker }
            })) {
                ForEach(EraserTarget.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("eraserTarget")
            Toggle("Solo evidenziatore", isOn: Binding(get: { model.writingOptions.effectiveEraserTarget == .marker }, set: { value in
                model.editWriting { $0.eraserTarget = value ? .marker : .all; $0.markerOnly = value }
            }))
            Text("Parziale e Tratto intero riguardano l’inchiostro. Gli oggetti toccati vengono eliminati interi; quelli bloccati restano protetti.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
