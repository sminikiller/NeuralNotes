import UIKit
import CoreText
import NeuralNotesCore

/// The words of a page with their boxes, for the Lens: the PDF text layer when there
/// is one, otherwise the OCR of the drawn page, plus the typed text boxes. Reading a
/// page takes a moment, so it is prepared ahead and kept for the pages used recently.
@MainActor
final class PageWordIndex {
    static let shared = PageWordIndex()
    private let recognize: @Sendable (Data) async throws -> [PageWord]
    init(recognize: @escaping @Sendable (Data) async throws -> [PageWord] = { try await VisionOCRService().words(image: $0) }) {
        self.recognize = recognize
    }
    private var cache: [String: [PageWord]] = [:]
    private var order: [String] = []
    private var running: Set<String> = []
    private var readingEpochs: [String: UUID] = [:]
    private var refreshRequested = Set<String>()
    private var digitalWords: [String: [PageWord]] = [:]
    private var digitalOrder: [String] = []
    private var digitalRunning = Set<String>()
    private var epochs: [UUID: UUID] = [:]

    func invalidate(_ page: PageSnapshot, preservingRecognizedWords: Bool = false) {
        if preservingRecognizedWords { return }
        if page.pdfFile != nil {
            // Digital text is immutable; OCR of a scan can change with ink or
            // images. Highlighting itself must not discard recognized words.
            if digitalWords[key(page)]?.isEmpty != false, !preservingRecognizedWords {
                epochs[page.id] = UUID(); cache[key(page)] = nil
            }
            return
        }
        epochs[page.id] = UUID()
    }
    /// A save advances the storage revision, not the visual content. Keep the
    /// current epoch's words so highlighting does not repeatedly restart OCR.
    func didSave(_ previous: PageSnapshot, as saved: PageSnapshot) {
        guard previous.id == saved.id, previous.pdfFile == nil, saved.pdfFile == nil,
              let words = cache[key(previous)] else { return }
        store(key(saved), words)
    }
    /// File-backed bulk history does not load page headers onto the UI thread.
    /// The immutable digital PDF layer remains reusable, while visual OCR expires.
    func invalidatePage(_ id: UUID) {
        epochs[id] = UUID()
        let token = "|\(id)|"
        for value in Array(cache.keys) where value.contains(token) && digitalWords[value]?.isEmpty != false { cache[value] = nil }
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
    func isPreparing(_ page: PageSnapshot) -> Bool { running.contains { $0.contains("|\(page.id)|") } }

    func pdfWords(_ page: PageSnapshot) -> [PageWord] { page.pdfFile == nil ? [] : digitalWords[key(page)] ?? [] }
    func markerWords(_ page: PageSnapshot) -> [PageWord] {
        guard page.pdfFile != nil else { return [] }
        let digital = pdfWords(page)
        return digital.isEmpty ? cache[key(page)] ?? [] : digital
    }
    func isPDFMarkerReady(_ page: PageSnapshot) -> Bool { digitalWords[key(page)] != nil }
    func hasRecognizedScanWords(_ page: PageSnapshot) -> Bool {
        page.pdfFile != nil && digitalWords[key(page)]?.isEmpty != false && cache[key(page)]?.isEmpty == false
    }
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
        guard cache[cacheKey] == nil else { return }
        if running.contains(cacheKey) {
            // A PDF keeps one cache key across edits. Remember an explicit
            // request for its new epoch instead of silently dropping it.
            if readingEpochs[cacheKey] != epochs[page.id] { refreshRequested.insert(cacheKey) }
            return
        }
        running.insert(cacheKey)
        let ink = model.canvas.drawing
        let generation = epochs[page.id]
        readingEpochs[cacheKey] = generation
        Task {
            defer {
                running.remove(cacheKey)
                readingEpochs[cacheKey] = nil
                let refresh = refreshRequested.remove(cacheKey) != nil
                if refresh, let current = model.page, current.id == page.id, model.hasLease {
                    prepare(current, model: model)
                }
                // Reprepare a genuinely newer visual epoch after a stale
                // result; never recursively retry an unchanged failed read.
                let changedWhileReading = epochs[page.id] != generation
                if cache[cacheKey] != nil || changedWhileReading, model.tool == .marker, !model.hasActiveStroke { model.configureTool() }
            }
            do {
            var words: [PageWord] = []
            if let file = page.pdfFile, let index = page.pdfIndex, let url = try? await model.workspace.url(file) {
                words = try await PDFTextReader.shared.words(url: url, index: index, pageWidth: page.width, pageHeight: page.height)
                storeDigital(cacheKey, words)
            }
            guard model.page?.id == page.id, self.key(page) == cacheKey, epochs[page.id] == generation else { return }
            if words.isEmpty {
                // Handwriting, scans and photos: word boxes from the OCR of the drawn page.
                var visual = page; visual.texts = []; visual.tapes = []; visual.shapes = []; visual.connectors = []
                let image = DocumentServices.image(page: visual, drawing: ink, workspace: model.workspace, maxDimension: 2200)
                if let data = image.pngData() {
                    let found = try await recognize(data)
                    let width = CGFloat(page.width), height = CGFloat(page.height)
                    words = found.map { word in
                        PageWord(text: word.text, rect: CGRect(x: word.rect.minX * width, y: word.rect.minY * height,
                                                               width: word.rect.width * width, height: word.rect.height * height))
                    }
                }
            }
            guard model.page?.id == page.id, self.key(page) == cacheKey, epochs[page.id] == generation else { return }
            store(cacheKey, words)
            // OCR may finish after a metadata-only autosave. A real content
            // edit changes the epoch and was rejected by the guard above.
            if let current = model.page, current.id == page.id, epochs[page.id] == generation {
                store(key(current), words)
            }
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
        var fonts: [String: CTFont] = [:]
        for token in PageWords.tokens(in: value.string) {
            let glyphs = layout.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
            // TextKit's line box includes the entire ascender/descender band.
            // With tightly spaced lines its bottom can already be inside the
            // next line. Use actual glyph ink bounds so an underline selects
            // its own word, just as it does with the PDF's word rectangles.
            var box = CGRect.null
            for i in glyphs.location..<NSMaxRange(glyphs) {
                let character = layout.characterIndexForGlyph(at: i)
                guard character < value.length else { continue }
                let font = value.attribute(.font, at: character, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: text.fontSize)
                let key = "\(font.fontName)|\(font.pointSize)"
                let native = fonts[key] ?? CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
                fonts[key] = native
                let index = layout.glyph(at: i)
                guard index <= UInt16.max else { continue }
                var glyph = CGGlyph(index)
                let bounds = CTFontGetBoundingRectsForGlyphs(native, .horizontal, &glyph, nil, 1)
                guard !bounds.isNull, !bounds.isEmpty else { continue }
                let line = layout.lineFragmentRect(forGlyphAt: i, effectiveRange: nil)
                let at = layout.location(forGlyphAt: i)
                let ink = CGRect(x: line.minX + at.x + bounds.minX, y: line.minY + at.y - bounds.maxY,
                                 width: bounds.width, height: bounds.height)
                box = box.union(ink)
            }
            if box.isNull { box = layout.boundingRect(forGlyphRange: glyphs, in: container) }
            guard box.width > 0, box.height > 0 else { continue }
            let rotated = box.offsetBy(dx: CGFloat(text.x), dy: CGFloat(text.y)).applying(RichText.rotation(text, pageHeight: pageHeight))
            words.append(PageWord(text: string.substring(with: token.range), rect: rotated))
        }
        typedCache.setObject(TypedEntry(text: text, height: pageHeight, words: words), forKey: text.id as NSUUID, cost: words.count * 120)
        return words
    }
}
