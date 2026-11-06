import XCTest
import UIKit
import PDFKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class LayerExportRenderingTests: XCTestCase {
    @MainActor func testLayerPDFKeepsTheImportedPDFBlendSpaceAndOriginalFileWhileItsOwnOpacityMatchesTheImage() async throws {
        try await fixture { workspace, original, layer in
            let bounds = CGRect(x: 0, y: 0, width: 120, height: 100)
            let source = UIGraphicsPDFRenderer(bounds: bounds).pdfData { renderer in
                renderer.beginPage(); let context = renderer.cgContext
                context.setFillColor(UIColor.blue.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
                context.setAlpha(0.5); context.beginTransparencyLayer(auxiliaryInfo: nil)
                context.setFillColor(UIColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 120, height: 40))
                context.endTransparencyLayer()
            }
            let file = try await workspace.url("attachments/source.pdf"); try source.write(to: file)
            var page = try PageLayerEditing.opacity(layer, value: 0.5, in: original)
            page.pdfFile = "attachments/source.pdf"; page.pdfIndex = 0
            page = try await workspace.saveLayerMetadata(page, expectedRevision: original.revision)
            let image = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 120)
            let output = try await DocumentServices.exportPDF(workspace: workspace)
            defer { try? FileManager.default.removeItem(at: output) }
            let pdf = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))
            let rendered = pdf.thumbnail(of: bounds.size, for: .mediaBox)
            for y: CGFloat in [20, 70] {
                let expected = try self.pixel(image, y: y), actual = try self.pixel(rendered, y: y)
                for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(expected[channel]) - Int(actual[channel])), 4, "Source y=\(y), bitmap \(expected), PDF \(actual)") }
            }
            XCTAssertEqual(try Data(contentsOf: file), source, "Color normalization must never rewrite the imported PDF")
            let vector = try XCTUnwrap(CGPDFDocument(output as CFURL)), dictionary = try XCTUnwrap(vector.page(at: 1)?.dictionary)
            XCTAssertFalse(PDFResourceProbe.hasImages(dictionary))
        }
    }
    @MainActor func testLayerPDFRetainsPhotoImageResourcesAndTheirPixelsUnderWholeOwnerOpacity() async throws {
        try await fixture { workspace, original, layer in
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24), format: format).image { renderer in
                UIColor.green.setFill(); renderer.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
                UIColor.blue.setFill(); renderer.fill(CGRect(x: 0, y: 12, width: 24, height: 12))
            }
            let file = try await workspace.url("images/photo.png"); try XCTUnwrap(photo.pngData()).write(to: file)
            var page = try PageLayerEditing.opacity(layer, value: 0.5, in: original)
            var image = ImageElement(file: "images/photo.png", width: 40, height: 40)
            image.x = 40; image.y = 5; image.layerID = layer; page.images = [image]
            page = try await workspace.saveLayerMetadata(page, expectedRevision: original.revision)
            let bitmap = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 120)
            let output = try await DocumentServices.exportPDF(workspace: workspace)
            defer { try? FileManager.default.removeItem(at: output) }
            let pdf = try XCTUnwrap(PDFDocument(url: output)?.page(at: 0))
            let rendered = pdf.thumbnail(of: CGSize(width: 120, height: 100), for: .mediaBox)
            for (name, value) in [("layer-photo-native-bitmap", bitmap), ("layer-photo-exported-pdf", rendered), ("layer-photo-original", photo)] {
                let attachment = XCTAttachment(image: value); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            }
            let source = XCTAttachment(data: try Data(contentsOf: output), uniformTypeIdentifier: "com.adobe.pdf")
            source.name = "layer-photo-source-pdf"; source.lifetime = .keepAlways; add(source)
            let info = XCTAttachment(string: "original=\(String(describing: photo.cgImage?.colorSpace?.name)), bitmap=\(String(describing: bitmap.cgImage?.colorSpace?.name)), PDF=\(String(describing: rendered.cgImage?.colorSpace?.name))")
            info.name = "layer-photo-color-spaces"; info.lifetime = .keepAlways; add(info)
            // Sample solid photo interiors and the center of the ink overlap.
            // At y35 the lower textured native pen still has a soft fringe,
            // whereas its public vector reconstruction ends at y33.5. That
            // fringe cannot be used as an oracle for the photograph's color.
            for y: CGFloat in [15, 30, 40, 70] {
                let a = try self.pixel(bitmap, y: y), b = try self.pixel(rendered, y: y)
                for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(a[channel]) - Int(b[channel])), 4, "Photo y=\(y), bitmap \(a), PDF \(b)") }
            }
            let vector = try XCTUnwrap(CGPDFDocument(output as CFURL)), dictionary = try XCTUnwrap(vector.page(at: 1)?.dictionary)
            XCTAssertTrue(PDFResourceProbe.hasImages(dictionary), "Keep the actual photo, not a flattened page substitute")
        }
    }
    @MainActor private func fixture(_ body: (DocumentWorkspace, PageSnapshot, UUID) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()), store = try NativeDocumentStore(root: root)
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        var page = PageSnapshot(); page.width = 120; page.height = 100
        page = try await workspace.addPage(page)
        page.revision += 1; page = try await workspace.save(page, drawing: ink(color: .blue, y: 30).dataRepresentation())
        let added = try PageLayerEditing.adding(to: page, name: "Annotations"); page = added.page
        page.revision += 1; page = try await workspace.save(page, drawing: ink(color: .red, y: 70).dataRepresentation(), layerID: added.layerID)
        try await body(workspace, page, added.layerID)
    }
    @MainActor private func ink(color: UIColor, y: CGFloat, kind: PKInk.InkType = .pen) -> PKDrawing {
        let a = PKStrokePoint(location: CGPoint(x: 10, y: y), timeOffset: 0, size: CGSize(width: 7, height: 7), opacity: 1, force: 0.7, azimuth: 0.3, altitude: 1)
        let b = PKStrokePoint(location: CGPoint(x: 110, y: y), timeOffset: 1, size: CGSize(width: 7, height: 7), opacity: 1, force: 0.9, azimuth: 0.5, altitude: 0.9)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(kind, color: color), path: PKStrokePath(controlPoints: [a, b], creationDate: Date(timeIntervalSince1970: Double(y))))])
    }
    @MainActor private func pixel(_ image: UIImage, y: CGFloat) throws -> [UInt8] {
        let source = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(source.cropping(to: CGRect(x: 60 * image.scale, y: y * image.scale, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }

    @MainActor func testVisibleAllAndSingleLayerImagesUseTheCorrectFilesWithoutChangingHiddenMetadata() async throws {
        try await fixture { workspace, original, layer in
            let hidden = try PageLayerEditing.visibility(layer, visible: false, in: original)
            let page = try await workspace.saveLayerMetadata(hidden, expectedRevision: original.revision)
            let visible = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 240)
            let all = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 240, selection: .all)
            let only = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 240, selection: .selected([layer]))
            let visibleBlue = try self.pixel(visible, y: 30), visibleRed = try self.pixel(visible, y: 70)
            XCTAssertGreaterThan(Int(visibleBlue[2]), Int(visibleBlue[0]) + 100)
            XCTAssertTrue(visibleRed.prefix(3).allSatisfy { $0 > 245 })
            let allRed = try self.pixel(all, y: 70); XCTAssertGreaterThan(Int(allRed[0]), Int(allRed[2]) + 100)
            let onlyBlue = try self.pixel(only, y: 30), onlyRed = try self.pixel(only, y: 70)
            XCTAssertTrue(onlyBlue.prefix(3).allSatisfy { $0 > 245 })
            XCTAssertGreaterThan(Int(onlyRed[0]), Int(onlyRed[2]) + 100)
            let unchanged = try await workspace.pageSnapshot(page.id); XCTAssertEqual(unchanged, page)
        }
    }

    @MainActor func testPDFLayerSelectionAndOpacityRemainVectorAndMatchImageOutput() async throws {
        try await fixture { workspace, original, layer in
            let partial = try PageLayerEditing.opacity(layer, value: 0.5, in: original)
            var page = try await workspace.saveLayerMetadata(partial, expectedRevision: original.revision)
            // Compare the common solid-ink contract. PencilKit's textured pen
            // shader is not exported by Apple's public API as vector paths;
            // its native archive is checked separately without reconstruction.
            page.revision += 1
            page = try await workspace.save(page, drawing: self.ink(color: .red, y: 70, kind: .monoline).dataRepresentation(), layerID: layer)
            let output = try await DocumentServices.exportPDF(workspace: workspace, layers: .selected([layer]), pageIDs: [page.id])
            defer { try? FileManager.default.removeItem(at: output) }
            let pdf = try XCTUnwrap(PDFDocument(url: output)), first = try XCTUnwrap(pdf.page(at: 0))
            XCTAssertEqual(pdf.pageCount, 1)
            let vector = try XCTUnwrap(CGPDFDocument(output as CFURL)), dictionary = try XCTUnwrap(vector.page(at: 1)?.dictionary)
            XCTAssertFalse(PDFResourceProbe.hasImages(dictionary))
            let bitmap = try await LayeredPageRenderer.image(page: page, workspace: workspace, maxDimension: 120, selection: .selected([layer]))
            let preview = first.thumbnail(of: CGSize(width: 120, height: 100), for: .mediaBox)
            for (name, image) in [("layer-opacity-native-bitmap", bitmap), ("layer-opacity-exported-pdf", preview)] {
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            }
            let pdfAttachment = XCTAttachment(data: try Data(contentsOf: output), uniformTypeIdentifier: "com.adobe.pdf")
            pdfAttachment.name = "layer-opacity-source-pdf"; pdfAttachment.lifetime = .keepAlways; add(pdfAttachment)
            let imageRed = try self.pixel(bitmap, y: 70), pdfRed = try self.pixel(preview, y: 70)
            for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(imageRed[channel]) - Int(pdfRed[channel])), 4, "Bitmap \(imageRed), PDF \(pdfRed)") }
            XCTAssertGreaterThan(Int(pdfRed[0]), Int(pdfRed[2]) + 80)
            let baseAbsent = try self.pixel(preview, y: 30)
            XCTAssertTrue(baseAbsent.prefix(3).allSatisfy { $0 > 245 })
            var intents: CGPDFArrayRef?
            XCTAssertTrue(CGPDFDictionaryGetArray(vector.catalog!, "OutputIntents", &intents))
            XCTAssertGreaterThan(CGPDFArrayGetCount(try XCTUnwrap(intents)), 0)
        }
    }

    @MainActor func testLiveOverrideCannotReplaceTheBaseDrawingOrRequireAFileWriteToExport() async throws {
        try await fixture { workspace, page, layer in
            let before = try await LayerDrawingReader.read(page: page, layerID: layer, workspace: workspace)
            let live = self.ink(color: .green, y: 70)
            let image = try await DocumentServices.compositeImage(page: page, drawing: live, drawingLayerID: layer,
                workspace: workspace, maxDimension: 120)
            let base = try self.pixel(image, y: 30), active = try self.pixel(image, y: 70)
            XCTAssertGreaterThan(Int(base[2]), Int(base[0]) + 100)
            XCTAssertGreaterThan(Int(active[1]), Int(active[0]) + 100)
            let stored = try await workspace.pageSnapshot(page.id); XCTAssertEqual(stored, page)
            let original = try await LayerDrawingReader.read(page: stored, layerID: layer, workspace: workspace)
            XCTAssertTrue(NativeInkComparison.equal(original.drawing, before.drawing), "Compare with the actual stored native seed, not a new randomly seeded stroke")
        }
    }
    @MainActor func testPartialLayerTypedTextRemainsSelectableOnceAndDoesNotRasterizeIntoThePDF() async throws {
        try await fixture { workspace, original, layer in
            var page = try PageLayerEditing.opacity(layer, value: 0.5, in: original)
            let source = "LAYER UNIQUE Caffè più già"
            var text = TextElement(text: source); text.layerID = layer
            text.x = 5; text.y = 5; text.width = 110; text.fontSize = 12; page.texts.append(text)
            page = try await workspace.saveLayerMetadata(page, expectedRevision: original.revision)
            let output = try await DocumentServices.exportPDF(workspace: workspace, layers: .selected([layer]))
            defer { try? FileManager.default.removeItem(at: output) }
            let pdf = try XCTUnwrap(PDFDocument(url: output)), extracted = try XCTUnwrap(pdf.page(at: 0)?.string)
            let normalized = extracted.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            XCTAssertEqual(normalized.components(separatedBy: source).count - 1, 1)
            let vector = try XCTUnwrap(CGPDFDocument(output as CFURL)), dictionary = try XCTUnwrap(vector.page(at: 1)?.dictionary)
            XCTAssertFalse(PDFResourceProbe.hasImages(dictionary))
        }
    }

    @MainActor func testMergePreservesRealPixelsWholeGroupOpacityVectorInkAndExactUndoWithObjectsOnBothSidesOfInk() async throws {
        try await fixture { workspace, original, layer in
            var page = try PageLayerEditing.opacity(original.id, value: 0.6, in: original)
            page = try PageLayerEditing.opacity(layer, value: 0.4, in: page)
            var front = TextElement(text: "Base front"); front.x = 20; front.y = 60; front.width = 80; front.fontSize = 16
            front.background = InkColor(0.2, 0.8, 0.4)
            var under = TextElement(text: "Upper under"); under.x = 20; under.y = 20; under.width = 80; under.fontSize = 16
            under.background = InkColor(0.8, 0.3, 0.2); under.layerID = layer
            page.texts = [front, under]; page.aboveInkObjects = [front.id]
            page = try await workspace.saveLayerMetadata(page, expectedRevision: original.revision)
            let lower = try await LayerDrawingReader.read(page: page, layerID: page.id, workspace: workspace)
            let upper = try await LayerDrawingReader.read(page: page, layerID: layer, workspace: workspace)
            let before = try await DocumentServices.compositeImage(page: page, workspace: workspace, maxDimension: 120)
            let model = EditorViewModel(workspace: workspace); await model.open(); await model.selectLayer(layer)
            do {
                let merged = await model.performLayerOperation(.merge(layer)); XCTAssertTrue(merged)
                let result = try XCTUnwrap(model.page); XCTAssertEqual(result.layers?.count, 1)
                XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
                XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: lower.drawing.strokes + upper.drawing.strokes)))
                let after = try await DocumentServices.compositeImage(page: result, workspace: workspace, maxDimension: 120)
                for y: CGFloat in [10, 30, 50, 70, 90] {
                    let a = try self.pixel(before, y: y), b = try self.pixel(after, y: y)
                    for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(a[channel]) - Int(b[channel])), 4) }
                }
                let pdf = try await DocumentServices.exportPDF(workspace: workspace)
                defer { try? FileManager.default.removeItem(at: pdf) }
                let text = try XCTUnwrap(PDFDocument(url: pdf)?.page(at: 0)?.string)
                let reading = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                XCTAssertEqual(reading.components(separatedBy: "Base front").count - 1, 1)
                XCTAssertEqual(reading.components(separatedBy: "Upper under").count - 1, 1)
                let vector = try XCTUnwrap(CGPDFDocument(pdf as CFURL)), dictionary = try XCTUnwrap(vector.page(at: 1)?.dictionary)
                XCTAssertFalse(PDFResourceProbe.hasImages(dictionary))
                await model.performUndo()
                XCTAssertEqual(model.drawingLayerID, layer); XCTAssertEqual(model.page?.layers?.count, 2)
                XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, upper.drawing))
                await model.performRedo()
                XCTAssertEqual(model.drawingLayerID, page.id); XCTAssertEqual(model.page?.layers?.count, 1)
                XCTAssertTrue(NativeInkComparison.equal(model.canvas.drawing, PKDrawing(strokes: lower.drawing.strokes + upper.drawing.strokes)))
                _ = await model.close()
            } catch { _ = await model.close(); throw error }
        }
    }

    @MainActor func testClipboardPreservesMergedOpacityInALegacyDestinationAndUndoRestoresItsEmptyNativeCanvas() async throws {
        try await fixture { workspace, original, layer in
            var page = try PageLayerEditing.opacity(original.id, value: 0.6, in: original)
            page = try PageLayerEditing.opacity(layer, value: 0.4, in: page)
            _ = try await workspace.saveLayerMetadata(page, expectedRevision: original.revision)
            let model = EditorViewModel(workspace: workspace); await model.open()
            do {
                let merged = await model.performLayerOperation(.merge(layer)); XCTAssertTrue(merged)
                let source = try XCTUnwrap(model.page), native = model.canvas.drawing
                let image = try await DocumentServices.compositeImage(page: source, workspace: workspace, maxDimension: 120)
                model.selectAll(); XCTAssertTrue(model.copySelection())
                var blank = PageSnapshot(); blank.width = 120; blank.height = 100
                let destination = try await workspace.addPage(blank); model.pages = try await workspace.pages()
                await model.select(destination); await model.pasteSelection()
                XCTAssertEqual(model.page?.id, destination.id); XCTAssertNotNil(model.page?.layers?.first?.composition)
                let pasted = try XCTUnwrap(model.page)
                let result = try await DocumentServices.compositeImage(page: pasted, drawing: model.canvas.drawing, workspace: workspace, maxDimension: 120)
                for y: CGFloat in [30, 70] {
                    let a = try self.pixel(image, y: y), b = try self.pixel(result, y: y + 20)
                    for channel in 0..<3 { XCTAssertLessThanOrEqual(abs(Int(a[channel]) - Int(b[channel])), 4) }
                }
                XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
                XCTAssertEqual(model.canvas.drawing.strokes[0].randomSeed, native.strokes[0].randomSeed)
                XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].force, native.strokes[0].path[0].force)
                await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty); XCTAssertNil(model.page?.layers)
                _ = await model.close()
            } catch { _ = await model.close(); throw error }
        }
    }

}
