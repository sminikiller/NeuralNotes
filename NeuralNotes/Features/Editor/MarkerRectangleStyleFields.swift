import SwiftUI
import NeuralNotesCore

@MainActor
struct MarkerRectangleStyleFields: View {
    @Binding var style: NeuralNotesCore.ShapeStyle
    var body: some View {
        ColorPicker("Colore", selection: Binding(get: { (style.fill ?? style.color ?? .yellow).color }, set: { style.fill = InkColor($0) }), supportsOpacity: false)
        HStack { Text("Opacità"); Text(style.fillOpacity ?? 0.25, format: .percent).monospacedDigit() }
        Slider(value: Binding(get: { style.fillOpacity ?? 0.25 }, set: { style.fillOpacity = $0 }), in: 0.05...0.8)
            .accessibilityLabel("Opacità evidenziatore")
    }
}
