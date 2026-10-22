import XCTest
import UIKit
import PDFKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class LargePDFDocumentTests: XCTestCase {
    @MainActor func testActualFifteenHundredPagePDFImportsWithoutEagerTextAndRemainsReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("NN-large-PDF-\(UUID())")
        let store = try NativeDocumentStore(root: root); defer { try? FileManager.default.removeItem(at: root) }
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID()); try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID)
        let source = root.appendingPathComponent("1500-pages.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).writePDF(to: source) { renderer in
            for number in 1...1500 {
                renderer.beginPage()
                ("Pagina \(number)" as NSString).draw(at: CGPoint(x: 50, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }
        }
        let pages = try await DocumentServices.importPDF(from: source, into: workspace)
        XCTAssertEqual(pages.count, 1500); XCTAssertEqual(pages.last?.pdfIndex, 1499)
        XCTAssertTrue(pages.allSatisfy { $0.recognizedText.isEmpty && $0.texts.isEmpty && $0.drawingFile == nil })
        let text = try await DocumentServices.pdfText(page: pages.last!, workspace: workspace)
        XCTAssertTrue(text.contains("Pagina 1500"))
        let firstText = try await DocumentServices.pdfText(page: pages[0], workspace: workspace)
        XCTAssertTrue(firstText.contains("Pagina 1"))
        let words = try await PDFTextReader.shared.words(url: source, index: 1499, pageWidth: 600, pageHeight: 800)
        let word = try XCTUnwrap(words.first { $0.text == "1500" })
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 600, height: 800).contains(word.rect))
        let picked = try XCTUnwrap(PageWords.word(at: CGPoint(x: word.rect.midX, y: word.rect.midY), in: words))
        XCTAssertEqual(words[picked].text, "1500")
        let marks = try await PDFTextReader.shared.matches("Pagina 1500", url: source, index: 1499, pageWidth: 600, pageHeight: 800)
        XCTAssertFalse(marks.isEmpty)
        let count = DocumentRenderCache.shared.pdfOpens
        for page in [pages[0], pages[1499]] {
            let image = DocumentServices.image(page: page, drawing: PKDrawing(), workspace: workspace, maxDimension: 800)
            XCTAssertNotNil(image.cgImage)
        }
        XCTAssertEqual(DocumentRenderCache.shared.pdfOpens - count, 1)
        XCTAssertEqual(PDFDocument(url: source)?.pageCount, 1500)
    }
}
