import SwiftUI

// These are app actions, not UIKit target/action selectors.
enum PageTextAction { case bold, italic, underline, heading, body, bullet, checklist, black, blue, red, indent, outdent }

@MainActor
struct PageTextControls: View {
    let model: EditorViewModel
    private var input: CanvasTextInput? { (model.pagePresenter as? CanvasHost)?.textInput }
    var body: some View {
        Group {
            if model.editingTextID == nil { Text("Tocca il foglio e scrivi con Pencil.").font(.caption).padding(12) }
            else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button { input?.format(.bold) } label: { Image(systemName: "bold").frame(width: 40, height: 44) }.accessibilityLabel("Grassetto")
                        Button { input?.format(.italic) } label: { Image(systemName: "italic").frame(width: 40, height: 44) }.accessibilityLabel("Corsivo")
                        Button { input?.format(.underline) } label: { Image(systemName: "underline").frame(width: 40, height: 44) }.accessibilityLabel("Sottolineato")
                        Menu("Aa") {
                            Button("Titolo") { input?.format(.heading) }; Button("Corpo") { input?.format(.body) }
                            Button("Elenco") { input?.format(.bullet) }; Button("Checklist") { input?.format(.checklist) }
                            Button("Aumenta rientro") { input?.format(.indent) }; Button("Riduci rientro") { input?.format(.outdent) }
                            Menu("Colore") {
                                Button("Nero") { input?.format(.black) }; Button("Blu") { input?.format(.blue) }; Button("Rosso") { input?.format(.red) }
                            }
                        }.frame(width: 40, height: 44)
                        Button { input?.showKeyboard() } label: { Image(systemName: "keyboard").frame(width: 44, height: 44) }.accessibilityLabel("Apri tastiera")
                        Button("Fine") { input?.finishEditing(); model.endTextEdit() }.padding(.horizontal, 8).frame(height: 44).accessibilityIdentifier("pageTextDone")
                    }.padding(.horizontal, 6)
                }.frame(maxWidth: 340)
            }
        }
        .foregroundStyle(Brand.accent).buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.gray.opacity(0.25)))
    }
}
