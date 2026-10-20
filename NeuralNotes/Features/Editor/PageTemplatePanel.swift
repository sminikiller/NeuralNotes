import SwiftUI
import PencilKit
import NeuralNotesCore

struct PageTemplateControls: View {
    @Binding var template: PageTemplate
    var allowFormat = true
    var body: some View {
        Section("Carta") {
            Picker("Tipo", selection: $template.paper) {
                ForEach(PaperStyle.allCases, id: \.self) { style in Text(style.title).tag(style) }
            }.pickerStyle(.segmented)
            Picker("Colore del foglio", selection: $template.appearance.tone) {
                ForEach(PaperTone.allCases, id: \.self) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            HStack {
                let rgb = template.appearance.tone.rgb
                RoundedRectangle(cornerRadius: 8).fill(Color(red: rgb.0, green: rgb.1, blue: rgb.2))
                    .frame(width: 44, height: 55).overlay(Image(systemName: paperIcon).foregroundStyle(.gray))
                Text("\(template.paper.title) · \(template.appearance.tone.title)")
            }
            Stepper("Passo \(Int(template.appearance.spacing)) pt", value: $template.appearance.spacing, in: 12...64, step: 2)
                .disabled(template.paper == .plain)
            Toggle("Margine sinistro", isOn: $template.appearance.margin)
            if template.appearance.tone == .slate { Text("Per scrivere sull’ardesia scegli un inchiostro chiaro.").font(.caption) }
        }
        Section("Formato") {
            Picker("Dimensione", selection: $template.format) {
                ForEach(PageFormat.allCases, id: \.self) { format in Text(format.title).tag(format) }
            }
            Toggle("Orizzontale", isOn: $template.landscape)
        }.disabled(!allowFormat)
    }
    private var paperIcon: String {
        switch template.paper { case .plain: return "doc"; case .ruled: return "line.3.horizontal"
        case .grid: return "square.grid.3x3"; case .dotted: return "circle.grid.3x3" }
    }
}

@MainActor
struct PageTemplatePanel: View {
    let model: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var template = PageTemplate()
    @State private var useForNext = true
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                PageTemplateControls(template: $template)
                Section("Navigazione delle pagine") {
                    Picker("Modalità", selection: Binding(get: { model.pageNavigation }, set: { model.pageNavigation = $0 })) {
                        ForEach(PageNavigationMode.allCases, id: \.self) { mode in Label(mode.title, systemImage: mode.icon).tag(mode) }
                    }.accessibilityIdentifier("pageNavigationMode")
                    Text("Il canvas usa tutta l’area dell’editor. Verticale: fogli uno dopo l’altro con poco distacco e scorrimento continuo. Orizzontale: voltata del foglio come un libro, a pagina intera. Scorri con le dita; con scrittura tramite dito usa due dita. La scelta viene ricordata per questo quaderno.").font(.caption)
                }
                Section("Gesti rapidi") {
                    Toggle("Trascina oltre il fondo per avanzare", isOn: Binding(get: { model.currentWorkspace.pullNext }, set: { value in model.editWorkspace { $0.pullNext = value } }))
                    Text("In Pagina singola, trascina con le dita oltre il bordo inferiore per avanzare o creare una pagina. Nelle modalità di sfoglio usa + Pagina per aggiungere un foglio.").font(.caption)
                    Toggle("Scarabocchio per cancellare", isOn: Binding(get: { model.currentWorkspace.scratchErase }, set: { value in model.editWorkspace { $0.scratchErase = value } }))
                    Text("Con Penna, ripassa avanti e indietro o annerisci con più giri continui la zona da cancellare. Solleva Pencil per applicare; puoi annullare. Immagini e forme restano intatte. Per i gesti di modifica del testo di iPadOS usa Testo con Pencil.").font(.caption)
                    Text("Doppio tocco: larghezza del foglio / pagina intera. Se disegni con il dito, usa due dita. I gesti si salvano nel workspace di questo quaderno.").font(.caption)
                }
                Section {
                    Toggle("Usa anche per le nuove pagine", isOn: $useForNext)
                    Text("Ogni pagina può avere un modello diverso. Cambiare formato ridimensiona insieme contenuti e inchiostro; puoi annullare.").font(.caption)
                    if model.page?.pdfFile != nil { Text("La pagina PDF mantiene il suo originale. Il modello scelto si applica alle nuove pagine vuote.").font(.caption) }
                }
            }.disabled(busy)
            .navigationTitle("Carta e formato")
            .task {
                if let page = model.page {
                    template.paper = page.paper
                    template.appearance = page.appearance ?? PaperAppearance(spacing: page.paper == .ruled ? 32 : 24)
                    template.landscape = page.width > page.height
                    if let format = PageFormat.allCases.first(where: { format in
                        let size = format.size
                        let width = template.landscape ? size.height : size.width
                        let height = template.landscape ? size.width : size.height
                        return abs(page.width - width) < 1 && abs(page.height - height) < 1
                    }) { template.format = format }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Applica") {
                    Task { busy = true; if await model.applyTemplate(template, useForNext: useForNext) { dismiss() }; busy = false }
                }.disabled(busy) }
            }
        }
    }
}

@MainActor
extension EditorViewModel {
    func applyTemplate(_ template: PageTemplate, useForNext: Bool) async -> Bool {
        guard hasLease, !navigating, !loading, !hasActiveStroke, let current = page else { return false }
        guard template.appearance.isValid else { return false }
        navigating = true; defer { navigating = false }
        guard await flush() else { return false }
        do {
            if useForNext { try await workspace.setDefaultPageTemplate(template) }
            if current.pdfFile == nil {
                let before = captureEdit(ink: true)
                let geometry = template.makePage()
                // Fit uniformly: changing paper proportions must not stretch
                // photographs, handwriting or circles.
                let fontScale: Double = min(geometry.width / current.width, geometry.height / current.height)
                let sx = fontScale, sy = fontScale
                page?.width = geometry.width; page?.height = geometry.height
                page?.paper = template.paper; page?.appearance = template.appearance
                if var value = page {
                    for i in value.texts.indices {
                        value.texts[i].x *= sx; value.texts[i].y *= sy; value.texts[i].width *= sx
                        if value.texts[i].rtf != nil {
                            let rich = NSMutableAttributedString(attributedString: RichText.attributed(value.texts[i]))
                            rich.enumerateAttribute(.font, in: NSRange(location: 0, length: rich.length)) { font, range, _ in
                                if let font = font as? UIFont { rich.addAttribute(.font, value: font.withSize(min(1000, max(1, font.pointSize * fontScale))), range: range) }
                            }
                            value.texts[i].rtf = RichText.data(rich)
                        }
                        value.texts[i].fontSize = min(1000, max(1, value.texts[i].fontSize * fontScale))
                    }
                    for i in value.images.indices {
                        value.images[i].x *= sx; value.images[i].y *= sy; value.images[i].width *= sx; value.images[i].height *= sy
                    }
                    if var shapes = value.shapes {
                        for i in shapes.indices {
                            shapes[i].x *= sx; shapes[i].y *= sy; shapes[i].width *= sx; shapes[i].height *= sy
                            shapes[i].lineWidth = min(200, max(0.1, shapes[i].lineWidth * fontScale))
                        }
                        value.shapes = shapes
                    }
                    page = value
                }
                canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(scaleX: CGFloat(sx), y: CGFloat(sy)))
                recordEdit(before, label: "Carta e formato"); drawingChanged()
                return await flush()
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
