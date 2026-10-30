import SwiftUI
import NeuralNotesCore

@MainActor
struct ConnectorStyleMenu: View {
    let model: EditorViewModel
    var body: some View {
        Menu {
            ForEach(ConnectorRouting.allCases, id: \.self) { routing in
                Button(routing.title) { model.setConnectorRouting(routing) }
            }
            Button("Modifica etichetta", systemImage: "textformat") { if let id = model.selectedConnector?.id { model.editDiagramLabel(id) } }
            Button("Stile del connettore", systemImage: "paintbrush.pointed") { model.connectorStyleRequest += 1 }
        } label: { Image(systemName: "point.topleft.down.curvedto.point.bottomright.up") }
        .accessibilityLabel("Connettore: tracciato, etichetta e stile").accessibilityIdentifier("connectorOptions")
    }
}

@MainActor
struct ConnectorStylePanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: ConnectorElement?
    var body: some View {
        NavigationStack {
            Form {
                if value != nil {
                    Picker("Tracciato", selection: routing) { ForEach(ConnectorRouting.allCases, id: \.self) { Text($0.title).tag($0) } }
                    ColorPicker("Colore", selection: color, supportsOpacity: false)
                    Text("Spessore · \(style.width ?? 2, specifier: "%.1f") pt")
                    Slider(value: width, in: 0.5...40).accessibilityLabel("Spessore del connettore")
                    Slider(value: opacity, in: 0...1) { Text("Opacità del connettore") }
                    Picker("Tratto", selection: dash) { ForEach(ShapeDash.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Punte", selection: heads) { ForEach(ArrowHeads.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Stile punta", selection: arrowStyle) { ForEach(ArrowStyle.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
            }.navigationTitle("Connettore")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { if let value { model.changeConnector(value, label: "Stile connettore") }; dismiss() } }
                }.task { value = model.selectedConnector }
        }
    }
    private var style: NeuralNotesCore.ShapeStyle { value?.effectiveStyle ?? .standard }
    private func edit(_ action: (inout NeuralNotesCore.ShapeStyle) -> Void) {
        guard var edge = value else { return }; var next = edge.effectiveStyle; action(&next); edge.style = next; value = edge
    }
    private var color: Binding<Color> { Binding(get: { (style.color ?? .blue).color }, set: { color in edit { $0.color = InkColor(color) } }) }
    private var width: Binding<Double> { Binding(get: { style.width ?? 2 }, set: { width in edit { $0.width = width } }) }
    private var opacity: Binding<Double> { Binding(get: { style.strokeOpacity ?? 1 }, set: { opacity in edit { $0.strokeOpacity = opacity } }) }
    private var dash: Binding<ShapeDash> { Binding(get: { style.dash ?? .solid }, set: { dash in edit { $0.dash = dash } }) }
    private var heads: Binding<ArrowHeads> { Binding(get: { style.arrowHeads ?? .end }, set: { heads in edit { $0.arrowHeads = heads } }) }
    private var arrowStyle: Binding<ArrowStyle> { Binding(get: { style.arrowStyle ?? .open }, set: { arrow in edit { $0.arrowStyle = arrow } }) }
    private var routing: Binding<ConnectorRouting> { Binding(get: { value?.routing ?? .curved }, set: { value?.routing = $0; value?.controlPoints = nil }) }
}
