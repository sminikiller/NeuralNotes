import UIKit
import PencilKit
import NeuralNotesCore

/// The PKCanvasView is the only scroll view. Adjacent paper/ink previews share
/// its coordinates; changing the active page rebases the offset without snapping.
@MainActor
final class ContinuousCanvasFlow {
    private struct Cached {
        let page: PageSnapshot
        let drawing: PKDrawing
        let image: UIImage
    }
    private struct Viewport {
        let documentPoint: CGPoint, zoom: CGFloat, bounds: CGSize, target: UUID
    }
    weak var host: CanvasHost?
    weak var model: EditorViewModel?
    private(set) var layout = ContinuousPageLayout(pages: [])
    private var cache: [UUID: Cached] = [:]
    private var previews: [UUID: UIImageView] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: UUID] = [:]
    private var failures: [UUID: PageSnapshot] = [:]
    private var pending: Viewport?
    private var arranging = false
    private var previouslyEnabled = false
    private var pendingInputHint = false
    var enabled: Bool { model?.pageNavigation == .vertical }

    init(host: CanvasHost, model: EditorViewModel) { self.host = host; self.model = model; _ = updateSource() }

    @discardableResult
    func updateSource() -> Bool {
        guard let model else { return false }
        let changedMode = enabled != previouslyEnabled; previouslyEnabled = enabled
        var pages = model.pages
        if let page = model.page, let i = pages.firstIndex(where: { $0.id == page.id }) { pages[i] = page }
        layout = ContinuousPageLayout(pages: pages)
        if !enabled {
            for task in tasks.values { task.cancel() }; tasks = [:]; tokens = [:]
            for view in previews.values { view.removeFromSuperview() }; previews = [:]; cache = [:]; failures = [:]; pending = nil
        }
        return changedMode
    }

    var fitReference: CGSize? {
        enabled ? CGSize(width: layout.width, height: layout.maximumPageHeight) : nil
    }

    func preferredOffset() -> CGPoint? {
        guard enabled, let host else { return nil }
        let margin = max(12, (host.bounds.height - CGFloat(layout.maximumPageHeight) * host.canvas.zoomScale) / 2)
        return CGPoint(x: -host.canvas.contentInset.left, y: -margin)
    }

    @discardableResult
    func arrange() -> Bool {
        guard enabled, !arranging, let host, let frame = layout.frame(host.surface.page.id) else { return enabled }
        arranging = true; defer { arranging = false }
        let canvas = host.canvas, z = max(0.001, canvas.zoomScale)
        let size = CGSize(width: frame.width, height: frame.height)
        let extent = CGSize(width: size.width * z, height: size.height * z)
        if canvas.contentSize != extent { canvas.contentSize = extent }
        // A document-wide margin is independent of which sheet is active.
        // Mixed PDF page heights must not change the scroll limits on rebasing.
        let topMargin = max(12, (host.bounds.height - CGFloat(layout.maximumPageHeight) * z) / 2)
        let side = max(host.fitsPageWidth ? 0 : 12, (host.bounds.width - extent.width) / 2)
        let insets = UIEdgeInsets(top: CGFloat(frame.y) * z + topMargin, left: side,
            bottom: CGFloat(max(0, layout.height - frame.maxY)) * z + topMargin, right: side)
        if canvas.contentInset != insets { canvas.contentInset = insets }
        host.surface.bounds = CGRect(origin: .zero, size: size)
        host.surface.transform = CGAffineTransform(scaleX: z, y: z)
        host.surface.center = CGPoint(x: extent.width / 2 - canvas.contentOffset.x, y: extent.height / 2 - canvas.contentOffset.y)
        updatePreviews(active: frame)
        return true
    }

    func restorePendingViewport(for id: UUID) -> Bool {
        guard let pending, pending.target == id, let host, pending.bounds == host.bounds.size,
              let frame = layout.frame(id) else { self.pending = nil; return false }
        self.pending = nil
        host.canvas.setZoomScale(pending.zoom, animated: false)
        _ = arrange()
        host.canvas.setContentOffset(CGPoint(x: (pending.documentPoint.x - CGFloat(frame.x)) * pending.zoom,
            y: (pending.documentPoint.y - CGFloat(frame.y)) * pending.zoom), animated: false)
        _ = arrange()
        return true
    }

    func dragBegan() {
        guard enabled, let model, !model.interactionBusy else { return }
        // Prepare a clean editor while the finger scrolls, so prefetched pages
        // can accept Pencil's very first touch without an async page load.
        Task { [weak self] in _ = await model.flush(); await self?.prepareVisiblePages() }
    }

    func prepareVisiblePages() async {
        _ = arrange()
        let jobs = Array(tasks.values)
        for task in jobs { await task.value }
    }

    func scrollSettled() {
        guard enabled, pending == nil, let host, let model, !model.interactionBusy,
              !model.loading, !model.navigating, let active = layout.frame(host.surface.page.id) else { return }
        let z = max(0.001, host.canvas.zoomScale)
        let top = Double(host.canvas.contentOffset.y / z) + active.y
        guard let id = layout.mostVisible(top: top, height: Double(host.bounds.height / z)), id != model.page?.id else { return }
        activate(id)
    }

    func page(at point: CGPoint) -> UUID? {
        guard enabled, let host, let active = layout.frame(host.surface.page.id) else { return nil }
        let z = max(0.001, host.canvas.zoomScale)
        return layout.page(atX: Double((point.x + host.canvas.contentOffset.x) / z) + active.x,
                           y: Double((point.y + host.canvas.contentOffset.y) / z) + active.y)
    }

    /// Return true only if native PencilKit can receive this very touch safely.
    func prepareInput(at point: CGPoint) -> Bool {
        guard enabled, let host, let model else { return true }
        guard let id = page(at: point) else { return false } // the small paper gap
        if id == model.page?.id { return true }
        guard !model.interactionBusy else { return false }
        captureViewport(target: id)
        if let ready = cache[id], model.activatePreparedPage(ready.page, drawing: ready.drawing) {
            host.synchronizePage(); return true
        }
        // A cold, small native drawing can be installed synchronously before
        // UIKit dispatches the very first Pencil touch. No preview rasterization
        // belongs on this input path; larger files keep the safe async route.
        if !model.dirty, !model.saving, let target = model.pages.first(where: { $0.id == id }) {
            do {
                let drawing: PKDrawing
                if let file = target.drawingFile {
                    let url = try NativeArchive.fileURL(file, in: model.workspace.package)
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 8 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
                    drawing = try PKDrawing(data: Data(contentsOf: url, options: .mappedIfSafe))
                } else { drawing = PKDrawing() }
                if model.activatePreparedPage(target, drawing: drawing) { host.synchronizePage(); return true }
            } catch { /* The asynchronous reader retains recovery/error handling. */ }
        }
        pending = nil
        pendingInputHint = true
        host.showPageInputHint("Apertura pagina…")
        activate(id)
        return false
    }

    func activateAtPoint(_ point: CGPoint) {
        guard let id = page(at: point), id != model?.page?.id else { return }
        activate(id)
    }

    private func activate(_ id: UUID) {
        guard pending == nil, let host, let model, !model.interactionBusy, !model.navigating,
              let target = model.pages.first(where: { $0.id == id }) else { return }
        captureViewport(target: id)
        if let current = model.page {
            cache[current.id] = Cached(page: current, drawing: host.canvas.drawing,
                image: DocumentServices.image(page: current, drawing: host.canvas.drawing, workspace: model.workspace, maxDimension: 1200))
        }
        Task { [weak self, weak model] in
            guard let self, let model else { return }
            await model.select(target)
            if model.page?.id == id {
                self.host?.synchronizePage()
                if self.pendingInputHint { self.host?.showPageInputHint("Pagina pronta: inizia a scrivere.") }
            }
            else { self.pending = nil }
            self.pendingInputHint = false
        }
    }

    private func captureViewport(target: UUID) {
        guard let host, let active = layout.frame(host.surface.page.id) else { return }
        let z = max(0.001, host.canvas.zoomScale)
        pending = Viewport(documentPoint: CGPoint(x: host.canvas.contentOffset.x / z + CGFloat(active.x),
            y: host.canvas.contentOffset.y / z + CGFloat(active.y)), zoom: z, bounds: host.bounds.size, target: target)
    }

    private func updatePreviews(active: ContinuousPageLayout.Frame) {
        guard let host, let model else { return }
        let z = max(0.001, host.canvas.zoomScale)
        let top = Double(host.canvas.contentOffset.y / z) + active.y
        let visibleHeight = Double(host.bounds.height / z)
        let candidates = layout.frames.filter { $0.id != active.id && $0.maxY >= top - visibleHeight && $0.y <= top + visibleHeight * 2 }
            .sorted { abs(($0.y + $0.height / 2) - (top + visibleHeight / 2)) < abs(($1.y + $1.height / 2) - (top + visibleHeight / 2)) }
        let wanted = Set(candidates.prefix(6).map(\.id))
        for id in Array(previews.keys) where !wanted.contains(id) { previews.removeValue(forKey: id)?.removeFromSuperview() }
        for id in Array(cache.keys) where !wanted.contains(id) && id != active.id { cache.removeValue(forKey: id) }
        for id in Array(failures.keys) where !wanted.contains(id) { failures.removeValue(forKey: id) }
        for id in Array(tasks.keys) where !wanted.contains(id) { tasks.removeValue(forKey: id)?.cancel(); tokens.removeValue(forKey: id) }
        for frame in candidates.prefix(6) {
            let view: UIImageView
            if let existing = previews[frame.id] { view = existing }
            else {
                view = UIImageView(); view.contentMode = .scaleToFill; view.backgroundColor = .secondarySystemBackground
                view.isUserInteractionEnabled = false; view.accessibilityIdentifier = "continuousPagePreview-\(frame.id)"
                view.isAccessibilityElement = true; view.accessibilityLabel = "Anteprima pagina"
                let label = UILabel(); label.tag = 81; label.text = "Caricamento pagina…"
                label.font = .preferredFont(forTextStyle: .caption1); label.textAlignment = .center; label.numberOfLines = 0
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; label.frame = view.bounds
                view.addSubview(label)
                host.insertSubview(view, belowSubview: host.surface); previews[frame.id] = view
            }
            view.frame = CGRect(x: CGFloat(frame.x - active.x) * z - host.canvas.contentOffset.x,
                y: CGFloat(frame.y - active.y) * z - host.canvas.contentOffset.y,
                width: CGFloat(frame.width) * z, height: CGFloat(frame.height) * z)
            guard let page = model.pages.first(where: { $0.id == frame.id }) else { continue }
            if let ready = cache[page.id], ready.page == page { view.image = ready.image; view.viewWithTag(81)?.isHidden = true }
            else {
                view.image = nil; view.viewWithTag(81)?.isHidden = false
                if failures[page.id] != page { loadPreview(page) }
            }
        }
    }

    private func loadPreview(_ page: PageSnapshot) {
        guard tokens[page.id] == nil, let model else { return }
        let token = UUID(); tokens[page.id] = token
        tasks[page.id] = Task { [weak self, workspace = model.workspace] in
            guard let self else { return }
            defer { if self.tokens[page.id] == token { self.tokens.removeValue(forKey: page.id); self.tasks.removeValue(forKey: page.id) } }
            do {
                let bytes = try await workspace.drawing(page)
                try Task.checkCancellation()
                let drawing = try bytes.map { try PKDrawing(data: $0) } ?? PKDrawing()
                let image = DocumentServices.image(page: page, drawing: drawing, workspace: workspace, maxDimension: 1200)
                try Task.checkCancellation()
                guard self.tokens[page.id] == token else { return }
                self.cache[page.id] = Cached(page: page, drawing: drawing, image: image)
                self.previews[page.id]?.image = image
                self.previews[page.id]?.viewWithTag(81)?.isHidden = true
                self.failures.removeValue(forKey: page.id)
            } catch is CancellationError { }
            catch {
                self.failures[page.id] = page
                self.previews[page.id]?.accessibilityLabel = "Anteprima non disponibile: tocca per aprire la pagina"
                (self.previews[page.id]?.viewWithTag(81) as? UILabel)?.text = "Anteprima non disponibile\nTocca per aprire"
            }
        }
    }
}

/// Only used while an uncached page is being opened, or for the paper gap.
/// It prevents a first stroke from being written into the wrong page's file.
@MainActor
final class PendingPageInputShield: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
