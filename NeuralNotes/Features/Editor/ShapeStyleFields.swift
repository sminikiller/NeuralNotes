import SwiftUI
import NeuralNotesCore

@MainActor
struct ShapeStyleFields: View {
    @Binding var style: NeuralNotesCore.ShapeStyle
    var maximumRadius: Double = 80
    var body: some View {
        Section("Contorno") {
            ColorPicker("Colore del contorno", selection: color(\.color, fallback: .black), supportsOpacity: false)
            Text("Spessore · \(style.width ?? 3, specifier: "%.1f") pt")
            Slider(value: value(\.width, fallback: 3), in: 0.5...40).accessibilityLabel("Spessore del contorno")
            Picker("Tratto", selection: value(\.dash, fallback: .solid)) {
                ForEach(ShapeDash.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text("Opacità contorno · \(Int((style.strokeOpacity ?? 1) * 100))%")
            Slider(value: value(\.strokeOpacity, fallback: 1), in: 0...1).accessibilityLabel("Opacità del contorno")
        }
        Section("Riempimento") {
            Button {
                var value = style
                value.fill = value.fill == nil ? (value.color ?? .black) : nil
                style = value
            } label: {
                Label(style.fill == nil ? "Attiva riempimento" : "Disattiva riempimento", systemImage: style.fill == nil ? "square" : "square.fill")
            }.accessibilityIdentifier("shapeFillEnabled").accessibilityValue(style.fill == nil ? "Disattivo" : "Attivo")
            if style.fill != nil {
                ColorPicker("Colore del riempimento", selection: color(\.fill, fallback: .blue), supportsOpacity: false)
                Text("Opacità riempimento · \(Int((style.fillOpacity ?? 0.25) * 100))%")
                Slider(value: value(\.fillOpacity, fallback: 0.25), in: 0...1).accessibilityLabel("Opacità del riempimento")
            }
        }
        Section("Angoli e frecce") {
            Text("Angoli arrotondati · \(style.cornerRadius ?? 0, specifier: "%.0f") pt")
            Slider(value: value(\.cornerRadius, fallback: 0), in: 0...max(1, maximumRadius)).accessibilityLabel("Raggio degli angoli")
            Text("Il raggio vale per rettangoli e rombi; le punte per linee, frecce e archi.").font(.caption).foregroundStyle(.secondary)
            Picker("Punte delle frecce", selection: value(\.arrowHeads, fallback: ArrowHeads.none)) {
                ForEach(ArrowHeads.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Stile punta", selection: value(\.arrowStyle, fallback: .open)) {
                ForEach(ArrowStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        }
    }
    private func value<T>(_ key: WritableKeyPath<NeuralNotesCore.ShapeStyle, T?>, fallback: T) -> Binding<T> {
        Binding(get: { style[keyPath: key] ?? fallback }, set: { style[keyPath: key] = $0 })
    }
    private func color(_ key: WritableKeyPath<NeuralNotesCore.ShapeStyle, InkColor?>, fallback: InkColor) -> Binding<Color> {
        Binding(get: { (style[keyPath: key] ?? fallback).color }, set: { style[keyPath: key] = InkColor($0) })
    }
}

@MainActor
struct ShapeParametersFields: View {
    @Binding var shape: ShapeElement
    var body: some View {
        if shape.kind == .polygon || shape.kind == .star {
            Stepper(sideTitle, value: sideCount, in: minimumSides...12)
        }
        if shape.kind == .star { starParameters }
        if shape.kind == .arc { arcParameters }
        if shape.kind == .freePolygon { Text("Con Oggetti trascina i vertici. Tieni premuto un lato per aggiungere un vertice, o un vertice per rimuoverlo.").font(.caption).foregroundStyle(.secondary) }
    }
    private var minimumSides: Int { shape.kind == .star ? 4 : 3 }
    private var sideTitle: String { shape.kind == .star ? "Punte: \(shape.sides ?? 5)" : "Lati: \(shape.sides ?? 6)" }
    private var sideCount: Binding<Int> {
        Binding(get: { shape.sides ?? (shape.kind == .star ? 5 : 6) }, set: { shape.sides = $0; shape.vertices = nil })
    }
    private var starRatio: Binding<Double> { Binding(get: { shape.innerRatio ?? 0.5 }, set: { shape.innerRatio = $0 }) }
    private var arcDegrees: Double { abs(shape.arcSweep ?? Double.pi) * 180.0 / Double.pi }
    private var arcBinding: Binding<Double> {
        Binding(get: { arcDegrees }, set: { degrees in
            let sign = (shape.arcSweep ?? Double.pi) < 0 ? -1.0 : 1.0
            shape.arcSweep = degrees * Double.pi / 180.0 * sign
        })
    }
    private var starParameters: some View {
        Group {
            Text("Raggio interno · \(Int((shape.innerRatio ?? 0.5) * 100))%")
            Slider(value: starRatio, in: 0.2...0.8)
                .accessibilityLabel("Rapporto raggio interno della stella")
        }
    }
    private var arcParameters: some View {
        Group {
            Text("Ampiezza · \(Int(arcDegrees))°")
            Slider(value: arcBinding, in: 10...350).accessibilityLabel("Ampiezza dell’arco")
        }
    }
}
