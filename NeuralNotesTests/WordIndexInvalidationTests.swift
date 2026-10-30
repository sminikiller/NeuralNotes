import XCTest
import UIKit
import NeuralNotesCore
@testable import NeuralNotes

private actor DeferredWordReader {
    private(set) var started = false
    private var released = false
    private var resume: CheckedContinuation<Void, Never>?
    func read(_ data: Data) async -> [PageWord] {
        started = true
        if !released { await withCheckedContinuation { resume = $0 } }
        return [PageWord(text: "VECCHIO", rect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1))]
    }
    func release() { released = true; resume?.resume(); resume = nil }
}

final class WordIndexInvalidationTests: XCTestCase {
    @MainActor func testLateScanOCRCannotPublishWordsAfterInkWasChanged() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do {
        let file = root.appendingPathComponent("scan.pdf"), bounds = CGRect(x: 0, y: 0, width: 600, height: 800)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: file) { renderer in renderer.beginPage(); UIColor.white.setFill(); renderer.cgContext.fill(bounds) }
        await model.importPages(from: file)
        let page = try XCTUnwrap(model.page), gate = DeferredWordReader()
        XCTAssertNotNil(page.pdfFile)
        defer { Task { await gate.release() } }
        let index = PageWordIndex { data in await gate.read(data) }
        index.prepare(page, model: model)
        let startDeadline = Date().addingTimeInterval(10)
        while !(await gate.started), Date() < startDeadline { try await Task.sleep(for: .milliseconds(20)) }
        let started = await gate.started; XCTAssertTrue(started)
        index.invalidate(page)
        await gate.release()
        let finishDeadline = Date().addingTimeInterval(10)
        while index.isPreparing(page), Date() < finishDeadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(index.isPreparing(page)); XCTAssertFalse(index.isReady(page))
        XCTAssertTrue(index.markerWords(page).isEmpty)
        _ = await model.close()
        } catch { _ = await model.close(); throw error }
    }
}
