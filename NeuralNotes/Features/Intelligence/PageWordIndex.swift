import UIKit
import NeuralNotesCore

/// The words of a page with their boxes, for the Lens: the PDF text layer when there
/// is one, otherwise the OCR of the drawn page, plus the typed text boxes. Reading a
/// page takes a moment, so it is prepared ahead and kept for the pages used recently.
@MainActor
final class PageWordIndex {
    static let shared = PageWordIndex()
    private var cache: [String: [PageWord]] = [:]
    private var order: [String] = []
    private var running: Set<String> = []
    private var digitalWords: [String: [PageWord]] = [:]
    private var digitalOrder: [String] = []
    private var digitalRunning = Set<String>()
    private var epochs: [UUID: UUID] = [:]

    func invalidate(_ page: PageSnapshot, preservingRecognizedWords: Bool = false) {
        if page.pdfFile != nil {
            // Digital text is immutable; OCR of a scan can change with ink or
            // images. Highlighting itself must not discard recognized words.
            if digitalWords[key(page)]?.isEmpty != false, !preservingRecognizedWords { cache[key(page)] = nil }
            return
        }
        epochs[page.id] = UUID()
    }

    /// Word groups in reading order: the text layer or OCR first, then each typed box.
    /// Lens notes are answers, not the student's material, and are left out.
    func groups(for page: PageSnapshot) -> [[PageWord]] {
        var groups: [[PageWord]] = []
        if let base = cache[key(page)], !base.isEmpty { groups.append(base) }
        for text in page.texts where text.lensNote == nil && !text.text.isEmpty {
            let words = Self.typedWords(text, pageHeight: page.height)
            if !words.isEmpty { groups.append(words) }
        }
        for shape in page.shapes ?? [] {
            if let label = DiagramLabels.shape(shape, page: page) { groups.append(labelWords(label, page: page)) }
        }
        if page.connectors?.isEmpty == false {
            let objects = DiagramObjects.make(page)
            for connector in page.connectors ?? [] {
                if let label = DiagramLabels.connector(connector, objects: objects, page: page) { groups.append(labelWords(label, page: page)) }
            }
        }
        return groups
    }
    private func labelWords(_ label: DiagramLabelLayout, page: PageSnapshot) -> [PageWord] {
        Self.typedWords(label.text, pageHeight: max(page.height, label.box.maxY)).compactMap { word in
            let clipped = word.rect.intersection(label.box)
            guard !clipped.isNull, !clipped.isEmpty else { return nil }
            return PageWord(text: word.text, rect: clipped.applying(label.transform))
        }
    }

    /// The text layer or the OCR of the page has been read (possibly finding nothing).
    func isReady(_ page: PageSnapshot) -> Bool { cache[key(page)] != nil }

    func pdfWords(_ page: PageSnapshot) -> [PageWord] { page.pdfFile == nil ? [] : digitalWords[key(page)] ?? [] }
    func markerWords(_ page: PageSnapshot) -> [PageWord] {
        guard page.pdfFile != nil else { return [] }
        let digital = pdfWords(page)
        return digital.isEmpty ? cache[key(page)] ?? [] : digital
    }
    func isPDFMarkerReady(_ page: PageSnapshot) -> Bool { digitalWords[key(page)] != nil }
    /// The marker needs the immutable digital layer only, without starting OCR
    /// of a large scanned PDF while the user is trying to write.
    func preparePDFMarker(_ page: PageSnapshot, model: EditorViewModel) {
        let cacheKey = key(page)
        guard let file = page.pdfFile, let index = page.pdfIndex, digitalWords[cacheKey] == nil, !digitalRunning.contains(cacheKey) else { return }
        digitalRunning.insert(cacheKey)
        Task {
            defer { digitalRunning.remove(cacheKey) }
            guard let url = try? await model.workspace.url(file),
                  let words = try? await PDFTextReader.shared.words(url: url, index: index, pageWidth: page.width, pageHeight: page.height),
                  model.page?.id == page.id else { return }
            storeDigital(cacheKey, words)
            // An empty digital layer does not mean OCR of the scan completed.
            // Keep the Lens cache unprepared so it can still recognize the image.
            if !words.isEmpty, cache[cacheKey] == nil { store(cacheKey, words) }
            if model.tool == .marker, !model.hasActiveStroke { model.configureTool() }
        }
    }

    func prepare(_ page: PageSnapshot, model: EditorViewModel) {
        let cacheKey = key(page)
        guard cache[cacheKey] == nil, !running.contains(cacheKey) else { return }
        running.insert(cacheKey)
        let ink = model.canvas.drawing
        Task {
            defer { running.remove(cacheKey) }
            do {
            var words: [PageWord] = []
            if let file = page.pdfFile, let index = page.pdfIndex, let url = try? await model.workspace.url(file) {
                words = try await PDFTextReader.shared.words(url: url, index: index, pageWidth: page.width, pageHeight: page.height)
                storeDigital(cacheKey, words)
            }
            guard model.page?.id == page.id, self.key(page) == cacheKey else { return }
            if words.isEmpty {
                // Handwriting, scans and photos: word boxes from the OCR of the drawn page.
                var visual = page; visual.texts = []; visual.tapes = []; visual.shapes = []; visual.connectors = []
                let image = DocumentServices.image(page: visual, drawing: ink, workspace: model.workspace, maxDimension: 2200)
                if let data = image.pngData() {
                    let found = try await VisionOCRService().words(image: data)
                    let width = CGFloat(page.width), height = CGFloat(page.height)
                    words = found.map { word in
                        PageWord(text: word.text, rect: CGRect(x: word.rect.minX * width, y: word.rect.minY * height,
                                                               width: word.rect.width * width, height: word.rect.height * height))
                    }
                }
            }
            guard model.page?.id == page.id, self.key(page) == cacheKey else { return }
            store(cacheKey, words)
            if model.tool == .marker, !model.hasActiveStroke { model.configureTool() }
            } catch { /* No empty cache on a transient error; the next gesture may retry. */ }
        }
    }

    private func store(_ key: String, _ words: [PageWord]) {
        cache[key] = words; order.removeAll { $0 == key }; order.append(key)
        if order.count > 24 { cache[order.removeFirst()] = nil }
    }
    private func storeDigital(_ key: String, _ words: [PageWord]) {
        digitalWords[key] = words; digitalOrder.removeAll { $0 == key }; digitalOrder.append(key)
        if digitalOrder.count > 24 { digitalWords[digitalOrder.removeFirst()] = nil }
    }

    /// The text layer of a PDF page never changes; the OCR of a drawn page follows its revision.
    private func key(_ page: PageSnapshot) -> String {
        if let file = page.pdfFile, let index = page.pdfIndex { return "pdf|\(page.id)|\(file)|\(index)|\(page.width)|\(page.height)" }
        return "ocr|\(page.id)|\(page.revision)|\(epochs[page.id]?.uuidString ?? "")"
    }

    private final class TypedEntry {
        let text: TextElement, height: Double, words: [PageWord]
        init(text: TextElement, height: Double, words: [PageWord]) { self.text = text; self.height = height; self.words = words }
    }
    private static let typedCache: NSCache<NSUUID, TypedEntry> = {
        let value = NSCache<NSUUID, TypedEntry>(); value.countLimit = 200; value.totalCostLimit = 2 * 1024 * 1024; return value
    }()

    /// Words of a typed box, laid out as the page draws it.
    static func typedWords(_ text: TextElement, pageHeight: Double) -> [PageWord] {
        if let cached = typedCache.object(forKey: text.id as NSUUID), cached.text == text, cached.height == pageHeight { return cached.words }
        let value = RichText.attributed(text)
        let storage = NSTextStorage(attributedString: value), layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: text.width, height: max(1, pageHeight - text.y)))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        let string = value.string as NSString
        var words: [PageWord] = []
        for token in PageWords.tokens(in: value.string) {
            let glyphs = layout.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
            let box = layout.boundingRect(forGlyphRange: glyphs, in: container)
            guard box.width > 0, box.height > 0 else { continue }
            let rotated = box.offsetBy(dx: CGFloat(text.x), dy: CGFloat(text.y)).applying(RichText.rotation(text, pageHeight: pageHeight))
            words.append(PageWord(text: string.substring(with: token.range), rect: rotated))
        }
        typedCache.setObject(TypedEntry(text: text, height: pageHeight, words: words), forKey: text.id as NSUUID, cost: words.count * 120)
        return words
    }
}
