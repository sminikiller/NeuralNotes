import UIKit
import CoreGraphics
import NeuralNotesCore

/// Export always uses the original vector PDF. Screen surfaces share a small
/// preview and reusable, fixed pixel tiles instead of decoding PDF on touch.
enum PDFRenderMode: Equatable { case vector, preview, interactive }

struct PDFRasterSource: Hashable, Sendable {
    let url: URL, index: Int, width: Double, height: Double
    init?(page: PageSnapshot, package: URL) {
        guard let file = page.pdfFile, let index = page.pdfIndex, index >= 0,
              page.width.isFinite, page.height.isFinite,
              page.width > 0, page.height > 0, page.width <= 20_000, page.height <= 20_000 else { return nil }
        url = package.appendingPathComponent(file).standardizedFileURL
        self.index = index; width = page.width; height = page.height
    }
    var bounds: CGRect { CGRect(x: 0, y: 0, width: width, height: height) }
}

private enum PDFRasterPart: Hashable, Sendable {
    case preview
    case tile(level: Int, x: Int, y: Int)
    var isPreview: Bool { if case .preview = self { return true }; return false }
}
private struct PDFRasterKey: Hashable, Sendable { let source: PDFRasterSource, part: PDFRasterPart }
private struct PDFRasterRequest: Sendable {
    let key: PDFRasterKey, bounds: CGRect, scale: Double, epoch: UUID
}
/// CGImage is immutable; it is never drawn into or mutated after publication.
private struct PDFRasterResult: @unchecked Sendable {
    let image: CGImage, opened: Bool, onMainThread: Bool
}

/// The worker owns its own CGPDFDocuments. It never shares a document with
/// UIKit/export, never reads a whole PDF into Data, and renders one tile at a time.
private actor PDFRasterWorker {
    private final class Document {
        let value: CGPDFDocument, epoch: UUID
        var pages = Set<Int>(), touched = 0
        init(_ value: CGPDFDocument, epoch: UUID) { self.value = value; self.epoch = epoch }
    }
    private var documents: [URL: Document] = [:]
    private var clock = 0
    func render(_ request: PDFRasterRequest) -> PDFRasterResult? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            let source = request.key.source
            var document = documents[source.url], opened = false
            if document?.epoch != request.epoch || (document?.pages.count ?? 0) >= 16 && document?.pages.contains(source.index) != true {
                document = nil; documents[source.url] = nil
            }
            if document == nil {
                guard let pdf = CGPDFDocument(source.url as CFURL), pdf.isUnlocked else { return nil }
                document = Document(pdf, epoch: request.epoch); documents[source.url] = document; opened = true
            }
            guard let document, source.index < document.value.numberOfPages,
                  let page = document.value.page(at: source.index + 1), !Task.isCancelled else { return nil }
            clock &+= 1; document.touched = clock; document.pages.insert(source.index)
            while documents.count > 3, let oldest = documents.min(by: { $0.value.touched < $1.value.touched })?.key { documents[oldest] = nil }
            let pw = ceil(request.bounds.width * request.scale), ph = ceil(request.bounds.height * request.scale)
            guard pw.isFinite, ph.isFinite, pw > 0, ph > 0, pw <= 2048, ph <= 2048,
                  let context = CGContext(data: nil, width: Int(pw), height: Int(ph), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // The same top-left page geometry and intrinsic rotation as the
            // vector renderer, with an additional visible-tile translation.
            context.translateBy(x: 0, y: ph); context.scaleBy(x: request.scale, y: -request.scale)
            context.translateBy(x: -request.bounds.minX, y: -request.bounds.minY)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(source.bounds)
            context.translateBy(x: 0, y: source.height); context.scaleBy(x: 1, y: -1)
            context.concatenate(page.getDrawingTransform(.cropBox, rect: source.bounds, rotate: 0, preserveAspectRatio: true))
            context.interpolationQuality = .high
            context.drawPDFPage(page)
            guard !Task.isCancelled, let image = context.makeImage() else { return nil }
            return PDFRasterResult(image: image, opened: opened, onMainThread: Thread.isMainThread)
        }
    }
}

@MainActor
final class PDFRasterCache: NSObject {
    static let shared = PDFRasterCache()
    static let didRender = Notification.Name("NeuralNotes.PDFRasterReady")
    private final class Entry {
        let image: UIImage, bounds: CGRect, cost: Int
        var touched: Int
        init(_ result: PDFRasterResult, bounds: CGRect, touched: Int) {
            image = UIImage(cgImage: result.image); self.bounds = bounds; self.touched = touched
            cost = result.image.bytesPerRow * result.image.height
        }
    }
    private struct Queued { let request: PDFRasterRequest; var touched: Int }
    let maximumBytes: Int
    private let worker = PDFRasterWorker()
    private var entries: [PDFRasterKey: Entry] = [:], queue: [PDFRasterKey: Queued] = [:]
    private var failed = Set<PDFRasterKey>()
    private var active: Task<Void, Never>?, activeKey: PDFRasterKey?, ticket = UUID(), epoch = UUID()
    private var activeTouch = 0
    private var clock = 0, serial = 0, invalidation = 0
    private var versions: [PDFRasterSource: Int] = [:]
    private var changed = Set<PDFRasterSource>(), changedPreviews = Set<PDFRasterSource>()
    private var notification: Task<Void, Never>?
    private(set) var rasterizations = 0, documentOpens = 0, mainThreadRasterizations = 0
    var cachedBytes: Int { entries.values.reduce(0) { $0 + $1.cost } }
    var queuedCount: Int { queue.count + (active == nil ? 0 : 1) }
    init(maximumBytes: Int = 48 * 1024 * 1024) {
        self.maximumBytes = max(4 * 1024 * 1024, maximumBytes)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(nnPDFMemoryWarning), name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func nnPDFMemoryWarning() { clear() }
    func clear() {
        epoch = UUID(); ticket = UUID(); active?.cancel(); active = nil; activeKey = nil
        queue = [:]; entries = [:]; failed = []; versions = [:]
        serial &+= 1; invalidation = serial
        notification?.cancel(); notification = nil; changed = []; changedPreviews = []
    }
    func version(page: PageSnapshot, package: URL) -> Int {
        guard let source = PDFRasterSource(page: page, package: package) else { return 0 }
        return versions[source] ?? invalidation
    }
    static func affects(_ note: Notification, page: PageSnapshot, package: URL, previewOnly: Bool = false) -> Bool {
        guard let source = PDFRasterSource(page: page, package: package), let sources = note.userInfo?[previewOnly ? "previews" : "sources"] as? [PDFRasterSource] else { return false }
        return sources.contains(source)
    }
    /// Requests are keyed to immutable PDF source, page index and output size;
    /// ink edits, object movement and undo never invalidate the PDF background.
    func draw(page: PageSnapshot, package: URL, in context: CGContext, detailed: Bool) {
        guard let source = PDFRasterSource(page: page, package: package) else { return }
        let clip = context.boundingBoxOfClipPath.intersection(source.bounds)
        guard !clip.isNull, !clip.isEmpty else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.interpolationQuality = .high
        clock &+= 1; let demand = clock
        let preview = previewRequest(source)
        if let entry = entries[preview.key] { entry.touched = demand; entry.image.draw(in: entry.bounds) }
        else { request(preview, touched: demand) }
        guard detailed else { pump(); return }
        let transform = context.userSpaceToDeviceSpaceTransform
        let scale = max(hypot(transform.a, transform.b), hypot(transform.c, transform.d))
        guard scale.isFinite, scale > 0 else { pump(); return }
        let jobs = detailRequests(source, clip: clip, scale: Double(scale))
        // Reuse the last available resolution while pinch/scroll asks for new
        // detail. Fixed tile coordinates avoid rerasterizing each moved viewport.
        let available = entries.filter { $0.key.source == source && !$0.key.part.isPreview && $0.value.bounds.intersects(clip) }
            .sorted { lhs, rhs in
                if case .tile(let a, _, _) = lhs.key.part, case .tile(let b, _, _) = rhs.key.part { return a < b }
                return false
            }
        for (_, entry) in available { entry.touched = demand; entry.image.draw(in: entry.bounds) }
        clock &+= 1
        for job in jobs {
            if let entry = entries[job.key] { entry.touched = clock }
            else { request(job, touched: clock) }
        }
        pump()
    }
    /// Prewarm only a small page preview before activating a cold PDF page or
    /// composing a neighbour thumbnail. The interface remains free while waiting.
    func preparePreview(page: PageSnapshot, package: URL) async {
        guard let source = PDFRasterSource(page: page, package: package) else { return }
        let job = previewRequest(source), originalEpoch = epoch
        while entries[job.key] == nil && !failed.contains(job.key) && epoch == originalEpoch && !Task.isCancelled {
            clock &+= 1; request(job, touched: clock); pump()
            guard let task = active else { break }; await task.value
        }
    }
    func waitUntilIdle() async {
        pump()
        while let task = active { await task.value }
    }
    /// Optional derived work (OCR) can prepare its requested resolution without
    /// putting PDF decoding back on the main actor. Abort rather than compete
    /// indefinitely with a rapidly changing interactive viewport.
    @discardableResult
    func prepareDetail(page: PageSnapshot, package: URL, bounds: CGRect, scale: Double) async -> Bool {
        guard let source = PDFRasterSource(page: page, package: package) else { return true }
        let clip = bounds.intersection(source.bounds)
        guard !clip.isNull, !clip.isEmpty, scale.isFinite, scale > 0 else { return false }
        await preparePreview(page: page, package: package)
        let jobs = detailRequests(source, clip: clip, scale: scale), originalEpoch = epoch
        for _ in 0..<(jobs.count * 2 + 2) {
            guard !Task.isCancelled, epoch == originalEpoch else { return false }
            let missing = jobs.filter { entries[$0.key] == nil && !failed.contains($0.key) }
            if missing.isEmpty { return jobs.allSatisfy { entries[$0.key] != nil } }
            clock &+= 1
            for job in missing { request(job, touched: clock) }
            pump(); guard let task = active else { return false }; await task.value
        }
        return jobs.allSatisfy { entries[$0.key] != nil }
    }
    private func previewRequest(_ source: PDFRasterSource) -> PDFRasterRequest {
        let pixelBudget = min(750_000.0, Double(maximumBytes / 4) / 8)
        let scale = min(1024 / max(source.width, source.height), sqrt(pixelBudget / (source.width * source.height)))
        return PDFRasterRequest(key: .init(source: source, part: .preview), bounds: source.bounds, scale: scale, epoch: epoch)
    }
    private func tileRequests(_ source: PDFRasterSource, clip: CGRect, level: Int) -> [PDFRasterRequest] {
        let scale = pow(2, Double(level) / 2), side = 512 / scale
        let x0 = max(0, Int(floor(clip.minX / side))), y0 = max(0, Int(floor(clip.minY / side)))
        let x1 = Int(ceil(clip.maxX / side)), y1 = Int(ceil(clip.maxY / side))
        var jobs: [PDFRasterRequest] = []
        for y in y0..<max(y0, y1) {
            for x in x0..<max(x0, x1) {
                // One-pixel bleed prevents seams at fractional zoom scales.
                let box = CGRect(x: Double(x) * side, y: Double(y) * side, width: side, height: side)
                    .insetBy(dx: -1 / scale, dy: -1 / scale).intersection(source.bounds)
                jobs.append(.init(key: .init(source: source, part: .tile(level: level, x: x, y: y)), bounds: box, scale: scale, epoch: epoch))
                if jobs.count == 64 { return jobs }
            }
        }
        return jobs
    }
    private func detailRequests(_ source: PDFRasterSource, clip: CGRect, scale: Double) -> [PDFRasterRequest] {
        // A fixed tile grid is often sampled at a fractional pixel offset while
        // panning. Render with headroom so that a second bitmap sampling does
        // not soften thin/rotated glyphs. The complete visible set still has
        // to fit the same working-memory budget below.
        var level = min(8, Int(ceil(log2(min(16, max(0.03125, scale))) * 2)) + 2)
        var jobs = tileRequests(source, clip: clip, level: level)
        let workingBudget = (maximumBytes - maximumBytes / 4) * 4 / 5
        // The complete visible set must fit, including offscreen tile edges.
        // This prevents an eviction/rasterization loop on large displays.
        while estimatedCost(jobs) > workingBudget && level > -10 {
            level -= 1; jobs = tileRequests(source, clip: clip, level: level)
        }
        return jobs
    }
    private func request(_ job: PDFRasterRequest, touched: Int) {
        if activeKey == job.key { activeTouch = max(activeTouch, touched); return }
        guard !failed.contains(job.key), entries[job.key] == nil else { return }
        queue[job.key] = Queued(request: job, touched: touched)
        if queue.count > 96, let oldest = queue.min(by: { $0.value.touched < $1.value.touched })?.key { queue[oldest] = nil }
    }
    private func estimatedCost(_ jobs: [PDFRasterRequest]) -> Int {
        jobs.reduce(0) { total, job in
            let width = Int(ceil(job.bounds.width * job.scale)), height = Int(ceil(job.bounds.height * job.scale))
            return total + ((width * 4 + 127) / 128) * 128 * height
        }
    }
    private func pump() {
        guard active == nil, !queue.isEmpty else { return }
        // Small previews first; among detail requests the newest viewport wins.
        let next = queue.max { a, b in
            if a.key.part.isPreview != b.key.part.isPreview { return !a.key.part.isPreview }
            return a.value.touched < b.value.touched
        }!
        queue[next.key] = nil; activeKey = next.key; activeTouch = next.value.touched
        let identity = UUID(); ticket = identity
        let request = next.value.request
        active = Task { [weak self, worker] in
            let result = await worker.render(request)
            guard let self, self.ticket == identity, self.epoch == request.epoch, !Task.isCancelled else { return }
            if let result {
                self.rasterizations += 1; if result.opened { self.documentOpens += 1 }
                if result.onMainThread { self.mainThreadRasterizations += 1 }
                self.entries[request.key] = Entry(result, bounds: request.bounds, touched: self.activeTouch)
                self.trim(preview: request.key.part.isPreview)
                self.serial &+= 1; self.versions[request.key.source] = self.serial
                if self.versions.count > 128, let oldest = self.versions.min(by: { $0.value < $1.value })?.key { self.versions[oldest] = nil }
                self.changed.insert(request.key.source)
                if request.key.part.isPreview { self.changedPreviews.insert(request.key.source) }
                self.scheduleNotification()
            } else {
                if self.failed.count >= 128 { self.failed.removeAll() }
                self.failed.insert(request.key)
            }
            self.active = nil; self.activeKey = nil; self.pump()
        }
    }
    private func trim(preview: Bool) {
        let budget = preview ? maximumBytes / 4 : maximumBytes - maximumBytes / 4
        var candidates = entries.filter { $0.key.part.isPreview == preview }.sorted { $0.value.touched < $1.value.touched }
        var cost = candidates.reduce(0) { $0 + $1.value.cost }
        while cost > budget, !candidates.isEmpty {
            let item = candidates.removeFirst(); cost -= item.value.cost; entries[item.key] = nil
        }
    }
    private func scheduleNotification() {
        guard notification == nil else { return }
        notification = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
            guard let self else { return }
            let sources = Array(self.changed), previews = Array(self.changedPreviews)
            self.changed = []; self.changedPreviews = []; self.notification = nil
            NotificationCenter.default.post(name: Self.didRender, object: nil, userInfo: ["sources": sources, "previews": previews])
        }
    }
}
