import SwiftUI
import PhotosUI
import VisionKit
import AVFoundation
import UniformTypeIdentifiers

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
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                Task { @MainActor in
                    if let data { self.completion(.success(data)) }
                    else { self.completion(.failure(error ?? CocoaError(.fileReadCorruptFile))) }
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
