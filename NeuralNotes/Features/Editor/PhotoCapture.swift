import SwiftUI
import UniformTypeIdentifiers
import NeuralNotesCore

enum PhotoCropGeometry {
    static func fittedSize(image: CGSize, available: CGSize) -> CGSize {
        let imageWidth: CGFloat = max(1.0, image.width)
        let imageHeight: CGFloat = max(1.0, image.height)
        let horizontalScale: CGFloat = max(0.0, available.width) / imageWidth
        let verticalScale: CGFloat = max(0.0, available.height) / imageHeight
        let scale: CGFloat = min(horizontalScale, verticalScale)
        return CGSize(width: imageWidth * scale, height: imageHeight * scale)
    }

    static func frame(crop: NormalizedCrop, size: CGSize) -> CGRect {
        let x: CGFloat = size.width * CGFloat(crop.x)
        let y: CGFloat = size.height * CGFloat(crop.y)
        let width: CGFloat = size.width * CGFloat(crop.width)
        let height: CGFloat = size.height * CGFloat(crop.height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func square(image: CGSize) -> NormalizedCrop {
        let imageWidth: Double = max(1.0, Double(image.width))
        let imageHeight: Double = max(1.0, Double(image.height))
        let width: Double = min(1.0, imageHeight / imageWidth)
        let height: Double = min(1.0, imageWidth / imageHeight)
        let x: Double = (1.0 - width) / 2.0
        let y: Double = (1.0 - height) / 2.0
        return NormalizedCrop(x: x, y: y, width: width, height: height)
    }

    static func dragged(start: CGPoint, end: CGPoint, size: CGSize) -> NormalizedCrop {
        let width: Double = max(1.0, Double(size.width))
        let height: Double = max(1.0, Double(size.height))
        let x: Double = Double(min(start.x, end.x)) / width
        let y: Double = Double(min(start.y, end.y)) / height
        let selectedWidth: Double = Double(abs(end.x - start.x)) / width
        let selectedHeight: Double = Double(abs(end.y - start.y)) / height
        return NormalizedCrop(x: x, y: y, width: selectedWidth, height: selectedHeight)
    }
}

@MainActor
struct CameraCapture: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera; picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo; picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}

@MainActor
struct PhotoCropPanel: View {
    let image: UIImage
    var initial: NormalizedCrop = .full
    let completion: (NormalizedCrop) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var crop = NormalizedCrop.full

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Trascina per scegliere l’area. L’immagine originale rimane conservata.").font(.callout).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    let size: CGSize = PhotoCropGeometry.fittedSize(image: image.size, available: geometry.size)
                    let selected: CGRect = PhotoCropGeometry.frame(crop: crop, size: size)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        Rectangle().fill(.black.opacity(0.15))
                        Rectangle().stroke(.teal, lineWidth: 3).background(.teal.opacity(0.08))
                            .frame(width: selected.width, height: selected.height)
                            .offset(x: selected.minX, y: selected.minY)
                    }
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                        crop = PhotoCropGeometry.dragged(start: value.startLocation, end: value.location, size: size)
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Button("Tutto", systemImage: "arrow.up.left.and.arrow.down.right") { crop = .full }
                    Button("Quadrato", systemImage: "square") {
                        crop = PhotoCropGeometry.square(image: image.size)
                    }
                }.buttonStyle(.bordered)
            }.padding()
            .navigationTitle("Ritaglia foto")
            .onAppear { crop = initial }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Usa ritaglio") { completion(crop); dismiss() } }
            }
        }
    }
}
