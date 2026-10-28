import SwiftUI
import NeuralNotesCore

@MainActor
struct ShapeElementFields: View {
    @Binding var shape: ShapeElement
    var body: some View {
        Picker("Forma", selection: $shape.kind) {
            ForEach(ShapeKind.allCases, id: \.self) { kind in Label(kind.title, systemImage: kind.icon).tag(kind) }
        }
        coordinate("X", $shape.x)
        coordinate("Y", $shape.y)
        coordinate("Larghezza", $shape.width)
        coordinate("Altezza", $shape.height)
        ColorPicker("Colore", selection: outlineColor, supportsOpacity: false)
        Stepper("Spessore \(Int(shape.lineWidth)) pt", value: $shape.lineWidth, in: 1...40)
        ShapeParametersFields(shape: $shape)
        NavigationLink("Stile della forma") {
            Form {
                ShapeStyleFields(style: style, maximumRadius: min(shape.width, shape.height) / 2)
            }.navigationTitle("Stile")
        }
    }
    private var style: Binding<NeuralNotesCore.ShapeStyle> {
        Binding(get: { NeuralNotesCore.ShapeStyle(shape) }, set: { shape = $0.applying(to: shape) })
    }
    private var outlineColor: Binding<Color> {
        Binding(get: { Color(red: shape.red, green: shape.green, blue: shape.blue) }, set: { color in
            let value = InkColor(color)
            shape.red = value.red; shape.green = value.green; shape.blue = value.blue
        })
    }
    private func coordinate(_ label: String, _ value: Binding<Double>) -> some View {
        HStack { Text(label); TextField(label, value: value, format: .number).keyboardType(.decimalPad) }
    }
}
