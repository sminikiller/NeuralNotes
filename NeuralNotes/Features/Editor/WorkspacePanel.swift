import SwiftUI
import NeuralNotesCore

@MainActor
struct ToolPalettePanel: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.tool.rawValue).font(.headline)
            swatches("Preferiti", colors: model.activePalette.favorites)
            swatches("Ultimi tre colori", colors: model.activePalette.recentColors)
            HStack {
                ColorPicker("Altro colore", selection: Binding(get: { model.ink }, set: { model.chooseInk($0) }), supportsOpacity: false)
                Button { model.toggleFavoriteColor() } label: {
                    Image(systemName: model.activePalette.favorites.contains(InkColor(model.ink)) ? "star.fill" : "star")
                }.accessibilityLabel("Aggiungi o rimuovi il colore dai preferiti")
            }
            Text("Spessori recenti").font(.caption).foregroundStyle(.secondary)
            HStack {
                ForEach(widths, id: \.self) { value in
                    Button { model.chooseWidth(value) } label: {
                        VStack { Circle().fill(.primary).frame(width: min(18, value + 3), height: min(18, value + 3)); Text(value, format: .number.precision(.fractionLength(0...1))).font(.caption2) }.frame(width: 44, height: 44)
                    }.background(abs(model.thickness - value) < 0.01 ? Brand.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Slider(value: Binding(get: { model.thickness }, set: { model.chooseWidth($0) }), in: 0.5...12, step: 0.5)
                .accessibilityLabel("Spessore personalizzato")
        }.buttonStyle(.plain)
    }
    private var widths: [Double] {
        let recent = model.activePalette.recentWidths
        return Array((recent + [1.5, 3, 6].filter { !recent.contains($0) }).prefix(3))
    }
    private func swatches(_ title: String, colors: [InkColor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            if colors.isEmpty { Text("I colori usati appariranno qui").font(.caption2).foregroundStyle(.secondary) }
            HStack {
                ForEach(Array(colors.enumerated()), id: \.offset) { row in
                    Button { model.chooseInk(row.element.color) } label: {
                        Circle().fill(row.element.color).frame(width: 26, height: 26).overlay(Circle().stroke(.gray.opacity(0.5)))
                            .padding(5).overlay(Circle().stroke(InkColor(model.ink) == row.element ? Brand.accent : .clear, lineWidth: 2))
                    }.accessibilityLabel("Seleziona colore \(row.offset + 1)")
                }
            }
        }
    }
}

@MainActor
struct WorkspacePanel: View {
    @Bindable var model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Attività di questo quaderno") {
                    ForEach(model.workspaces.profiles) { profile in
                        Button { model.selectWorkspace(profile.id) } label: {
                            HStack { Text(profile.name); Spacer(); if profile.id == model.workspaces.selectedID { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.accent) } }
                        }.foregroundStyle(.primary)
                    }
                }
                Section("Personalizza \(model.currentWorkspace.name)") {
                    NavigationLink { tools } label: { Label("Strumenti preferiti", systemImage: "star") }
                    NavigationLink { layout } label: { Label("Toolbar e pannelli", systemImage: "rectangle.3.group") }
                    NavigationLink { gestures } label: { Label("Gesti e automatismi", systemImage: "hand.draw") }
                    NavigationLink { ToolPalettePanel(model: model).padding().navigationTitle("Colori per strumento") } label: { Label("Colori e spessori", systemImage: "paintpalette") }
                }
                Section { NavigationLink("Penne, preset e gomma") { WritingToolsPanel(model: model) } }
                Section("Salva una configurazione") {
                    TextField("Nome attività", text: $name)
                    Button("Duplica con questo nome", systemImage: "plus.square.on.square") { model.duplicateWorkspace(name: name); name = "" }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40 || model.workspaces.profiles.count >= 12)
                    Button("Rinomina attività", systemImage: "pencil") { model.editWorkspace { $0.name = name }; name = "" }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 40)
                    Button("Elimina questa configurazione", role: .destructive) { model.deleteWorkspace() }.disabled(model.workspaces.profiles.count <= 1)
                }
                Section { Text("Le configurazioni e i recenti restano in questo quaderno e nel suo backup. Le preferenze personali dell’app non vengono cambiate.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("Workspace")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
        }
    }
    private var tools: some View {
        List {
            Section("Preferiti · i primi tre compaiono in focus") {
                ForEach(model.currentWorkspace.favorites, id: \.self) { item in Label(item.title, systemImage: item.icon) }
                    .onMove { source, destination in model.editWorkspace { $0.favorites.move(fromOffsets: source, toOffset: destination) } }
                    .onDelete { source in model.editWorkspace { $0.favorites.remove(atOffsets: source) } }
            }
            Section("Aggiungi uno strumento") {
                ForEach(WorkspaceTool.allCases.filter { !model.currentWorkspace.favorites.contains($0) }, id: \.self) { item in
                    Button { model.editWorkspace { $0.favorites.append(item) } } label: { Label(item.title, systemImage: item.icon) }
                        .disabled(model.currentWorkspace.favorites.count >= 8)
                }
            }
        }.navigationTitle("Strumenti preferiti").toolbar { EditButton() }
    }
    private var layout: some View {
        Form {
            Section("Toolbar flottante") {
                Picker("Posizione", selection: binding(\.dock)) { ForEach(ToolbarDock.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            Section("Pannelli visibili") {
                Toggle("Barra delle pagine", isOn: binding(\.showPages))
                Toggle("Stato del salvataggio", isOn: binding(\.showStatus))
            }
        }.navigationTitle("Toolbar e pannelli")
    }
    private var gestures: some View {
        Form {
            Section("Input") {
                Toggle("Scrittura con il dito", isOn: $model.fingerDrawing)
                Text("Con questa opzione usa due dita per scorrere e per il doppio tocco.").font(.caption)
            }
            Section("Durante la scrittura") {
                Toggle("Tieni premuto per una forma precisa", isOn: binding(\.holdShapes))
                Text("Disegna una linea, un cerchio o un rettangolo e ferma la punta per circa 0,65 secondi prima di sollevarla. Un piccolo feedback conferma la correzione; puoi annullare il tratto corretto.").font(.caption)
                Toggle("Scarabocchio per cancellare", isOn: binding(\.scratchErase))
            }
            Section("Navigazione") {
                Toggle("Trascina oltre il fondo per avanzare", isOn: binding(\.pullNext))
                Text("Doppio tocco: larghezza del foglio / pagina intera. Con disegno tramite dito usa due dita.").font(.caption)
            }
        }.navigationTitle("Gesti e automatismi")
    }
    private func binding<Value>(_ path: WritableKeyPath<EditorWorkspace, Value>) -> Binding<Value> {
        Binding(get: { model.currentWorkspace[keyPath: path] }, set: { value in model.editWorkspace { $0[keyPath: path] = value } })
    }
}
