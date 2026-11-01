import SwiftUI
import NeuralNotesCore

@MainActor
struct ToolCatalogPanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var options: WorkspaceTool?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Strumenti").font(.headline)
                Text("Tocca per usare · tieni premuto per le opzioni").font(.caption).foregroundStyle(.secondary)
                group("Scrittura", [.pen, .marker, .eraser, .text])
                group("Selezione e studio", [.lasso, .objects, .lens, .audioLink])
                group("Forme", [.line, .arrow, .ellipse, .rectangle, .triangle])
                group("Guide da disegno", [.ruler, .protractor, .square45, .square60])
            }.padding(16)
        }.accessibilityIdentifier("toolCatalogScroll").frame(width: 320).frame(maxHeight: 560).presentationCompactAdaptation(.popover)
    }
    private func group(_ title: String, _ tools: [WorkspaceTool]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(tools, id: \.self) { item in
                HStack(spacing: 4) {
                    Button { model.chooseTool(item); dismiss() } label: {
                        Label(item.title, systemImage: item.icon).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("catalogTool-\(item.rawValue)")
                        .highPriorityGesture(LongPressGesture(minimumDuration: 0.35).onEnded { _ in model.openToolOptions(item); options = item })
                        .accessibilityAction(named: "Opzioni dello strumento") { model.openToolOptions(item); options = item }
                    Button { model.openToolOptions(item); options = item } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Opzioni di \(item.title)").accessibilityIdentifier("catalogOptions-\(item.rawValue)")
                }.popover(isPresented: Binding(get: { options == item }, set: { if !$0 { options = nil } })) {
                    ToolOptionsPopover(model: model, tool: item)
                }

            }
        }
    }
}
