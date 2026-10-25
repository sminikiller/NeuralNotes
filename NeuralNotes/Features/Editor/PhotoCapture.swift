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
    var adjustment = PhotoAdjustment()
    var straighten = false
    var title = "Modifica foto"
    var confirm = "Usa foto"
    var hint = "L’originale resta conservato. Puoi modificare di nuovo o annullare."
    let completion: (PhotoAdjustment) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var edit = PhotoAdjustment()
    @State private var mode = 0
    @State private var preview: UIImage?
    @State private var detecting = false
    @State private var rendering = false
    @State private var notice = ""
    @State private var dragPoint: CGPoint?
    @State private var editGeneration = 0

    private var quad: PerspectiveQuad { edit.perspective ?? .full }
    private var previewKey: String { "\(mode)|\(mode == 0 ? String(describing: edit.perspective) : "corners")|\(edit.quarterTurns)|\(edit.enhanced)" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Modifica foto", selection: $mode) { Text("Rettangolo").tag(0); Text("Raddrizza").tag(1) }.pickerStyle(.segmented)
                Text(notice.isEmpty ? hint : notice).font(.caption).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    let picture = preview ?? image
                    let size = PhotoCropGeometry.fittedSize(image: picture.size, available: geometry.size)
                    photoCanvas(picture, size: size).frame(width: size.width, height: size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                controls
            }.padding().navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirm) { completion(edit); dismiss() }
                            .disabled(detecting || rendering || !quad.isConvex || quad.outputSize(for: .init(width: image.size.width, height: image.size.height)) == nil)
                            .accessibilityIdentifier("photoCropConfirm")
                    }
                }
        }.onAppear { edit = adjustment; edit.crop = initial; mode = straighten ? 1 : 0 }
            .task(id: previewKey) { await updatePreview() }
            .task { if straighten, adjustment.perspective == nil { await detect() } }
            .onChange(of: mode) { _, value in
                editGeneration += 1
                if value == 1, edit.perspective == nil { Task { await detect() } }
            }
    }

    private var controls: some View {
        ViewThatFits {
            HStack { editButtons }
            VStack { editButtons }
        }.buttonStyle(.bordered)
    }
    @ViewBuilder private var editButtons: some View {
        Button("Tutto", systemImage: "arrow.up.left.and.arrow.down.right") {
            editGeneration += 1; edit.crop = .full
            if mode == 1 { edit.perspective = .full }
        }
        if mode == 1 {
            Button("Rileva bordi", systemImage: "viewfinder") { Task { await detect() } }.disabled(detecting)
        } else {
            Button("Quadrato", systemImage: "square") { edit.crop = PhotoCropGeometry.square(image: (preview ?? image).size) }
        }
        Button { rotate(-1) } label: { Image(systemName: "rotate.left") }.accessibilityLabel("Ruota di 90 gradi a sinistra")
        Button { rotate(1) } label: { Image(systemName: "rotate.right") }.accessibilityLabel("Ruota di 90 gradi a destra")
        Button { edit.enhanced.toggle() } label: { Label("Migliora", systemImage: edit.enhanced ? "checkmark.circle.fill" : "wand.and.stars") }
            .tint(edit.enhanced ? Color.teal : Color.accentColor)
            .accessibilityIdentifier("photoEnhance").accessibilityValue(edit.enhanced ? "Attivo" : "Disattivo")
        if detecting || rendering { ProgressView() }
    }

    private func photoCanvas(_ picture: UIImage, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: picture).resizable().frame(width: size.width, height: size.height)
            if mode == 1 {
                quadOutline(size: size)
                ForEach(0..<4, id: \.self) { index in corner(index, size: size) }
                if let finger = dragPoint { magnifier(picture, at: finger, size: size) }
            } else {
                Rectangle().fill(.black.opacity(0.12)).allowsHitTesting(false)
                let box = PhotoCropGeometry.frame(crop: edit.crop, size: size)
                Rectangle().stroke(.teal, lineWidth: 2).background(.teal.opacity(0.06))
                    .frame(width: box.width, height: box.height).offset(x: box.minX, y: box.minY).allowsHitTesting(false)
            }
        }.coordinateSpace(name: "photoQuad").contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                guard mode == 0 else { return }
                let crop = PhotoCropGeometry.dragged(start: value.startLocation, end: value.location, size: size)
                if crop.width >= 0.01, crop.height >= 0.01 { edit.crop = crop }
            }, including: mode == 0 ? .all : .subviews)
    }

    private func quadOutline(size: CGSize) -> some View {
        Path { path in
            let points = quad.points.map { displayed($0, size: size) }
            path.addLines(points); path.closeSubpath()
        }.fill(.teal.opacity(0.12)).overlay {
            Path { path in path.addLines(quad.points.map { displayed($0, size: size) }); path.closeSubpath() }
                .stroke(.teal, lineWidth: 2)
        }.allowsHitTesting(false)
    }
    private func corner(_ index: Int, size: CGSize) -> some View {
        let point = displayed(quad.points[index], size: size)
        return Circle().fill(.white).frame(width: 16, height: 16).overlay(Circle().stroke(.teal, lineWidth: 3))
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .accessibilityLabel("Angolo foto \(index + 1)")
            .accessibilityIdentifier("photoCorner-\(index)")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("photoQuad"))
                .onChanged { value in
                    guard !rendering else { return }
                    editGeneration += 1
                    let x = min(1, max(0, value.location.x / max(1, size.width)))
                    let y = min(1, max(0, value.location.y / max(1, size.height)))
                    let p: PerspectivePoint
                    switch edit.quarterTurns {
                    case 1: p = .init(x: y, y: 1 - x)
                    case 2: p = .init(x: 1 - x, y: 1 - y)
                    case 3: p = .init(x: 1 - y, y: x)
                    default: p = .init(x: x, y: y)
                    }
                    var points = quad.points; points[index] = p
                    let candidate = PerspectiveQuad(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3])
                    if candidate.isConvex { edit.perspective = candidate; edit.crop = .full }
                    dragPoint = CGPoint(x: x * size.width, y: y * size.height)
                }.onEnded { _ in dragPoint = nil }).position(point)
    }
    private func displayed(_ p: PerspectivePoint, size: CGSize) -> CGPoint {
        let q: PerspectivePoint
        switch edit.quarterTurns {
        case 1: q = .init(x: 1 - p.y, y: p.x)
        case 2: q = .init(x: 1 - p.x, y: 1 - p.y)
        case 3: q = .init(x: p.y, y: 1 - p.x)
        default: q = p
        }
        return CGPoint(x: q.x * size.width, y: q.y * size.height)
    }
    private func magnifier(_ picture: UIImage, at finger: CGPoint, size: CGSize) -> some View {
        Image(uiImage: picture).resizable().frame(width: size.width * 2.5, height: size.height * 2.5)
            .offset(x: 44 - finger.x * 2.5, y: 44 - finger.y * 2.5)
            .frame(width: 88, height: 88, alignment: .topLeading).clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 5)
            .position(x: min(max(44, finger.x), max(44, size.width - 44)), y: min(finger.y + 76, max(44, size.height - 44)))
            .allowsHitTesting(false)
    }
    private func rotate(_ amount: Int) {
        editGeneration += 1; edit.quarterTurns = (edit.quarterTurns + amount + 4) % 4; edit.crop = .full
    }
    private func updatePreview() async {
        // Moving a corner only redraws four points, never a full resolution filter.
        if mode == 1, dragPoint != nil { return }
        var value = edit; value.crop = .full
        if mode == 1 { value.perspective = nil }
        rendering = true
        let result = await Task.detached(priority: .userInitiated) { PhotoPerspective.render(image, adjustment: value, maxDimension: 1600) }.value
        guard !Task.isCancelled else { return }
        preview = result; rendering = false
    }
    private func detect() async {
        guard !detecting else { return }
        detecting = true; let generation = editGeneration
        let detected = await PhotoPerspective.detect(image)
        defer { detecting = false }
        guard !Task.isCancelled, generation == editGeneration else { return }
        if let detected { edit.perspective = detected; edit.crop = .full; notice = "Regola i quattro angoli, poi conferma." }
        else { notice = "Bordi non rilevati: trascina i quattro angoli." }
    }
}

#if DEBUG
/// Isolated UI harness: the same crop editor, without camera permissions or personal notebooks.
@MainActor
struct PhotoCropUITestHost: View {
    @State private var showing = true
    @State private var edit = PhotoAdjustment(perspective: .full)
    private var image: UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1000), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 1000))
            UIColor.systemTeal.setStroke(); context.cgContext.setLineWidth(8); context.cgContext.stroke(CGRect(x: 80, y: 100, width: 640, height: 800))
            let text = "NEURALNOTES\nRaddrizza la foto\nOriginale conservato"
            (text as NSString).draw(in: CGRect(x: 120, y: 200, width: 560, height: 400), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
        }
    }
    var body: some View {
        VStack {
            Text("Rotazione \(edit.quarterTurns) · migliora \(edit.enhanced ? "sì" : "no") · bordi \(edit.perspective == .full ? "no" : "sì")").accessibilityIdentifier("photoTestResult")
            Button("Riapri foto") { showing = true }
        }.fullScreenCover(isPresented: $showing) {
            PhotoCropPanel(image: image, initial: edit.crop, adjustment: edit, straighten: true) { edit = $0 }
        }
    }
}
#endif
