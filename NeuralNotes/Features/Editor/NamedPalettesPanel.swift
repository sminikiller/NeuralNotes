import SwiftUI
import NeuralNotesCore

@MainActor
struct NamedPalettesPanel: View {
    @Bindable var model: EditorViewModel
    private var palettes: [NamedInkPalette] { model.currentWorkspace.namedPalettes ?? [] }
    var body: some View {
        List {
            Section {
                Button { model.editWorkspace { $0.activeNamedPaletteID = nil } } label: {
                    HStack { Text("Colori personali dello strumento"); Spacer(); if model.currentWorkspace.activeNamedPaletteID == nil { Image(systemName: "checkmark") } }
                }
                Text("Il set scelto vale per questa attività del quaderno. Preferiti e recenti di penna ed evidenziatore restano indipendenti.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Set per materia") {
                ForEach(palettes) { palette in
                    HStack {
                        Button { model.editWorkspace { $0.activeNamedPaletteID = palette.id }; model.restoreToolPalette(); model.configureTool() } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(palette.name); if model.currentWorkspace.activeNamedPaletteID == palette.id { Image(systemName: "checkmark.circle.fill") } }
                                HStack(spacing: 4) { ForEach(palette.colors, id: \.self) { Circle().fill($0.color).frame(width: 16, height: 16).overlay(Circle().stroke(.gray.opacity(0.3))) } }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderless).accessibilityIdentifier("choosePalette-\(palette.id)")
                        NavigationLink { NamedPaletteEditor(model: model, original: palette) } label: { Image(systemName: "pencil") }
                            .fixedSize().accessibilityLabel("Modifica set \(palette.name)")
                    }
                }
                .onMove { from, to in model.editWorkspace { $0.namedPalettes?.move(fromOffsets: from, toOffset: to) } }
                .onDelete { offsets in
                    let ids = offsets.map { palettes[$0].id }
                    model.editWorkspace { profile in for id in ids { profile.removeNamedPalette(id) } }
                }
                NavigationLink { NamedPaletteEditor(model: model, original: nil) } label: { Label("Nuovo set di colori", systemImage: "plus") }
                    .disabled(palettes.count >= NamedInkPalette.maximumSets)
            }
        }.navigationTitle("Colori per materia").toolbar { EditButton() }
    }
}

@MainActor
private struct NamedPaletteEditor: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NamedInkPalette
    init(model: EditorViewModel, original: NamedInkPalette?) {
        self.model = model
        _draft = State(initialValue: original ?? NamedInkPalette(name: "Nuova materia", colors: [.black, .blue, .red, .green, .orange]))
    }
    var body: some View {
        Form {
            Section("Nome") { TextField("Materia", text: $draft.name).accessibilityIdentifier("paletteName") }
            Section("Colori · trascina per riordinarli") {
                ForEach(Array(draft.colors.enumerated()), id: \.offset) { row in
                    ColorPicker(row.element.hex, selection: Binding(get: { draft.colors.indices.contains(row.offset) ? draft.colors[row.offset].color : .black },
                        set: { if draft.colors.indices.contains(row.offset) { draft.colors[row.offset] = InkColor($0) } }), supportsOpacity: false)
                }
                .onMove { draft.colors.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { draft.colors.remove(atOffsets: $0) }
                Button("Aggiungi colore", systemImage: "plus") {
                    let choices: [InkColor] = [.black, .blue, .red, .green, .orange, .yellow, InkColor(0.6, 0.2, 0.8)]
                    if let unused = choices.first(where: { !draft.colors.contains($0) }) { draft.colors.append(unused) }
                    else { draft.colors.append(InkColor(Double(draft.colors.count) / 20, 0.4, 0.6)) }
                }.disabled(draft.colors.count >= NamedInkPalette.maximumColors)
            }
            if !draft.isValid { Text("Scegli un nome di massimo 40 caratteri e da 1 a 12 colori distinti.").font(.caption).foregroundStyle(.secondary) }
        }.navigationTitle("Modifica set")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.editWorkspace { profile in if profile.saveNamedPalette(draft) { profile.activeNamedPaletteID = draft.id } }
                        model.restoreToolPalette(); model.configureTool(); dismiss()
                    }.disabled(!draft.isValid)
                }
            }
    }
}
