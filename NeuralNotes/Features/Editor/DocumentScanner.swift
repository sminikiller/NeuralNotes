import SwiftUI
import VisionKit
import UniformTypeIdentifiers
import NeuralNotesCore

@MainActor
struct DocumentScanner: UIViewControllerRepresentable {
    let completion: ([UIImage]) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController(); camera.delegate = context.coordinator; return camera
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: ([UIImage]) -> Void
        init(completion: @escaping ([UIImage]) -> Void) { self.completion = completion }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            completion((0..<min(scan.pageCount, 50)).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { completion([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { completion([]) }
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
