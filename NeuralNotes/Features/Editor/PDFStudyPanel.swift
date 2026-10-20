import SwiftUI
import PDFKit
import Observation
import PencilKit
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
            Task { @MainActor in self?.hasSelection = view?.currentSelection != nil }
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
    func load(file: String, package: URL, index: Int) {
        guard let view, self.file != file || view.document == nil else { return }
        stopSearch()
        self.file = file; markupStamp = ""; view.document = PDFDocument(url: package.appendingPathComponent(file)); outline = []
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
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.displayDirection = .vertical
        view.accessibilityIdentifier = "studyPDFView"; controller.attach(view); controller.load(file: file, package: package, index: index); controller.syncMarkups(pages)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) { controller.attach(view); controller.load(file: file, package: package, index: index); controller.syncMarkups(pages) }
}

@MainActor
struct PDFStudyPanel: View {
    @Bindable var model: EditorViewModel
    @State private var controller = PDFStudyController()
    @State private var selectedFile = ""
    @State private var query = ""
    @State private var matchIndex = 0
    private var files: [String] { Array(Set(model.pages.compactMap(\.pdfFile))).sorted() }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PDF e appunti").font(.headline)
                Spacer()
                Menu("Indice", systemImage: "list.bullet.indent") {
                    ForEach(controller.outline) { item in Button(item.label) { controller.view?.go(to: item.destination) } }
                }.disabled(controller.outline.isEmpty)
            }.padding(.horizontal)
            if files.count > 1 {
                Picker("PDF", selection: $selectedFile) { ForEach(files, id: \.self) { Text(URL(fileURLWithPath: $0).lastPathComponent).tag($0) } }.padding(.horizontal)
            }
            HStack {
                Button("Copia", systemImage: "doc.on.doc") { UIPasteboard.general.string = controller.view?.currentSelection?.string }.disabled(!controller.hasSelection)
                Button("Evidenzia", systemImage: "highlighter") { mark(.highlight) }.disabled(!controller.hasSelection)
                Button("Sottolinea", systemImage: "underline") { mark(.underline) }.disabled(!controller.hasSelection)
            }.font(.caption).buttonStyle(.bordered)
            HStack {
                TextField("Cerca nel PDF", text: $query).textFieldStyle(.roundedBorder)
                if controller.finding { ProgressView().controlSize(.small) }
                Text("\(controller.matches.count)\(controller.matches.count == 200 ? "+" : "")").font(.caption.monospacedDigit())
                Button("Risultato precedente", systemImage: "chevron.up") { showMatch(-1) }.labelStyle(.iconOnly).disabled(controller.matches.isEmpty)
                Button("Risultato successivo", systemImage: "chevron.down") { showMatch(1) }.labelStyle(.iconOnly).disabled(controller.matches.isEmpty)
            }.padding(.horizontal)
            if !selectedFile.isEmpty {
                StudyPDFView(controller: controller, file: selectedFile, package: model.workspace.package, index: model.page?.pdfIndex ?? 0, pages: model.pages)
            } else { ContentUnavailableView("Nessun PDF", systemImage: "doc", description: Text("Importa un PDF nel quaderno per leggerlo accanto agli appunti.")) }
            Button("Apri questa pagina nell’editor", systemImage: "arrow.left.to.line") {
                guard let view = controller.view, let source = view.currentPage, let document = view.document,
                      let page = model.pages.first(where: { $0.pdfFile == selectedFile && $0.pdfIndex == document.index(for: source) }) else { return }
                Task { await model.select(page) }
            }
            Button("Inserisci estratto con fonte negli appunti", systemImage: "text.badge.plus") { insertExcerpt() }.disabled(!controller.hasSelection)
            Text("Seleziona il testo nel PDF per copiarlo o evidenziarlo. Gli appunti a sinistra restano scrivibili.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
        }.padding(.vertical)
            .onAppear { selectedFile = model.page?.pdfFile ?? files.first ?? "" }
            .task(id: selectedFile + "|" + query) {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                matchIndex = 0; controller.search(query)
            }
            .onDisappear { controller.detach() }
    }
    private func showMatch(_ delta: Int) {
        guard !controller.matches.isEmpty else { return }
        matchIndex = (matchIndex + delta + controller.matches.count) % controller.matches.count
        let selection = controller.matches[matchIndex]; controller.view?.setCurrentSelection(selection, animate: true); controller.view?.go(to: selection)
    }
    private func insertExcerpt() {
        guard let view = controller.view, let selection = view.currentSelection, let text = selection.string,
              let source = selection.pages.first, let document = view.document,
              let pageIndex = model.pages.firstIndex(where: { $0.pdfFile == selectedFile && $0.pdfIndex == document.index(for: source) }) else { return }
        var element = TextElement(text: "«\(text.prefix(12000))»\n↗ Fonte: PDF · pagina \(pageIndex + 1)")
        element.pageLink = PageLinkTarget(documentID: model.workspace.documentID, pageID: model.pages[pageIndex].id)
        model.mutatePage("Inserisci estratto PDF") { $0.texts.append(element) }
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
