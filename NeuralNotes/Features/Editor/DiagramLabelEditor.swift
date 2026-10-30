import SwiftUI
import NeuralNotesCore

@MainActor
struct DiagramLabelEditor: View {
    let model: EditorViewModel
    let target: DiagramLabelEditTarget
    @Environment(\.dismiss) private var dismiss
    @State private var draft = TextElement(text: "")
    @State private var autoFit = true
    private var shape: ShapeElement? { model.page?.shapes?.first { $0.id == target.objectID } }
    private var paper: UIColor { DiagramObjects.paperColor(model.page, shape: shape) }
    private var ink: UIColor { shape.map { DiagramObjects.labelColor($0, page: model.page) } ?? DiagramObjects.textColor(model.page) }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scrivi con Pencil o tastiera. L’etichetta rimane modificabile e segue il blocco.").font(.callout).foregroundStyle(.secondary)
                RichTextEditor(text: $draft, paperColor: paper, defaultColor: ink)
                    .accessibilityIdentifier("diagramLabelText").frame(minHeight: 160)
                    .padding(10).background(Color(uiColor: paper), in: RoundedRectangle(cornerRadius: 14))
                if shape != nil { Toggle("Riduci il carattere per contenere il testo", isOn: $autoFit) }
                Text("Usa Aa per elenchi, rientri e formattazione.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).navigationTitle("Etichetta")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { model.saveDiagramLabel(target, text: draft, autoFit: autoFit); dismiss() }.accessibilityIdentifier("diagramLabelSave") }
                }
                .task {
                    if let shape {
                        draft.text = shape.label ?? ""; draft.rtf = shape.labelRTF; draft.fontSize = shape.labelFontSize ?? 18; autoFit = shape.labelAutoFit ?? true
                    } else if let connector = model.page?.connectors?.first(where: { $0.id == target.objectID }) {
                        draft.text = connector.label ?? ""; draft.rtf = connector.labelRTF; draft.fontSize = connector.labelFontSize ?? 16
                    }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
