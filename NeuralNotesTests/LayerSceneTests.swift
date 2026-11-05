import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class LayerSceneTests: XCTestCase {
    @MainActor private func fixture(_ body: (EditorViewModel, UUID) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        let store = try NativeDocumentStore(root: root); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = PageSnapshot(); page.width = 200; page.height = 200
        page = try await workspace.addPage(page); page.revision += 1
        page = try await workspace.save(page, drawing: drawing(.blue, y: 60).dataRepresentation())
        let added = try PageLayerEditing.adding(to: page, name: "Annotazioni"); page = added.page; page.revision += 1
        _ = try await workspace.save(page, drawing: drawing(.red, y: 140).dataRepresentation(), layerID: added.layerID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        do { try await body(model, added.layerID); _ = await model.close() }
        catch { _ = await model.close(); throw error }
    }
    @MainActor private func drawing(_ color: UIColor, y: CGFloat) -> PKDrawing {
        let a = PKStrokePoint(location: .init(x: 10, y: y), timeOffset: 0, size: .init(width: 8, height: 8), opacity: 1, force: 0.7, azimuth: 0.3, altitude: 1)
        let b = PKStrokePoint(location: .init(x: 190, y: y), timeOffset: 1, size: .init(width: 8, height: 8), opacity: 1, force: 0.9, azimuth: 0.5, altitude: 0.9)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: Double(y))))])
    }
    @MainActor private func pixel(_ image: UIImage, y: CGFloat) throws -> [UInt8] {
        let cg = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(cg.cropping(to: CGRect(x: 100 * image.scale, y: y * image.scale, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }
    @MainActor func testWholeSceneDrawsOwnersAboveAndBelowWithoutReplacingNativeDrawingAndStaysWithinItsBudget() async throws {
        try await fixture { model, owner in
            await model.selectLayer(owner)
            let original = model.canvas.drawing, page = try XCTUnwrap(model.page)
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.package = model.workspace.package
            host.surface.page = page; host.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
            host.setNeedsLayout(); host.layoutIfNeeded()
            let ready = await host.layeredScene.prepareForInput(host); XCTAssertTrue(ready)
            XCTAssertFalse(host.layeredScene.isUserInteractionEnabled)
            XCTAssertEqual(host.canvas.layer.opacity, 1)
            XCTAssertTrue(host.emptyInkCover.isHidden); XCTAssertTrue(host.paperDetail.isHidden)
            XCTAssertLessThanOrEqual(host.layeredScene.cachedBytes, LayerScene.fallbackBudget + LayerScene.detailBudget)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image {
                host.layeredScene.drawScene(in: $0.cgContext, bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
            }
            let lower = try self.pixel(image, y: 60), upper = try self.pixel(image, y: 140)
            XCTAssertGreaterThan(Int(lower[2]), Int(lower[0]) + 100)
            XCTAssertGreaterThan(Int(upper[0]), Int(upper[2]) + 100)
            XCTAssertTrue(NativeInkComparison.equal(original, model.canvas.drawing))
            XCTAssertEqual(model.page, page)
            host.layeredScene.reset(); XCTAssertFalse(host.layeredScene.isReady); XCTAssertEqual(host.layeredScene.cachedBytes, 0)
        }
    }
    @MainActor func testCachedMapsReuseInactiveOwnersAcrossActiveMetadataAndLocksButIncludeGroupOpacity() async throws {
        try await fixture { model, owner in
            var page = try XCTUnwrap(model.page)
            let first = try await LayerScene.prepare(page: page, owner: owner, workspace: model.workspace,
                bounds: CGRect(x: 0, y: 0, width: 200, height: 200), requestedScale: 1, budget: LayerScene.detailBudget)
            var text = TextElement(text: "Active"); text.layerID = owner; text.x = 10; text.y = 90; text.width = 100
            page.texts.append(text)
            let second = try await LayerScene.prepare(page: page, owner: owner, workspace: model.workspace,
                bounds: first.bounds, requestedScale: 1, budget: LayerScene.detailBudget, previous: first)
            XCTAssertEqual(first.inactiveFingerprint, second.inactiveFingerprint)
            XCTAssertTrue(first.below?.multiply === second.below?.multiply)
            XCTAssertNotEqual(first.fingerprint, second.fingerprint)
            let locked = try PageLayerEditing.lock(owner, locked: true, in: page)
            XCTAssertEqual(LayerScene.fingerprint(locked, owner: owner), second.fingerprint)
            let partial = try PageLayerEditing.opacity(owner, value: 0.5, in: page)
            XCTAssertNotEqual(LayerScene.fingerprint(partial, owner: owner), second.fingerprint)
            XCTAssertEqual(LayerScene.fingerprint(partial, owner: owner, inactiveOnly: true), second.inactiveFingerprint)
        }
    }
    @MainActor func testLiveAppendRasterizesTheOldInkOnlyOnceAndReplacementCannotReuseAnObsoleteBaseline() {
        let cache = ActiveLayerInkCache(), base = drawing(.blue, y: 60), bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let gesture = UUID(), local = UUID()
        for index in 0..<8 {
            let next = PKDrawing(strokes: base.strokes + drawing(.red, y: CGFloat(100 + index)).strokes)
            cache.prepare(drawing: next, baseline: base, baselineToken: gesture, token: UUID(), localToken: local, bounds: bounds, scale: 2)
        }
        XCTAssertEqual(cache.baselineBuilds, 1); XCTAssertEqual(cache.currentBuilds, 8)
        cache.prepare(drawing: PKDrawing(), baseline: nil, baselineToken: nil, token: UUID(), localToken: local, bounds: bounds, scale: 2)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image {
            UIColor.white.setFill(); $0.fill(bounds); cache.drawMarkers(in: $0.cgContext); cache.drawPens(in: $0.cgContext)
        }
        XCTAssertTrue((try? pixel(image, y: 60).prefix(3).allSatisfy { $0 > 245 }) == true)
    }
    @MainActor func testAudioHitReadsTheCorrectVisibleOwnerAndNeverSeeksInkOnlyInsideItsBoundingBox() async throws {
        try await fixture { model, owner in
            var page = try XCTUnwrap(model.page)
            let lower = try await LayerDrawingReader.read(page: page, layerID: page.id, workspace: model.workspace)
            let upper = try await LayerDrawingReader.read(page: page, layerID: owner, workspace: model.workspace)
            let session = UUID()
            var a = StrokeAnchor(signature: EditorInkSignatures.make(lower.drawing)[0], audioSessionID: session, seconds: 10)
            a.strokeOccurrence = 0
            var b = StrokeAnchor(signature: EditorInkSignatures.make(upper.drawing)[0], audioSessionID: session, seconds: 30)
            b.layerID = owner; b.strokeOccurrence = 0; page.anchors = [a, b]
            let hit = try await LayerAudioHit.anchor(at: CGPoint(x: 100, y: 140), tolerance: 10, page: page,
                live: lower.drawing, owner: page.id, workspace: model.workspace, zoom: 1)
            XCTAssertEqual(hit?.seconds, 30); XCTAssertEqual(hit?.layerID, owner)
            let miss = try await LayerAudioHit.anchor(at: CGPoint(x: 100, y: 100), tolerance: 10, page: page,
                live: lower.drawing, owner: page.id, workspace: model.workspace, zoom: 1)
            XCTAssertNil(miss)
            page = try PageLayerEditing.visibility(owner, visible: false, in: page)
            let hiddenHit = try await LayerAudioHit.anchor(at: CGPoint(x: 100, y: 140), tolerance: 10, page: page,
                live: lower.drawing, owner: page.id, workspace: model.workspace, zoom: 1)
            XCTAssertNil(hiddenHit)
        }
    }
    @MainActor func testReplayFiltersEachOwnersTimelineAndReusesUnchangedNativeArchivesWithoutMutatingThePage() async throws {
        try await fixture { model, owner in
            var page = try XCTUnwrap(model.page)
            let original = page, session = UUID(), cache = LayerReplayRenderer(), generation = UUID()
            let lower = try await LayerDrawingReader.read(page: page, layerID: page.id, workspace: model.workspace)
            let upper = try await LayerDrawingReader.read(page: page, layerID: owner, workspace: model.workspace)
            var a = StrokeAnchor(signature: EditorInkSignatures.make(lower.drawing)[0], audioSessionID: session, seconds: 10)
            a.strokeOccurrence = 0
            var b = StrokeAnchor(signature: EditorInkSignatures.make(upper.drawing)[0], audioSessionID: session, seconds: 30)
            b.layerID = owner; b.strokeOccurrence = 0; page.anchors = [a, b]
            let start = try await cache.image(page: page, workspace: model.workspace, live: lower.drawing, owner: page.id,
                generation: generation, sessionID: session, seconds: 0, mode: .follow, hiding: [], maxDimension: 200)
            XCTAssertTrue(try self.pixel(start, y: 60).prefix(3).allSatisfy { $0 > 245 })
            XCTAssertTrue(try self.pixel(start, y: 140).prefix(3).allSatisfy { $0 > 245 })
            let middle = try await cache.image(page: page, workspace: model.workspace, live: lower.drawing, owner: page.id,
                generation: generation, sessionID: session, seconds: 11, mode: .follow, hiding: [], maxDimension: 200)
            let blue = try self.pixel(middle, y: 60)
            XCTAssertGreaterThan(Int(blue[2]), Int(blue[0]) + 100)
            XCTAssertTrue(try self.pixel(middle, y: 140).prefix(3).allSatisfy { $0 > 245 })
            let reads = cache.nativeReads
            _ = try await cache.image(page: page, workspace: model.workspace, live: lower.drawing, owner: page.id,
                generation: generation, sessionID: session, seconds: 12, mode: .follow, hiding: [], maxDimension: 200)
            XCTAssertEqual(cache.nativeReads, reads, "A clock tick must not decode unchanged owners again")
            let end = try await cache.image(page: page, workspace: model.workspace, live: lower.drawing, owner: page.id,
                generation: generation, sessionID: session, seconds: 31, mode: .follow, hiding: [], maxDimension: 200)
            let red = try self.pixel(end, y: 140)
            XCTAssertGreaterThan(Int(red[0]), Int(red[2]) + 100)
            XCTAssertLessThanOrEqual(cache.cachedBytes, LayerReplayRenderer.budget)
            let stored = try await model.workspace.pageSnapshot(page.id); XCTAssertEqual(stored, original)
            XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, lower.drawing))
        }
    }

}
