import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var markerWidth: Double { writingOptions.markerWidth ?? max(1, min(80, thickness * 5)) }
    var markerWordsActive: Bool {
        tool == .marker && !rulerActive && writingOptions.markerSnapWords != false &&
        page.map { $0.pdfFile != nil && !PageWordIndex.shared.markerWords($0).isEmpty } == true
    }
    var markerCustomInput: Bool {
        tool == .marker && !rulerActive && (markerWordsActive || CGFloat(markerWidth) < PKInkingTool.InkType.marker.validWidthRange.lowerBound)
    }
    func chooseMarkerWidth(_ value: Double) {
        guard value.isFinite, (1...80).contains(value) else { return }
        editWriting {
            $0.markerWidth = value
            var widths = $0.markerRecentWidths ?? []; widths.removeAll { abs($0 - value) < 0.01 }; widths.insert(value, at: 0)
            $0.markerRecentWidths = Array(widths.prefix(3))
        }
    }
}

@MainActor
struct MarkerOptions: View {
    let model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Larghezza reale · \(model.markerWidth, specifier: "%.1f") pt").font(.callout.monospacedDigit())
            HStack {
                ForEach(widths, id: \.self) { width in
                    Button { model.chooseMarkerWidth(width) } label: { Text("\(width, specifier: "%.1f") pt").font(.caption.monospacedDigit()).frame(minWidth: 58, minHeight: 44) }
                        .accessibilityLabel("Evidenziatore largo \(width.formatted()) punti")
                }
            }
            Slider(value: Binding(get: { model.markerWidth }, set: { model.chooseMarkerWidth($0) }), in: 1...80, step: 0.5)
                .accessibilityLabel("Larghezza reale dell’evidenziatore").accessibilityIdentifier("markerActualWidth")
            Toggle("Aggancia alle parole del PDF", isOn: Binding(get: { model.writingOptions.markerSnapWords != false }, set: { enabled in model.editWriting { $0.markerSnapWords = enabled } }))
                .accessibilityIdentifier("markerSnapPDFWords")
            Text("Scorri sulle parole o subito sotto: il colore segue quelle selezionate. Sulle scansioni usa prima la Lente per riconoscerle; altrimenti rimane il tratto libero. La larghezza scelta vale per il tratto libero, mentre l’aggancio segue l’altezza delle parole.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var widths: [Double] {
        let recent = model.writingOptions.markerRecentWidths ?? []
        return Array((recent + [2.0, 6, 12].filter { !recent.contains($0) }).prefix(3))
    }
}
