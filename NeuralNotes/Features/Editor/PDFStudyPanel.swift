import SwiftUI
import PDFKit
import Observation
import PencilKit
import UniformTypeIdentifiers
import NeuralNotesCore

@MainActor @Observable
final class PDFStudyController: NSObject {
    weak var view: PDFView?
    var file: String?
    var hasSelection = false
    var outline: [OutlineRow] = []
    var matches: [PDFSelection] = []
    var finding = false
    @ObservationIgnored private var searchTerm = ""
    @ObservationIgnored private weak var searchedDocument: PDFDocument?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let annotationOwner = "NeuralNotes.study.\(UUID())"
    struct OutlineRow: Identifiable {
        let id: UUID
        let label: String
        let destination: PDFDestination
        init(label: String, destination: PDFDestination) { id = UUID(); self.label = label; self.destination = destination }
    }
    func attach(_ view: PDFView) {
        guard self.view !== view || observer == nil else { return }
        detach()
        self.view = view
        observer = NotificationCenter.default.addObserver(forName: .PDFViewSelectionChanged, object: view, queue: .main) { [weak self, weak view] _ in
            Task { @MainActor [weak self, weak view] in
                self?.hasSelection = view?.currentSelection != nil
            }
        }
    }
    func syncMarkups(_ pages: [PageSnapshot]) {
        guard let document = view?.document, let file else { return }
        let stamp = pages.filter { $0.pdfFile == file }.map { "\($0.id):\($0.revision)" }.joined(separator: "|")
        guard stamp != markupStamp else { return }; markupStamp = stamp
        for index in 0..<document.pageCount {
            guard let source = document.page(at: index), let reference = source.pageRef,
                  let page = pages.first(where: { $0.pdfFile == file && $0.pdfIndex == index }) else { continue }
            for annotation in source.annotations where annotation.userName == annotationOwner { source.removeAnnotation(annotation) }
            let inverse = reference.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: page.width, height: page.height), rotate: 0, preserveAspectRatio: true)
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: page.height)).inverted()
            for markup in page.pdfMarkups ?? [] {
                let box = CGRect(x: markup.x, y: markup.y, width: markup.width, height: markup.height).applying(inverse)
                let annotation = PDFAnnotation(bounds: box, forType: markup.kind == .highlight ? .highlight : .underline, withProperties: nil)
                annotation.userName = annotationOwner; annotation.color = markup.kind == .highlight ? .systemYellow : .systemRed; source.addAnnotation(annotation)
            }
        }
    }
    @ObservationIgnored private var markupStamp = ""
    func detach() {
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        stopSearch()
    }
    private func stopSearch() {
        searchedDocument?.cancelFindString()
        NotificationCenter.default.removeObserver(self, name: .PDFDocumentDidFindMatch, object: nil)
        NotificationCenter.default.removeObserver(self, name: .PDFDocumentDidEndFind, object: nil)
        searchedDocument = nil; finding = false; matches = []; view?.highlightedSelections = nil
    }
    func search(_ query: String) {
        searchTerm = String(query.prefix(200)); stopSearch()
        guard searchTerm.count >= 2, let document = view?.document else { return }
        searchedDocument = document; finding = true
        NotificationCenter.default.addObserver(self, selector: #selector(found(_:)), name: .PDFDocumentDidFindMatch, object: document)
        NotificationCenter.default.addObserver(self, selector: #selector(ended(_:)), name: .PDFDocumentDidEndFind, object: document)
        document.beginFindString(searchTerm, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }
    @objc private func found(_ notification: Notification) {
        guard let document = notification.object as? PDFDocument, document === searchedDocument,
              let selection = notification.userInfo?["PDFDocumentFoundSelection"] as? PDFSelection else { return }
        guard matches.count < 200 else { document.cancelFindString(); finding = false; return }
        selection.color = .systemOrange.withAlphaComponent(0.45); matches.append(selection)
        view?.highlightedSelections = matches
    }
    @objc private func ended(_ notification: Notification) { if (notification.object as? PDFDocument) === searchedDocument { finding = false } }
    func load(file: String, package: URL, index: Int, external: URL? = nil) {
        guard let view, self.file != file || view.document == nil else { return }
        stopSearch()
        self.file = file; markupStamp = ""; view.document = PDFDocument(url: external ?? package.appendingPathComponent(file)); outline = []
        hasSelection = false
        var visitedNodes = 0
        func visit(_ node: PDFOutline, level: Int) {
            guard level <= 12, visitedNodes < 5000 else { return }; visitedNodes += 1
            if let destination = node.destination { outline.append(OutlineRow(label: String(repeating: "  ", count: max(0, min(6, level))) + (node.label ?? "Sezione"), destination: destination)) }
            for i in 0..<node.numberOfChildren { if let child = node.child(at: i) { visit(child, level: level + 1) } }
        }
        if let root = view.document?.outlineRoot { visit(root, level: -1) }
        if let page = view.document?.page(at: index) { view.go(to: page) }
        search(searchTerm)
    }
    func markups(kind: PDFMarkupKind, pages: [PageSnapshot]) -> [(UUID, PDFMarkup)] {
        guard let view, let selection = view.currentSelection, let document = view.document, let file else { return [] }
        var result: [(UUID, PDFMarkup)] = []
        for line in selection.selectionsByLine() {
            for source in line.pages {
                let index = document.index(for: source)
                guard let page = pages.first(where: { $0.pdfFile == file && $0.pdfIndex == index }), let reference = source.pageRef else { continue }
                let transform = reference.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: page.width, height: page.height), rotate: 0, preserveAspectRatio: true)
                    .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: page.height))
                let box = line.bounds(for: source).applying(transform)
                guard !box.isEmpty, !box.isNull else { continue }
                result.append((page.id, PDFMarkup(kind: kind, x: box.minX, y: box.minY, width: box.width, height: box.height, text: line.string ?? "")))

            }
        }
        return result
    }
}

@MainActor
private struct StudyPDFView: UIViewRepresentable {
    let controller: PDFStudyController
    let file: String
    let package: URL
    let index: Int
    let pages: [PageSnapshot]
    var external: URL?
    var conceptMode: Bool
    var onConcept: (String) -> Void
    func makeUIView(context: Context) -> ConceptPDFView {
        let view = ConceptPDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.conceptMode = conceptMode; view.onConcept = onConcept
        view.accessibilityIdentifier = "studyPDFView"; controller.attach(view); controller.load(file: file, package: package, index: index, external: external); controller.syncMarkups(pages)
        return view
    }
    func updateUIView(_ view: ConceptPDFView, context: Context) {
        view.conceptMode = conceptMode; view.onConcept = onConcept
        controller.attach(view); controller.load(file: file, package: package, index: index, external: external); controller.syncMarkups(pages)
    }
}

@MainActor
struct PDFStudyPanel: View {
    @Bindable var model: EditorViewModel
    @State private var controller = PDFStudyController()
    @State private var selectedFile = ""
    @State private var query = ""
    @State private var matchIndex = 0
    @State private var importing = false
    @State private var externalURL: URL?
    @State private var scoped = false
    @State private var conceptMode = false
    @State private var research: PDFResearchTerm?
    @State private var error: String?
    private var isExternal: Bool { externalURL?.absoluteString == selectedFile }
    private var files: [String] { Array(Set(model.pages.compactMap(\.pdfFile))).sorted() }
    var body: some View {
        VStack(spacing: 8) {
            header
            sourcePicker
            selectionCommands
            conceptCommands
            searchControls
            documentView
            documentActions
        }.padding(.vertical)
            .onAppear { selectedFile = model.page?.pdfFile ?? files.first ?? "" }
            .task(id: selectedFile + "|" + query) {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                matchIndex = 0; controller.search(query)
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                do { try openReference(result.get()) } catch { self.error = error.localizedDescription }
            }
            .sheet(item: $research) { item in PDFResearchSheet(model: model, term: item.text) }
            .onDisappear { controller.detach(); releaseReference() }
    }
    @ViewBuilder private var header: some View {
            HStack {
                Text("PDF e appunti").font(.headline)
                Spacer()
                Button("Apri PDF da File", systemImage: "folder") { importing = true }.labelStyle(.iconOnly).accessibilityIdentifier("openReferencePDF")
                Menu("Indice", systemImage: "list.bullet.indent") {
                    ForEach(controller.outline) { item in Button(item.label) { controller.view?.go(to: item.destination) } }
                }.disabled(controller.outline.isEmpty)
            }.padding(.horizontal)
    }
    @ViewBuilder private var sourcePicker: some View {
            if !files.isEmpty || externalURL != nil {
                Picker("PDF", selection: $selectedFile) {
                    ForEach(files, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0) }
                    if let externalURL { Text(externalURL.lastPathComponent + " · riferimento").tag(externalURL.absoluteString) }
                }.padding(.horizontal)
            }
    }
    @ViewBuilder private var selectionCommands: some View {
            HStack {
                Button("Copia", systemImage: "doc.on.doc") { UIPasteboard.general.string = controller.view?.currentSelection?.string }.disabled(!controller.hasSelection)
                Button("Evidenzia", systemImage: "highlighter") { mark(.highlight) }.disabled(!controller.hasSelection || isExternal)
                Button("Sottolinea", systemImage: "underline") { mark(.underline) }.disabled(!controller.hasSelection || isExternal)
            }.font(.caption).buttonStyle(.bordered)
    }
    @ViewBuilder private var conceptCommands: some View {
            HStack {
                Toggle("Cerchia / sottolinea con la Lente", isOn: $conceptMode).toggleStyle(.button)
                Button("Spiega e annota", systemImage: "note.text.badge.plus") { model.lensAsk(text: controller.view?.currentSelection?.string ?? "", fromSidePDF: true) }
                    .disabled(!controller.hasSelection)
                Button("Chiedi", systemImage: "sparkle.magnifyingglass") {
                    model.lensAnchor = nil; model.openLens(LensCardRequest(text: controller.view?.currentSelection?.string ?? "", fromSidePDF: true))
                }.disabled(!controller.hasSelection)
                Button("Web", systemImage: "globe") { lookup(controller.view?.currentSelection?.string ?? "") }.disabled(!controller.hasSelection)
            }.font(.caption).buttonStyle(.bordered).padding(.horizontal)
    }
    @ViewBuilder private var searchControls: some View {
            HStack {
                TextField("Cerca nel PDF", text: $query).textFieldStyle(.roundedBorder)
                if controller.finding { ProgressView().controlSize(.small) }
                Text("\(controller.matches.count)\(controller.matches.count == 200 ? "+" : "")").font(.caption.monospacedDigit())
                Button("Risultato precedente", systemImage: "chevron.up") { showMatch(-1) }.labelStyle(.iconOnly).disabled(controller.matches.isEmpty)
                Button("Risultato successivo", systemImage: "chevron.down") { showMatch(1) }.labelStyle(.iconOnly).disabled(controller.matches.isEmpty)
            }.padding(.horizontal)
    }
    @ViewBuilder private var documentView: some View {
            if !selectedFile.isEmpty {
                StudyPDFView(controller: controller, file: selectedFile, package: model.workspace.package, index: isExternal ? 0 : model.page?.pdfIndex ?? 0, pages: model.pages, external: isExternal ? externalURL : nil, conceptMode: conceptMode, onConcept: { model.lensAsk(text: $0, fromSidePDF: true) })
            } else { ContentUnavailableView("PDF di riferimento", systemImage: "doc", description: Text("Apri un PDF da File per leggerlo accanto agli appunti, senza importarlo nel quaderno.")) }
    }
    @ViewBuilder private var documentActions: some View {
        VStack(spacing: 8) {
            Button("Apri questa pagina nell’editor", systemImage: "arrow.left.to.line") {
                guard let view = controller.view, let source = view.currentPage, let document = view.document,
                      let page = model.pages.first(where: { $0.pdfFile == selectedFile && $0.pdfIndex == document.index(for: source) }) else { return }
                Task { await model.select(page) }
            }.disabled(isExternal || selectedFile.isEmpty)
            Button("Inserisci estratto con fonte negli appunti", systemImage: "text.badge.plus") { insertExcerpt() }.disabled(!controller.hasSelection)
            Text(isExternal ? "PDF aperto come riferimento: il file originale non viene modificato. Seleziona testo per inserirlo negli appunti. Seleziona un termine e premi Spiega e annota: la nota va nel quaderno. Con «Cerchia / sottolinea» usi Apple Pencil." : "Seleziona testo per copiarlo o evidenziarlo; Spiega e annota mette nel quaderno una nota con la spiegazione, Chiedi apre la scheda della Lente.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            if let error { Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal) }
        }
    }
    private func showMatch(_ delta: Int) {
        guard !controller.matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + controller.matches.count) % controller.matches.count
        let selection = controller.matches[matchIndex]; controller.view?.setCurrentSelection(selection, animate: true); controller.view?.go(to: selection)
    }
    private func insertExcerpt() {
        guard let view = controller.view, let selection = view.currentSelection, let text = selection.string,
              let source = selection.pages.first, let document = view.document else { return }
        let pdfIndex = document.index(for: source)
        guard pdfIndex != NSNotFound else { return }
        let name = isExternal ? externalURL?.lastPathComponent ?? "PDF" : "PDF"
        var element = TextElement(text: "«\(text.prefix(12000))»\n↗ Fonte: \(name) · pagina \(pdfIndex + 1)")
        if !isExternal, let page = model.pages.first(where: { $0.pdfFile == selectedFile && $0.pdfIndex == pdfIndex }) {
            element.pageLink = PageLinkTarget(documentID: model.workspace.documentID, pageID: page.id)
        }
        model.mutatePage("Inserisci estratto PDF") { $0.texts.append(element) }
    }
    private func lookup(_ text: String) {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { error = "Nessun testo selezionabile in questa zona: prova la selezione del PDF o importa il documento per usare l’OCR."; return }
        research = PDFResearchTerm(text: String(term.prefix(120))); error = nil
    }
    private func openReference(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        guard let document = PDFDocument(url: url), !document.isLocked, document.pageCount > 0 else {
            if access { url.stopAccessingSecurityScopedResource() }; throw PDFImportFailure.unreadable
        }
        releaseReference(); externalURL = url; scoped = access; selectedFile = url.absoluteString; error = nil
    }
    private func releaseReference() {
        if scoped { externalURL?.stopAccessingSecurityScopedResource() }
        scoped = false; externalURL = nil
    }
    private func mark(_ kind: PDFMarkupKind) {
        let marks = controller.markups(kind: kind, pages: model.pages)
        Task { await model.addPDFMarkups(marks) }
    }
}

@MainActor
extension EditorViewModel {
    func addPDFMarkups(_ marks: [(UUID, PDFMarkup)]) async {
        guard hasLease, !interactionBusy, !navigating, await flush() else { return }
        navigating = true; defer { navigating = false }
        do {
            let groups = Dictionary(grouping: marks, by: { $0.0 })
            for (id, values) in groups {
                guard var target = try await workspace.pages().first(where: { $0.id == id }) else { continue }
                let before = EditorContentState(page: target, drawing: nil)
                target.pdfMarkups = (target.pdfMarkups ?? []) + values.map(\.1)
                target.revision += 1
                let bytes = try await workspace.drawing(target) ?? PKDrawing().dataRepresentation()
                let saved = try await workspace.save(target, drawing: bytes)
                history.record(.content(before, EditorContentState(page: saved, drawing: nil)), label: "Evidenzia testo PDF")
                if page?.id == saved.id { page = saved }
            }
            pages = try await workspace.pages(); scheduleMaintenance()
        } catch { self.error = error.localizedDescription }
    }
}
