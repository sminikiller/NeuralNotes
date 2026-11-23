import XCTest
import UIKit
import PDFKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class PDFStudySnippetTests: XCTestCase {
    @MainActor private func source() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snippet-\(UUID()).pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).writePDF(to: url) { output in
            output.beginPage()
            UIColor.red.setFill(); output.cgContext.fill(CGRect(x: 40, y: 60, width: 120, height: 80))
            ("Estratto di studio" as NSString).draw(at: CGPoint(x: 45, y: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
        return url
    }
    @MainActor func testSnippetUsesCropAndAllRotationsWithoutChangingPDFAndLimitsPixels() async throws {
        let url = try source(); defer { try? FileManager.default.removeItem(at: url) }
        let document = try XCTUnwrap(PDFDocument(url: url)), page = try XCTUnwrap(document.page(at: 0))
        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            XCTAssertTrue(document.write(to: url))
            let original = try Data(contentsOf: url)
            let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL)), reference = try XCTUnwrap(pdf.page(at: 1))
            let request = try XCTUnwrap(PDFSnippetRequest.make(url: url, index: 0, page: reference,
                selection: CGRect(x: 50, y: 470, width: 100, height: 60)))
            let data = try await PDFSnippetRenderer.shared.render(request)
            let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
            XCTAssertEqual(image.width, Int(ceil(request.bounds.width * 2)))
            XCTAssertEqual(image.height, Int(ceil(request.bounds.height * 2)))
            var pixel = [UInt8](repeating: 0, count: 4)
            pixel.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertGreaterThan(pixel[0], 240); XCTAssertLessThan(pixel[1], 15); XCTAssertLessThan(pixel[2], 15)
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertNil(PDFSnippetRequest.make(url: url, index: 0, page: reference, selection: CGRect(x: -500, y: -500, width: 10, height: 10)))
        }
        let huge = PDFSnippetRequest(url: url, index: 0, bounds: CGRect(x: 0, y: 0, width: 5000, height: 6000), pageSize: CGSize(width: 5000, height: 6000))
        let large = try await PDFSnippetRenderer.shared.render(huge)
        let bounded = try XCTUnwrap(UIImage(data: large)?.cgImage)
        XCTAssertLessThanOrEqual(bounded.width, 2048); XCTAssertLessThanOrEqual(bounded.height, 2048)
    }
    @MainActor func testSidePDFResumesOnSavedPageUsingANewController() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).writePDF(to: url) { output in
            for _ in 0..<5 { output.beginPage() }
        }
        let reader = PDFStudyController(), view = PDFView(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        var saved = -1
        reader.didReadPage = { _, page in saved = page }
        reader.attach(view); reader.load(file: url.lastPathComponent, package: url.deletingLastPathComponent(), index: 0)
        view.go(to: try XCTUnwrap(view.document?.page(at: 3))); reader.detach()
        XCTAssertEqual(saved, 3)
        let next = PDFStudyController(), reopened = PDFView(frame: view.frame)
        next.attach(reopened); next.load(file: url.lastPathComponent, package: url.deletingLastPathComponent(), index: saved)
        let document = try XCTUnwrap(reopened.document)
        XCTAssertEqual(document.index(for: try XCTUnwrap(reopened.currentPage)), 3)
        next.detach()
    }
    @MainActor func testSidebarDoesNotVisitAllPDFPagesOnEveryPenRevision() throws {
        let url = try source(); defer { try? FileManager.default.removeItem(at: url) }
        let controller = PDFStudyController(), view = PDFView()
        controller.attach(view); controller.load(file: url.absoluteString, package: url.deletingLastPathComponent(), index: 0, external: url)
        var pages = (0..<1500).map { index in
            var page = PageSnapshot(); page.pdfFile = url.absoluteString; page.pdfIndex = index; return page
        }
        controller.syncMarkups(pages); XCTAssertEqual(controller.markupPageVisits, 0)
        pages[0].revision += 1; controller.syncMarkups(pages); XCTAssertEqual(controller.markupPageVisits, 0)
        pages[0].pdfMarkups = [PDFMarkup(kind: .highlight, x: 40, y: 60, width: 100, height: 20, text: "Studio")]
        controller.syncMarkups(pages); XCTAssertEqual(controller.markupPageVisits, 1)
        XCTAssertEqual(view.document?.page(at: 0)?.annotations.count, 1)
        pages[0].revision += 1; controller.syncMarkups(pages); XCTAssertEqual(controller.markupPageVisits, 1)
        pages[0].pdfMarkups = []; controller.syncMarkups(pages)
        XCTAssertEqual(controller.markupPageVisits, 2); XCTAssertEqual(view.document?.page(at: 0)?.annotations.count, 0)
        pages[0].pdfMarkups = [PDFMarkup(kind: .highlight, x: 40, y: 60, width: 100, height: 20, text: "Studio")]
        controller.syncMarkups(pages)
        pages.removeFirst(); controller.syncMarkups(pages)
        XCTAssertEqual(view.document?.page(at: 0)?.annotations.count, 0, "Deleting a notebook page must also remove its owned sidebar markup")
        controller.detach()
    }
    @MainActor func testSnippetImportIsOneUndoAndPersistsWithoutImportingPDFPages() async throws {
        let url = try source(), root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: url) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let model = EditorViewModel(workspace: workspace); await model.open()
        let id = try XCTUnwrap(model.page?.id), count = model.pages.count
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL)), page = try XCTUnwrap(pdf.page(at: 1))
        let request = try XCTUnwrap(PDFSnippetRequest.make(url: url, index: 0, page: page, selection: CGRect(x: 50, y: 470, width: 100, height: 60)))
        try await model.insertPDFSnippet(request)
        XCTAssertEqual(model.page?.images.count, 1); XCTAssertEqual(model.pages.count, count)
        let inserted = try XCTUnwrap(model.page?.images.first)
        await model.performUndo(); XCTAssertEqual(model.page?.images.count, 0)
        await model.performRedo(); XCTAssertEqual(model.page?.images.first, inserted)
        let flushed = await model.flush(); XCTAssertTrue(flushed)
        let saved = try await workspace.pageSnapshot(id)
        XCTAssertEqual(saved.images.first, inserted); XCTAssertNil(saved.pdfFile)
        let closed = await model.close(); XCTAssertTrue(closed)
    }
}
