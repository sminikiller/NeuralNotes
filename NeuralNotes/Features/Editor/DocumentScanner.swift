import SwiftUI
import VisionKit
import UniformTypeIdentifiers
import NeuralNotesCore

@MainActor
struct DocumentScanner: UIViewControllerRepresentable {
    let completion: (Result<VNDocumentCameraScan?, Error>) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController(); camera.delegate = context.coordinator; return camera
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (Result<VNDocumentCameraScan?, Error>) -> Void
        init(completion: @escaping (Result<VNDocumentCameraScan?, Error>) -> Void) { self.completion = completion }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion(.success(scan))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completion(.success(nil)) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion(.failure(error)) }
    }
}

@MainActor
extension EditorViewModel {
    func importScan(_ scan: VNDocumentCameraScan) async {
        for index in 0..<scan.pageCount {
            do {
                try Task.checkCancellation()
                // Decode and normalize one page at a time; do not hold a second
                // array of full camera-resolution images in memory.
                let bytes: Data = try autoreleasepool {
                    let source = scan.imageOfPage(at: index)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = min(1, 2400 / max(1, max(source.size.width, source.size.height)))
                    let image = UIGraphicsImageRenderer(size: source.size, format: format).image { _ in source.draw(at: .zero) }
                    guard let data = image.jpegData(compressionQuality: 0.9) else { throw CocoaError(.fileReadCorruptFile) }
                    return data
                }
                if index > 0 {
                    let previous = page?.id; await addPage()
                    guard page?.id != previous else { throw CocoaError(.fileWriteUnknown) }
                }
                addImage(try await DocumentServices.importImage(data: bytes, into: workspace))
                guard await flush() else { return }
            } catch { self.error = "Scansione interrotta alla pagina \(index + 1): \(error.localizedDescription). Le pagine già importate restano salvate."; return }
        }
    }
}

@MainActor
enum PageDrop {
    private enum DropFailure: LocalizedError {
        case busy
        var errorDescription: String? { "La pagina è occupata: rilascia la Pencil o termina la modifica del testo, poi trascina di nuovo." }
    }
    private static func requireTarget(_ id: UUID, model: EditorViewModel) throws {
        guard model.page?.id == id, model.hasLease, !model.navigating, !model.loading else { throw WorkspaceFailure.staleRevision }
        guard !model.interactionBusy else { throw DropFailure.busy }
    }
    static func insert(_ providers: [NSItemProvider], at point: CGPoint, model: EditorViewModel) async {
        guard model.hasLease, !model.loading, !model.navigating, !model.interactionBusy, let originID = model.page?.id else { return }
        for provider in providers.prefix(10) {
            do {
                try Task.checkCancellation()
                try requireTarget(originID, model: model)
                if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .pdf) == true }) {
                    let file = try await temporaryFile(provider, type: type)
                    defer { try? FileManager.default.removeItem(at: file) }
                    try requireTarget(originID, model: model)
                    await model.importPages(from: file); return
                } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                    let file = try await temporaryFile(provider, type: type)
                    defer { try? FileManager.default.removeItem(at: file) }
                    try requireTarget(originID, model: model)
                    var image = try await DocumentServices.importImage(from: file, into: model.workspace)
                    try requireTarget(originID, model: model)
                    image.x = max(0, min(Double(point.x), (model.page?.width ?? 768) - image.width))
                    image.y = max(0, min(Double(point.y), (model.page?.height ?? 1024) - image.height)); model.addImage(image)
                } else if provider.canLoadObject(ofClass: NSURL.self) {
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        _ = provider.loadObject(ofClass: NSURL.self) { value, error in
                            if let url = value as? URL { continuation.resume(returning: url) }
                            else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                        }
                    }
                    try requireTarget(originID, model: model)
                    if url.isFileURL, UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                        await model.importPages(from: url); return
                    }
                    guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { continue }
                    var element = positionedText(String(url.absoluteString.prefix(100_000)), at: point, model: model)
                    element.rtf = RichText.data(NSAttributedString(string: element.text, attributes: [.link: url, .font: UIFont.systemFont(ofSize: 24)]))
                    model.mutatePage("Trascina collegamento") { $0.texts.append(element) }
                } else if provider.canLoadObject(ofClass: NSString.self) {
                    let text: String = try await withCheckedThrowingContinuation { continuation in
                        _ = provider.loadObject(ofClass: NSString.self) { value, error in
                            if let text = value as? String { continuation.resume(returning: text) }
                            else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                        }
                    }
                    guard text.count <= 100_000 else { throw WorkspaceFailure.oversizedImport }
                    try requireTarget(originID, model: model)
                    let element = positionedText(text, at: point, model: model)
                    model.mutatePage("Trascina testo") { $0.texts.append(element) }
                }
            } catch is CancellationError { return }
            catch { model.error = error.localizedDescription; return }
        }
    }
    private static func positionedText(_ value: String, at point: CGPoint, model: EditorViewModel) -> TextElement {
        var text = TextElement(text: value)
        text.x = max(0, min(Double(point.x), (model.page?.width ?? 768) - 20))
        text.y = max(0, min(Double(point.y), (model.page?.height ?? 1024) - 20)); return text
    }
    private static func temporaryFile(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { source, error in
                do {
                    guard let source else { throw error ?? CocoaError(.fileReadCorruptFile) }
                    let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
                    let suffix = UTType(type)?.preferredFilenameExtension ?? "bin"
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent("NN-drop-\(UUID()).\(suffix)")
                    // The provider URL expires when its callback returns.
                    try FileManager.default.copyItem(at: source, to: file)
                    continuation.resume(returning: file)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
