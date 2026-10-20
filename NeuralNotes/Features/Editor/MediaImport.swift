import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation
import UniformTypeIdentifiers
import NeuralNotesCore

enum EditorMedia: String, Identifiable { case photos, camera, scanner; var id: String { rawValue } }

@MainActor
struct PhotoLibraryImport: UIViewControllerRepresentable {
    let completion: (Result<Data?, Error>) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images; config.selectionLimit = 1; config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator
        picker.view.accessibilityViewIsModal = true
        return picker
    }
    func updateUIViewController(_ picker: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<Data?, Error>) -> Void
        init(_ completion: @escaping (Result<Data?, Error>) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else { completion(.success(nil)); return }
            picker.view.isUserInteractionEnabled = false
            load(provider)
        }
        func load(_ provider: NSItemProvider) {
            // Some providers expose JPEG/HEIC/PNG but cannot vend the abstract
            // public.image representation. Ask for their concrete image type.
            guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else {
                completion(.failure(CocoaError(.fileReadUnknown))); return
            }
            provider.loadFileRepresentation(forTypeIdentifier: type) { file, error in
                let result: Result<Data?, Error>
                do {
                    guard let file else { throw error ?? CocoaError(.fileReadCorruptFile) }
                    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0, size <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
                    // The provider's temporary URL is valid only in this callback.
                    let data = try Data(contentsOf: file)
                    guard data.count <= 100 * 1024 * 1024 else { throw WorkspaceFailure.oversizedImport }
                    result = .success(data)
                } catch { result = .failure(error) }
                Task { @MainActor in
                    self.completion(result)
                }
            }
        }
    }
}

@MainActor
enum CameraAccess {
    static func request(scanner: Bool = false) async throws {
        guard UIImagePickerController.isSourceTypeAvailable(.camera), !scanner || VNDocumentCameraViewController.isSupported else {
            throw Failure.unavailable
        }
        guard Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil else { throw Failure.configuration }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else { throw Failure.denied }
    }
    enum Failure: LocalizedError {
        case unavailable, configuration, denied
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Fotocamera non disponibile in questa esecuzione. Puoi inserire una foto dalla libreria o da File."
            case .configuration: return "La funzionalità Fotocamera deve essere abilitata nel progetto Swift Playground."
            case .denied: return "Accesso alla fotocamera negato. Puoi abilitarlo nelle impostazioni dell’iPad o inserire una foto dalla libreria."
            }
        }
    }
}
