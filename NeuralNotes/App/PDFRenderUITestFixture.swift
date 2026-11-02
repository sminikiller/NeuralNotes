#if DEBUG
import UIKit
import NeuralNotesCore

/// Only installed behind both UI-test flags in AppController's isolated store.
@MainActor
enum PDFRenderUITestFixture {
    static func install(repository: SwiftDataLibraryRepository, documents: NativeDocumentStore) throws {
        let notebook = try repository.createNotebook(title: "PDF performance test", folderID: nil, cover: .lagoon)
        let package = documents.packageURL(for: notebook.documentID), file = "attachments/render-fixture.pdf"
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).writePDF(to: package.appendingPathComponent(file)) { output in
            for number in 1...6 {
                output.beginPage()
                ("Energia conservata pagina \(number)" as NSString).draw(at: CGPoint(x: 40, y: 250), withAttributes: [.font: UIFont.systemFont(ofSize: 22), .foregroundColor: UIColor.black])
                output.cgContext.setStrokeColor(UIColor.lightGray.cgColor); output.cgContext.setLineWidth(0.3)
                for i in 0..<1800 {
                    let y = CGFloat(i % 380) + 360
                    output.cgContext.move(to: CGPoint(x: CGFloat(i % 40) + 30, y: y))
                    output.cgContext.addLine(to: CGPoint(x: 560, y: y + 3)); output.cgContext.strokePath()
                }
            }
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var pages: [PageSnapshot] = []
        for i in 0..<6 {
            var page = PageSnapshot(); page.width = 600; page.height = 800; page.paper = .plain
            page.pdfFile = file; page.pdfIndex = i
            try encoder.encode(page).write(to: package.appendingPathComponent("pages/\(page.id.uuidString).json"), options: .atomic)
            pages.append(page)
        }
        var manifest = try documents.read(documentID: notebook.documentID, notebookID: notebook.id)
        manifest.pageIDs = pages.map(\.id)
        try encoder.encode(manifest).write(to: package.appendingPathComponent("manifest.json"), options: .atomic)
    }
}
#endif
