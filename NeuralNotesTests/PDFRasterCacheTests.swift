import XCTest
import UIKit
import PDFKit
import PencilKit
import CryptoKit
import ImageIO
import NeuralNotesCore
@testable import NeuralNotes

private actor PDFScanReaderProbe {
    private(set) var calls = 0, blackPixels = 0
    func read(_ data: Data) -> [PageWord] {
        calls += 1
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            var bytes = [UInt8](repeating: 255, count: image.width * image.height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                if let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                }
            }
            for i in stride(from: 0, to: bytes.count, by: 4) { if bytes[i] < 50 && bytes[i + 1] < 50 && bytes[i + 2] < 50 { blackPixels += 1 } }
        }
        return [PageWord(text: "Energia", rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05))]
    }
}

final class PDFRasterCacheTests: XCTestCase {
    @MainActor private func source(pages: Int = 2, dense: Bool = false) throws -> (URL, [PageSnapshot]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NN-PDF-raster-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).writePDF(to: root.appendingPathComponent("attachments/source.pdf")) { output in
            for i in 0..<pages {
                output.beginPage()
                let context = output.cgContext
                if dense {
                    context.setStrokeColor(UIColor.gray.cgColor); context.setLineWidth(0.25)
                    for line in 0..<1800 {
                        let y = CGFloat(line % 700) + 90
                        context.move(to: CGPoint(x: CGFloat(line % 37), y: y)); context.addLine(to: CGPoint(x: 570, y: y + 4)); context.strokePath()
                    }
                }
                (i % 2 == 0 ? UIColor.red : UIColor.blue).setFill()
                context.fill(CGRect(x: 450, y: 50, width: 100, height: 100))
                ("Energia conservata pagina \(i + 1)" as NSString).draw(at: CGPoint(x: 40, y: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
            }
        }
        let snapshots = (0..<pages).map { i in
            var p = PageSnapshot(); p.width = 600; p.height = 800; p.paper = .plain
            p.pdfFile = "attachments/source.pdf"; p.pdfIndex = i; return p
        }
        return (root, snapshots)
    }
    @MainActor private func image(_ cache: PDFRasterCache, page: PageSnapshot, root: URL,
                                  box: CGRect, scale: CGFloat = 2, detailed: Bool = true) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        return UIGraphicsImageRenderer(size: box.size, format: format).image { output in
            output.cgContext.translateBy(x: -box.minX, y: -box.minY)
            UIColor.white.setFill(); output.cgContext.fill(box)
            cache.draw(page: page, package: root, in: output.cgContext, detailed: detailed)
        }
    }
    @MainActor func testDensePDFPointerFramesAndOverlappingPansNeverDecodePDFOnMainOrRerasterizeWarmTiles() async throws {
        let (root, pages) = try source(dense: true); defer { try? FileManager.default.removeItem(at: root) }
        let cache = PDFRasterCache(), page = pages[0], box = CGRect(x: 100, y: 120, width: 180, height: 180)
        await cache.preparePreview(page: page, package: root)
        _ = image(cache, page: page, root: root, box: box); await cache.waitUntilIdle()
        let count = cache.rasterizations
        XCTAssertGreaterThan(count, 1); XCTAssertEqual(cache.documentOpens, 1)
        // These viewports remain in the same fixed grid cells; the old viewport
        // renderer decoded the PDF again for each small contentOffset change.
        for i in 0..<100 {
            let offset = CGFloat(i % 20)
            _ = image(cache, page: page, root: root, box: box.offsetBy(dx: offset, dy: offset))
        }
        await cache.waitUntilIdle()
        XCTAssertEqual(cache.rasterizations, count)
        XCTAssertEqual(cache.mainThreadRasterizations, 0)
        XCTAssertEqual(cache.queuedCount, 0); XCTAssertLessThanOrEqual(cache.cachedBytes, cache.maximumBytes)
    }
    @MainActor func testVisibleSetFitsTheBudgetAndDoesNotStartAnEvictionRenderingLoop() async throws {
        let (root, pages) = try source(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = PDFRasterCache(maximumBytes: 4 * 1024 * 1024), page = pages[0]
        let box = CGRect(x: 0, y: 0, width: 600, height: 800)
        await cache.preparePreview(page: page, package: root)
        _ = image(cache, page: page, root: root, box: box, scale: 4); await cache.waitUntilIdle()
        let count = cache.rasterizations
        for _ in 0..<8 { _ = image(cache, page: page, root: root, box: box, scale: 4); await cache.waitUntilIdle() }
        XCTAssertEqual(cache.rasterizations, count, "The complete visible set must fit, not cycle through its evictions")
        XCTAssertLessThanOrEqual(cache.cachedBytes, cache.maximumBytes); XCTAssertEqual(cache.queuedCount, 0)
        XCTAssertEqual(cache.mainThreadRasterizations, 0)
    }
    @MainActor func testPageAndEpochIdentityRejectLateTilesWithoutChangingTheSourceFile() async throws {
        let (root, pages) = try source(dense: true); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("attachments/source.pdf"), before = SHA256.hash(data: try Data(contentsOf: url))
        let cache = PDFRasterCache(), box = CGRect(x: 400, y: 0, width: 200, height: 200)
        _ = image(cache, page: pages[0], root: root, box: box)
        await Task.yield(); cache.clear()
        await cache.preparePreview(page: pages[1], package: root)
        _ = image(cache, page: pages[1], root: root, box: box); await cache.waitUntilIdle()
        let result = image(cache, page: pages[1], root: root, box: box)
        let rgba = try pixel(result, at: CGPoint(x: 100, y: 100))
        XCTAssertGreaterThan(rgba[2], 180); XCTAssertLessThan(rgba[0], 80, "A late red page must never replace the current blue page")
        XCTAssertGreaterThan(cache.version(page: pages[1], package: root), cache.version(page: pages[0], package: root))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)), before)
        XCTAssertEqual(cache.mainThreadRasterizations, 0)
        cache.clear(); XCTAssertEqual(cache.cachedBytes, 0)
    }
    @MainActor func testRotatedPDFTilesUseTheSameWordGeometryAsVectorRenderingAtHighZoom() async throws {
        let (root, originals) = try source(); defer { try? FileManager.default.removeItem(at: root) }
        for rotation in [0, 90, 180, 270] {
            let pdf = try XCTUnwrap(PDFDocument(url: root.appendingPathComponent("attachments/source.pdf")))
            pdf.page(at: 0)?.rotation = rotation
            let file = "attachments/rotation-\(rotation).pdf", url = root.appendingPathComponent(file)
            XCTAssertTrue(pdf.write(to: url))
            var page = originals[0]; page.pdfFile = file
            page.width = rotation % 180 == 0 ? 600 : 800; page.height = rotation % 180 == 0 ? 800 : 600
            let words = try await PDFTextReader.shared.words(url: url, index: 0, pageWidth: page.width, pageHeight: page.height)
            let word = try XCTUnwrap(words.first { $0.text == "Energia" })
            let box = word.rect.insetBy(dx: -12, dy: -12)
            let cache = PDFRasterCache()
            await cache.preparePreview(page: page, package: root)
            _ = image(cache, page: page, root: root, box: box, scale: 4); await cache.waitUntilIdle()
            let raster = image(cache, page: page, root: root, box: box, scale: 4)
            let format = UIGraphicsImageRendererFormat(); format.scale = 4
            let vector = UIGraphicsImageRenderer(size: box.size, format: format).image { output in
                output.cgContext.translateBy(x: -box.minX, y: -box.minY)
                PageRenderer.draw(page, package: root, in: output.cgContext)
            }
            for (name, value) in [("raster", raster), ("vector", vector)] {
                let attachment = XCTAttachment(image: value); attachment.name = "PDF-\(name)-\(rotation)"; attachment.lifetime = .keepAlways; add(attachment)
            }
            let originalBlack = try blackPixels(vector), rasterBlack = try blackPixels(raster)
            XCTAssertGreaterThan(originalBlack, 100)
            XCTAssertGreaterThanOrEqual(rasterBlack, Int(Double(originalBlack) * 0.94), "Glyphs must stay sharp at \(rotation) degrees")
            XCTAssertLessThanOrEqual(rasterBlack, Int(Double(originalBlack) * 1.06) + 20)
            let originalBounds = try inkBounds(vector), rasterBounds = try inkBounds(raster)
            XCTAssertEqual(rasterBounds.minX, originalBounds.minX, accuracy: 1.25)
            XCTAssertEqual(rasterBounds.minY, originalBounds.minY, accuracy: 1.25)
            XCTAssertEqual(rasterBounds.maxX, originalBounds.maxX, accuracy: 1.25)
            XCTAssertEqual(rasterBounds.maxY, originalBounds.maxY, accuracy: 1.25)
        }
    }
    @MainActor func testInteractiveMarkerKeepsGlyphsAndColorAndDoesNotDecodeThePDFAgainForNewStrokes() async throws {
        let (root, pages) = try source(); defer { try? FileManager.default.removeItem(at: root) }
        let page = pages[0], bounds = CGRect(x: 0, y: 0, width: 600, height: 250)
        let pdf = PDFRasterCache.shared; pdf.clear(); defer { pdf.clear() }
        let prepared = await pdf.prepareDetail(page: page, package: root, bounds: bounds, scale: 2)
        XCTAssertTrue(prepared)
        let rasterCount = pdf.rasterizations, opens = DocumentRenderCache.shared.pdfOpens
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let path = UIBezierPath(rect: CGRect(x: 30, y: 40, width: 400, height: 35)).cgPath
        let baseline = renderer.image { PageRenderer.draw(page, package: root, in: $0.cgContext, pdfMode: .interactive) }
        let cache = MarkerCompositionCache()
        var highlighted = UIImage()
        for _ in 0..<20 {
            highlighted = renderer.image { output in
                cache.drawLiveMarker(page: page, baseline: PKDrawing(), token: UUID(), footprint: path, color: .yellow,
                    package: root, bounds: bounds, scale: 2, in: output.cgContext, pdfMode: .interactive)
            }
        }
        await pdf.waitUntilIdle()
        XCTAssertEqual(pdf.rasterizations, rasterCount, "New ink baselines must reuse the immutable PDF pixels")
        XCTAssertEqual(DocumentRenderCache.shared.pdfOpens, opens, "No synchronous PDF fallback is allowed on pointer frames")
        XCTAssertGreaterThanOrEqual(try blackPixels(highlighted), Int(Double(try blackPixels(baseline)) * 0.97))
        let color = try pixel(highlighted, at: CGPoint(x: 400, y: 65))
        XCTAssertGreaterThan(color[0], 245); XCTAssertGreaterThan(color[1], 245); XCTAssertEqual(Double(color[2]), 191, accuracy: 3)
    }
    @MainActor func testInvalidPDFStopsRequestsAndMemoryWarningKeepsTheCacheBounded() async throws {
        let (root, pages) = try source(pages: 18); defer { try? FileManager.default.removeItem(at: root) }
        let cache = PDFRasterCache(maximumBytes: 4 * 1024 * 1024)
        for page in pages {
            await cache.preparePreview(page: page, package: root)
            _ = image(cache, page: page, root: root, box: CGRect(x: 0, y: 0, width: 180, height: 180))
            await cache.waitUntilIdle(); XCTAssertLessThanOrEqual(cache.cachedBytes, cache.maximumBytes)
        }
        var broken = pages[0]; broken.pdfFile = "attachments/not-a-pdf.pdf"
        try Data("invalid".utf8).write(to: root.appendingPathComponent(broken.pdfFile!))
        for _ in 0..<3 { await cache.preparePreview(page: broken, package: root); await cache.waitUntilIdle() }
        XCTAssertEqual(cache.queuedCount, 0); XCTAssertEqual(cache.mainThreadRasterizations, 0)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(cache.cachedBytes, 0)
    }
    @MainActor func testRealImportedPDFKeepsNativeInkUndoExportAndFreshPageIsolation() async throws {
        let (root, _) = try source(dense: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root.appendingPathComponent("notebooks"))
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let imported = try await DocumentServices.importPDF(from: root.appendingPathComponent("attachments/source.pdf"), into: workspace)
        let model = EditorViewModel(workspace: workspace)
        await model.open(); try await model.load(try XCTUnwrap(imported.first))
        let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
        host.surface.package = workspace.package
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        host.synchronizePage(); host.layoutIfNeeded()
        let cache = PDFRasterCache.shared
        let page = try XCTUnwrap(model.page)
        XCTAssertNotNil(page.pdfFile)
        host.emptyInkCover.layer.displayIfNeeded(); host.paperDetail.layer.displayIfNeeded()
        await cache.waitUntilIdle()
        host.emptyInkCover.setNeedsDisplay(); host.emptyInkCover.layer.displayIfNeeded()
        host.paperDetail.setNeedsDisplay(); host.paperDetail.layer.displayIfNeeded()
        await cache.waitUntilIdle()
        let count = cache.rasterizations
        let points = [CGPoint(x: 130, y: 150), CGPoint(x: 240, y: 180)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: .init(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        host.updateNativeInkVisibility()
        XCTAssertFalse(host.emptyInkCover.isHidden); XCTAssertTrue(host.paperDetail.isHidden)
        model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke])
        model.drawingChanged()
        // No synchronizePage/layout call here: drawingDidChange must replace
        // the empty cover with its high-resolution PDF detail immediately.
        XCTAssertTrue(host.emptyInkCover.isHidden)
        XCTAssertFalse(host.paperDetail.isHidden, "The first pen stroke must not expose only the blurry PDF preview until the next save/layout")
        host.paperDetail.layer.displayIfNeeded()
        let detailFormat = UIGraphicsImageRendererFormat(); detailFormat.scale = 1
        let firstStrokeBackground = UIGraphicsImageRenderer(size: host.paperDetail.bounds.size, format: detailFormat).image {
            host.paperDetail.layer.render(in: $0.cgContext)
        }
        XCTAssertGreaterThan(try blackPixels(firstStrokeBackground), 100, "Restoring visibility must also repaint the cleared detail backing store")
        model.strokeEnded(); model.finishInkGesture()
        host.synchronizePage()
        XCTAssertTrue(host.emptyInkCover.isHidden); XCTAssertEqual(model.canvas.layer.opacity, 1)
        XCTAssertTrue(host.hitTest(CGPoint(x: 500, y: 400), with: nil)?.isDescendant(of: model.canvas) == true)
        await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        host.synchronizePage(); host.emptyInkCover.layer.displayIfNeeded(); host.paperDetail.layer.displayIfNeeded()
        await cache.waitUntilIdle()
        XCTAssertEqual(cache.rasterizations, count, "Ink/undo must not invalidate the immutable PDF background")
        XCTAssertEqual(cache.mainThreadRasterizations, 0)
        let saved = await model.flush(); XCTAssertTrue(saved)
        let exported = try await DocumentServices.exportPDF(workspace: workspace)
        defer { try? FileManager.default.removeItem(at: exported) }
        XCTAssertTrue(try XCTUnwrap(PDFDocument(url: exported)?.string).contains("Energia"), "Export must preserve selectable original vector text")
        await model.addPage()
        XCTAssertNil(model.page?.pdfFile); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        host.synchronizePage(); host.layoutIfNeeded()
        XCTAssertFalse(host.emptyInkCover.isHidden)
        XCTAssertTrue(host.hitTest(CGPoint(x: 500, y: 400), with: nil)?.isDescendant(of: model.canvas) == true)
        // A completion for the previous PDF must not draw its red block on a
        // newly created sheet, even if it arrives after the page switch.
        await cache.prepareDetail(page: page, package: workspace.package, bounds: CGRect(x: 400, y: 0, width: 200, height: 200), scale: 4)
        host.emptyInkCover.layer.displayIfNeeded()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let fresh = UIGraphicsImageRenderer(size: host.emptyInkCover.bounds.size, format: format).image { host.emptyInkCover.layer.render(in: $0.cgContext) }
        let white = try pixel(fresh, at: CGPoint(x: fresh.size.width * 0.83, y: fresh.size.height * 0.125))
        XCTAssertGreaterThan(white[0], 220); XCTAssertGreaterThan(white[1], 220); XCTAssertGreaterThan(white[2], 220)
        _ = await model.close()
    }
    @MainActor func testScannedPDFWordPreparationUsesBackgroundPixelsAndPassesActualContentToOCR() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do {
            let bounds = CGRect(x: 0, y: 0, width: 600, height: 800), file = root.appendingPathComponent("scan.pdf")
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let scan = UIGraphicsImageRenderer(bounds: bounds, format: format).image { output in
                UIColor.white.setFill(); output.fill(bounds)
                ("Energia conservata" as NSString).draw(at: CGPoint(x: 60, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.black])
            }
            try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: file) { output in output.beginPage(); scan.draw(in: bounds) }
            await model.importPages(from: file)
            let page = try XCTUnwrap(model.page); XCTAssertNotNil(page.pdfFile)
            XCTAssertTrue((PDFDocument(url: file)?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let before = DocumentRenderCache.shared.pdfOpens, probe = PDFScanReaderProbe()
            let index = PageWordIndex { await probe.read($0) }
            index.prepare(page, model: model)
            let deadline = Date().addingTimeInterval(10)
            while index.isPreparing(page), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertTrue(index.isReady(page)); XCTAssertEqual(index.groups(for: page).first?.first?.text, "Energia")
            let calls = await probe.calls, black = await probe.blackPixels
            XCTAssertEqual(calls, 1); XCTAssertGreaterThan(black, 100, "OCR must receive the scan's content, not a cold blank preview")
            XCTAssertEqual(DocumentRenderCache.shared.pdfOpens, before, "Selecting the marker on a scan must not synchronously decode its PDF")
            XCTAssertEqual(PDFRasterCache.shared.mainThreadRasterizations, 0)
            _ = await model.close()
        } catch { _ = await model.close(); throw error }
    }
    @MainActor private func pixel(_ image: UIImage, at point: CGPoint) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage), scale = image.scale
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: point.x * scale, y: point.y * scale, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }; return bytes
    }
    @MainActor private func blackPixels(_ image: UIImage) throws -> Int {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let p = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: p.count, by: 4).filter { p[$0] < 30 && p[$0 + 1] < 30 && p[$0 + 2] < 30 }.count
        }
    }
    @MainActor private func inkBounds(_ image: UIImage) throws -> CGRect {
        let source = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: source.width * source.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: source.width, height: source.height, bitsPerComponent: 8,
                bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let pixels = buffer.bindMemory(to: UInt8.self); var box = CGRect.null
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] < 128 && pixels[i + 1] < 128 && pixels[i + 2] < 128 {
                let at = i / 4; box = box.union(CGRect(x: at % source.width, y: at / source.width, width: 1, height: 1))
            }
            return box
        }
    }
}
