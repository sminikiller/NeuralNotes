import UIKit
import NeuralNotesCore

struct SearchFocusRequest: Equatable { var pageID: UUID; var query: String }

@MainActor
extension RichText {
    static func matchingRects(_ query: String, in text: TextElement, pageHeight: Double) -> [CGRect] {
        guard !query.isEmpty else { return [] }
        if text.lensNote?.isCollapsed == true {
            return text.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) == nil ? [] : [bounds(text, pageHeight: pageHeight)]
        }
        let value = attributed(text), storage = NSTextStorage(attributedString: value), layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: text.width, height: max(1, pageHeight - text.y)))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        let string = value.string as NSString
        var start = 0, boxes: [CGRect] = []
        while start < string.length, boxes.count < 80 {
            let range = string.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: start, length: string.length - start))
            guard range.location != NSNotFound, range.length > 0 else { break }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { box, _ in
                boxes.append(box.offsetBy(dx: text.x, dy: text.y).applying(rotation(text, pageHeight: pageHeight)))
            }
            start = range.location + range.length
        }
        return boxes
    }
}

@MainActor
final class SearchHighlightOverlay: UIView {
    private let highlights = CAShapeLayer()
    private var generation = ""
    private var job: Task<Void, Never>?
    init() {
        super.init(frame: .zero); isUserInteractionEnabled = false; backgroundColor = .clear; isOpaque = false; isHidden = true
        highlights.fillColor = UIColor.systemYellow.withAlphaComponent(0.3).cgColor
        highlights.strokeColor = UIColor.systemOrange.withAlphaComponent(0.7).cgColor; highlights.lineWidth = 1
        layer.addSublayer(highlights); accessibilityIdentifier = "searchPageHighlight"
    }
    required init?(coder: NSCoder) { nil }
    func update(_ host: CanvasHost) {
        guard let model = host.model, let request = model.searchFocus, let page = model.page, page.id == request.pageID else {
            job?.cancel(); generation = ""; highlights.path = nil; isHidden = true; return
        }
        bounds = host.surface.bounds; transform = host.surface.transform; center = host.surface.center
        let key = "\(page.id)|\(page.revision)|\(request.query)"
        guard generation != key else { return }; generation = key; job?.cancel()
        let boxes = page.texts.flatMap { RichText.matchingRects(request.query, in: $0, pageHeight: page.height) }
        if !boxes.isEmpty { show(boxes, host: host) }
        else { highlights.path = nil; isHidden = true }
        job = Task { [weak self, weak host] in
            guard let self, let host else { return }
            do {
                try Task.checkCancellation()
                // A page made from a PDF: exact boxes from its text layer, before any OCR.
                if let file = page.pdfFile, let index = page.pdfIndex, let url = try? await model.workspace.url(file) {
                    let rects = (try? await PDFTextReader.shared.matches(request.query, url: url, index: index, pageWidth: page.width, pageHeight: page.height)) ?? []
                    try Task.checkCancellation()
                    guard self.generation == key, model.page?.id == page.id, model.searchFocus == request else { return }
                    if !rects.isEmpty { self.show(boxes + rects, host: host); return }
                }
                let image = DocumentServices.image(page: page, drawing: model.canvas.drawing, workspace: model.workspace, maxDimension: 2000)
                guard let bytes = image.pngData() else { return }
                let words = try await VisionOCRService().words(image: bytes)
                try Task.checkCancellation()
                guard self.generation == key, model.page?.id == page.id, model.searchFocus == request else { return }
                let marks = PageWords.matches(request.query, in: words).prefix(80).flatMap { PageWords.lineRects($0, in: words) }.map {
                    CGRect(x: $0.minX * page.width, y: $0.minY * page.height, width: $0.width * page.width, height: $0.height * page.height)
                }
                self.show(boxes + marks, host: host)
            } catch { /* Highlighting is derived: never mutate or fail a saved note. */ }
        }
    }
    private func show(_ boxes: [CGRect], host: CanvasHost) {
        let path = UIBezierPath()
        for box in boxes where !box.isNull && !box.isEmpty { path.append(UIBezierPath(roundedRect: box.insetBy(dx: -2, dy: -2), cornerRadius: 3)) }
        highlights.path = path.cgPath; isHidden = boxes.isEmpty
        if let first = boxes.first { host.centerWritingArea(CGPoint(x: first.midX, y: first.midY)) }
    }
}
