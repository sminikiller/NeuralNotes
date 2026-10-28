import SwiftUI
import NeuralNotesCore

@MainActor
struct ElementEditor: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var texts: [TextElement] = []
    @State private var images: [ImageElement] = []
    @State private var shapes: [ShapeElement] = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in Form {
                Section {
                    Button("Aggiungi casella di testo", systemImage: "text.badge.plus") {
                        texts.append(TextElement(text: "Nuovo testo"))
                    }
                }
                ForEach($texts) { $text in
                    Section(model.selectedIDs.contains(text.id) ? "Testo selezionato" : "Testo") {
                        RichTextEditor(text: $text).frame(minHeight: 150)
                        position(x: $text.x, y: $text.y, width: $text.width)
                        Stepper("Dimensione \(Int(text.fontSize)) pt", value: $text.fontSize, in: 10...96)
                        Button("Rimuovi testo", role: .destructive) { texts.removeAll { $0.id == text.id } }
                    }.id(text.id)
                }
                ForEach($images) { $image in
                    Section(model.selectedIDs.contains(image.id) ? "Immagine selezionata" : "Immagine") {
                        position(x: $image.x, y: $image.y, width: $image.width)
                        HStack { Text("Altezza"); TextField("Altezza", value: $image.height, format: .number).keyboardType(.decimalPad) }
                        Button("Rimuovi immagine", role: .destructive) { images.removeAll { $0.id == image.id } }
                    }.id(image.id)
                }
                ForEach($shapes) { $shape in
                    Section(model.selectedIDs.contains(shape.id) ? "Forma selezionata" : "Forma") {
                        ShapeElementFields(shape: $shape)
                        Button("Rimuovi forma", role: .destructive) { shapes.removeAll { $0.id == shape.id } }
                    }.id(shape.id)
                }
            }.task {
                texts = model.page?.texts ?? []; images = model.page?.images ?? []; shapes = model.page?.shapes ?? []
                await Task.yield()
                if let id = model.selectedObjectID { proxy.scrollTo(id, anchor: .top) }
            }
            }
            .navigationTitle("Oggetti sul foglio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        texts = texts.map { value in
                            var text = value
                            if !text.x.isFinite { text.x = 48 }; if !text.y.isFinite { text.y = 64 }
                            if !text.width.isFinite { text.width = 480 }; if !text.fontSize.isFinite { text.fontSize = 24 }
                            text.x = min(max(text.x, 0), (model.page?.width ?? 768) - 20)
                            text.y = min(max(text.y, 0), (model.page?.height ?? 1024) - 20)
                            text.width = min(max(text.width, 20), 20000); return text
                        }
                        images = images.filter { [$0.x, $0.y, $0.width, $0.height].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0 }
                            .map { value in
                                var image = value
                                image.x = max(0, min(image.x, (model.page?.width ?? 768) - 20))
                                image.y = max(0, min(image.y, (model.page?.height ?? 1024) - 20))
                                image.width = min(image.width, 20000); image.height = min(image.height, 20000)
                                return image
                            }
                        shapes = shapes.filter { [$0.x, $0.y, $0.width, $0.height, $0.lineWidth].allSatisfy(\.isFinite) && $0.width > 0 && $0.height > 0 }
                            .map { value in
                                var shape = value
                                shape.x = max(0, min(shape.x, (model.page?.width ?? 768) - 20))
                                shape.y = max(0, min(shape.y, (model.page?.height ?? 1024) - 20))
                                shape.width = min(shape.width, 20000); shape.height = min(shape.height, 20000)
                                shape.lineWidth = min(200, max(0.1, shape.lineWidth)); return shape
                            }
                        model.editElements(texts: texts, images: images, shapes: shapes); dismiss()
                    }
                }
            }
        }
    }

    private func position(x: Binding<Double>, y: Binding<Double>, width: Binding<Double>) -> some View {
        Group {
            HStack { Text("X"); TextField("X", value: x, format: .number).keyboardType(.decimalPad) }
            HStack { Text("Y"); TextField("Y", value: y, format: .number).keyboardType(.decimalPad) }
            HStack { Text("Larghezza"); TextField("Larghezza", value: width, format: .number).keyboardType(.decimalPad) }
        }
    }
}
