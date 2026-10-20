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
    static func insert(_ providers: [NSItemProvider], at point: CGPoint, model: EditorViewModel) async {
        guard model.hasLease, !model.interactionBusy else { return }
        for provider in providers.prefix(10) {
            do {
                if provider.hasItemConformingToTypeIdentifier("public.image") {
                    let data: Data = try await withCheckedThrowingContinuation { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                            if let data { continuation.resume(returning: data) } else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                        }
                    }
                    var image = try await DocumentServices.importImage(data: data, into: model.workspace)
                    image.x = max(0, min(Double(point.x), (model.page?.width ?? 768) - image.width)); image.y = max(0, min(Double(point.y), (model.page?.height ?? 1024) - image.height)); model.addImage(image)
                } else if provider.canLoadObject(ofClass: NSURL.self) {
                    let url: URL = try await withCheckedThrowingContinuation { continuation in
                        _ = provider.loadObject(ofClass: NSURL.self) { value, error in
                            if let url = value as? URL { continuation.resume(returning: url) }
                            else { continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)) }
                        }
                    }
                    guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { continue }
                    var element = TextElement(text: url.absoluteString); element.x = max(0, Double(point.x)); element.y = max(0, Double(point.y))
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
                    var element = TextElement(text: text); element.x = max(0, Double(point.x)); element.y = max(0, Double(point.y))
                    model.mutatePage("Trascina testo") { $0.texts.append(element) }
                }
            } catch { model.error = error.localizedDescription }
        }
    }
}
