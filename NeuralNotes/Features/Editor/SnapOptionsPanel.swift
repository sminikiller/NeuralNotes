import SwiftUI
import NeuralNotesCore

@MainActor
struct SnapOptionsPanel: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        Form {
            Section("Aggancio") {
                Toggle("Agli oggetti e alla pagina", isOn: Binding(get: { model.snapPreferences.objectsEnabled }, set: { value in model.editSnapPreferences { $0.objects = value } }))
                    .accessibilityIdentifier("snapObjectsToggle")
                Toggle("Alla griglia", isOn: Binding(get: { gridEnabled }, set: { value in model.editSnapPreferences { $0.grid = value } }))
                    .accessibilityIdentifier("snapGridToggle")
                Toggle("Mostra linee guida", isOn: Binding(get: { model.snapPreferences.guidesEnabled }, set: { value in model.editSnapPreferences { $0.guides = value } }))
                Toggle("Mantieni proporzioni", isOn: Binding(get: { model.snapPreferences.keepProportions ?? false }, set: { value in model.editSnapPreferences { $0.keepProportions = value } }))
            }
            Section {
                Text("Trascina vicino a bordi o centri. Due dita appoggiate, oppure il tasto ⌥, sospendono l’aggancio durante il gesto.")
                Text("Sui fogli con griglia si usa il passo della carta; sulle altre carte, una griglia invisibile da 8 punti. Le impostazioni restano in questa attività del quaderno.")
            }.font(.callout).foregroundStyle(.secondary)
        }.navigationTitle("Aggancio")
    }
    private var gridEnabled: Bool {
        guard let page = model.page else { return false }
        return SnapGrid.forPaper(page.paper, appearance: page.appearance, enabled: model.snapPreferences.grid) != nil
    }
}
