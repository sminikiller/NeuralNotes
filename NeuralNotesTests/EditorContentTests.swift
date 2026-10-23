import XCTest
import PencilKit
import PDFKit
import SwiftUI
import NeuralNotesCore
@testable import NeuralNotes

final class EditorContentTests: XCTestCase {
    @MainActor
    func testInkAndCanvasKeepPhysicalColorsInDarkAndLightChrome() throws {
        let workspace = DocumentWorkspace(package: FileManager.default.temporaryDirectory,
            documentID: UUID(), notebookID: UUID())
        let model = EditorViewModel(workspace: workspace)
        let host = CanvasHost(canvas: model.canvas)
        for style in [UIUserInterfaceStyle.light, .dark] {
            host.overrideUserInterfaceStyle = style
            for (color, expected) in [(Color.black, CGFloat(0)), (Color.white, CGFloat(1))] {
                model.ink = color; model.configureTool()
                XCTAssertEqual(model.canvas.traitCollection.userInterfaceStyle, .light)
                XCTAssertEqual(host.surface.traitCollection.userInterfaceStyle, .light)
                let tool = try XCTUnwrap(model.canvas.tool as? PKInkingTool)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(tool.color.getRed(&r, green: &g, blue: &b, alpha: &a))
                XCTAssertEqual(r, expected, accuracy: 0.01)
                XCTAssertEqual(g, expected, accuracy: 0.01)
                XCTAssertEqual(b, expected, accuracy: 0.01)
            }
        }
    }
    private struct CosineFixture: EmbeddingService {
        func embed(_ texts: [String]) async throws -> [[Float]] { [[1, 0], [0, 1], [1, 0]] }
    }

    func testSemanticRetrieverRanksActualVectorsByCosine() async throws {
        let reference = SourceReference(documentID: UUID())
        let chunks = [IndexedChunk(text: "Primo", reference: reference), IndexedChunk(text: "Secondo", reference: reference)]
        let ranked = try await SemanticRetrievalService(embeddings: CosineFixture()).retrieve(question: "Domanda", from: chunks, limit: 1)
        XCTAssertEqual(ranked.first?.text, "Secondo")
    }

    @MainActor
    func testPencilKitVectorRoundTripAndPDFExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root)
        let manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let workspace = DocumentWorkspace(package: store.packageURL(for: manifest.documentID),
            documentID: manifest.documentID, notebookID: manifest.notebookID)
        let points = [CGPoint(x: 20, y: 30), CGPoint(x: 150, y: 100)].enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index), size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue),
            path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        var page = try await workspace.addPage(); page.revision = 1
        page.texts = [TextElement(text: "Testo vettoriale")]
        let saved = try await workspace.save(page, drawing: drawing.dataRepresentation())
        let optionalBytes = try await workspace.drawing(saved)
        let bytes = try XCTUnwrap(optionalBytes)
        let reopened = try PKDrawing(data: bytes)
        XCTAssertEqual(reopened.strokes.count, drawing.strokes.count)
        XCTAssertEqual(reopened.bounds, drawing.bounds)
        let pdfURL = try await DocumentServices.exportPDF(workspace: workspace)
        defer { try? FileManager.default.removeItem(at: pdfURL) }
        let pdf = try XCTUnwrap(PDFDocument(url: pdfURL))
        XCTAssertEqual(pdf.pageCount, 1)
        XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Testo vettoriale") == true)
    }

    func testLocalStudyUsesOnlySuppliedReferences() async throws {
        let reference = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 4)
        let original = "La fotosintesi converte energia luminosa in energia chimica all’interno delle cellule vegetali."
        let artifact = try await ExtractiveStudyProvider().generate(AIRequest(task: .summarize, question: "",
            sources: [IndexedChunk(text: original, reference: reference)]))
        XCTAssertEqual(artifact.references, [reference])
        XCTAssertTrue(artifact.text.contains("fotosintesi"))
        XCTAssertEqual(artifact.task, .summarize)
    }

    func testRemoteBackendRequiresHTTPSBeforeAnyNetworkRequest() async throws {
        let provider = RemoteAIProvider(endpoint: try XCTUnwrap(URL(string: "http://invalid.example/study")), sessionToken: "test")
        do {
            _ = try await provider.generate(AIRequest(task: .chat, question: "Test", sources: []))
            XCTFail("HTTP endpoint accepted")
        } catch AIConnectionFailure.configuration { }
    }

    func testLocalStudyTaskModesPreserveSourcesAfterCompilerCompatibilityFix() async throws {
        let first = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 1)
        let second = SourceReference(documentID: UUID(), pageID: UUID(), pageRevision: 2)
        let sources = [
            IndexedChunk(text: "La fotosintesi trasforma energia luminosa in energia chimica nelle cellule vegetali.", reference: first),
            IndexedChunk(text: "La respirazione rende disponibile energia chimica per le attività delle cellule.", reference: second)
        ]
        for task in AITask.allCases {
            let request = AIRequest(task: task, question: "energia cellule", sources: sources)
            let artifact = try await ExtractiveStudyProvider().generate(request)
            XCTAssertEqual(artifact.task, task)
            XCTAssertFalse(artifact.references.isEmpty, task.rawValue)
            XCTAssertTrue(artifact.references.allSatisfy { [first, second].contains($0) }, task.rawValue)
            XCTAssertFalse(artifact.text.contains("Nessun passaggio"), task.rawValue)
            let repeated = try await ExtractiveStudyProvider().generate(request)
            XCTAssertEqual(artifact.text, repeated.text, task.rawValue)
            XCTAssertEqual(artifact.references, repeated.references, task.rawValue)
        }
    }
}
