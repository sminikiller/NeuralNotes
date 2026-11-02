import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
extension EditorViewModel {
    var markerWidth: Double { writingOptions.markerWidth ?? max(1, min(80, thickness * 5)) }
    var wordHighlightEnabled: Bool { tool == .marker && !rulerActive && !protractorActive && writingOptions.effectiveMarkerMode == .words }
    var markerWordsActive: Bool {
        wordHighlightEnabled && page.map { !PageWordIndex.shared.groups(for: $0).isEmpty } == true
    }
    var markerCustomInput: Bool {
        tool == .marker && !rulerActive && !protractorActive && true
    }
    func prepareMarkerWords() {
        guard wordHighlightEnabled || (tool == .marker && writingOptions.effectiveMarkerMode == .rectangle && writingOptions.rectangleSnapLines == true), let page else { return }
        if page.pdfFile != nil || !page.images.isEmpty || !canvas.drawing.strokes.isEmpty { PageWordIndex.shared.prepare(page, model: self) }
    }
    func highlightWords(_ selection: (words: [PageWord], indices: [Int])) {
        guard hasLease, !loading, !navigating, !hasActiveStroke, var value = page else { return }
        do {
            let previous = value.pdfMarkups ?? []
            let marks = try WordHighlights.appending(words: selection.words, indices: selection.indices, to: previous,
                color: InkColor(ink), width: value.width, height: value.height)
            guard marks != previous else { status = "Parole già evidenziate"; return }
            let before = captureEdit()
            value.pdfMarkups = marks; try PageValidation.validate(value); page = value
            recordEdit(before, label: "Evidenzia parole"); drawingChanged(preservingRecognizedWords: true)
        } catch { self.error = error.localizedDescription }
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
            Picker("Modalità evidenziatore", selection: Binding(get: { model.writingOptions.effectiveMarkerMode }, set: { value in model.editWriting { $0.markerMode = value; $0.markerSnapWords = value == .words } })) {
                ForEach(MarkerInputMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).accessibilityIdentifier("markerMode")
            if model.writingOptions.effectiveMarkerMode == .rectangle {
                Toggle("Aggancia alle righe del PDF", isOn: Binding(get: { model.writingOptions.rectangleSnapLines == true }, set: { value in model.editWriting { $0.rectangleSnapLines = value } }))
                Text("Trascina da un angolo all’altro. Poi usa il lazo per spostare, ridimensionare o cambiare colore al rettangolo.").font(.caption).foregroundStyle(.secondary)
            }
            if model.writingOptions.effectiveMarkerMode != .rectangle {
            Text("Larghezza reale · \(model.markerWidth, specifier: "%.1f") pt").font(.callout.monospacedDigit())
            HStack {
                ForEach(widths, id: \.self) { width in
                    Button { model.chooseMarkerWidth(width) } label: { Text("\(width, specifier: "%.1f") pt").font(.caption.monospacedDigit()).frame(minWidth: 58, minHeight: 44) }
                        .accessibilityLabel("Evidenziatore largo \(width.formatted()) punti")
                }
            }
            Slider(value: Binding(get: { model.markerWidth }, set: { model.chooseMarkerWidth($0) }), in: 1...80, step: 0.5)
                .accessibilityLabel("Larghezza reale dell’evidenziatore").accessibilityIdentifier("markerActualWidth")
            Text("In Parole sottolinea come con la Lente: si colorano solo le parole riconosciute, anche nei testi inseriti e nelle scansioni. Attendi la lettura iniziale della grafia. Per un segno a mano libera scegli Tratto libero; la larghezza riguarda solo quel segno.")
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var widths: [Double] {
        let recent = model.writingOptions.markerRecentWidths ?? []
        return Array((recent + [2.0, 6, 12].filter { !recent.contains($0) }).prefix(3))
    }
}
