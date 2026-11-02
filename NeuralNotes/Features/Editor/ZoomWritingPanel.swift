import SwiftUI
import PencilKit
import NeuralNotesCore

@MainActor
struct ZoomWritingPanel: View {
    let model: EditorViewModel
    @State private var controller: ZoomWritingController?
    var body: some View {
        VStack(spacing: 0) {
            if let controller { controls(controller); ZoomWritingCanvas(controller: controller) }
        }
        .background(.regularMaterial)
        .accessibilityIdentifier("zoomWritingPanel")
        .onAppear { if controller == nil { controller = ZoomWritingController(model: model) } }
        .onDisappear { controller?.finishAndClose(); controller = nil; model.configureTool() }
    }
    private func controls(_ controller: ZoomWritingController) -> some View {
        HStack(spacing: 8) {
            Button("Indietro", systemImage: "arrow.left") { controller.step(-1) }.labelStyle(.iconOnly)
            Button("Avanti", systemImage: "arrow.right") { controller.step(1) }.labelStyle(.iconOnly)
            Button("Nuova riga", systemImage: "return") { controller.newLine() }.labelStyle(.iconOnly)
            Text(controller.geometry?.atEnd == true ? "Fine pagina" : "Scrittura zoom").font(.caption)
            Spacer(minLength: 4)
            Text("\(controller.geometry?.zoom ?? 3, specifier: "%.1f")×").font(.caption.monospacedDigit())
            Slider(value: Binding(get: { controller.geometry?.zoom ?? 3 }, set: { controller.setZoom($0) }), in: 2...4, step: 0.25)
                .frame(maxWidth: 140).accessibilityLabel("Ingrandimento finestra di scrittura")
            Menu("Opzioni zoom", systemImage: "slider.horizontal.3") {
                Toggle("Avanza dopo il tratto", isOn: Binding(get: { controller.automatic }, set: { controller.automatic = $0 }))
                Picker("Margine sinistro", selection: Binding(get: { controller.geometry?.leftMargin ?? 24 }, set: { controller.margins(left: $0, right: controller.geometry?.rightMargin ?? 24) })) {
                    Text("0 pt").tag(0.0); Text("24 pt").tag(24.0); Text("48 pt").tag(48.0)
                }
                Picker("Margine destro", selection: Binding(get: { controller.geometry?.rightMargin ?? 24 }, set: { controller.margins(left: controller.geometry?.leftMargin ?? 24, right: $0) })) {
                    Text("0 pt").tag(0.0); Text("24 pt").tag(24.0); Text("48 pt").tag(48.0)
                }
            }.labelStyle(.iconOnly)
            Button("Chiudi finestra di scrittura", systemImage: "xmark") { model.closeZoomWriting() }.labelStyle(.iconOnly)
        }.buttonStyle(.borderless).frame(minHeight: 44).padding(.horizontal, 8)
            .disabled(model.hasActiveStroke)
    }
}

@MainActor
private struct ZoomWritingCanvas: UIViewRepresentable {
    let controller: ZoomWritingController
    func makeUIView(context: Context) -> CanvasHost { controller.host }
    func updateUIView(_ host: CanvasHost, context: Context) {
        controller.refresh()
        context.coordinator.controller = controller
        // Geometry changes after layout, outside SwiftUI's update transaction.
        DispatchQueue.main.async { [weak controller, weak host] in
            if let host { controller?.resize(host.bounds.size) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { weak var controller: ZoomWritingController? }
}

/// One finger moves the page-coordinate writing window. It does not transform ink.
@MainActor
final class ZoomWritingViewport: UIView {
    private weak var controller: ZoomWritingController?
    private weak var host: CanvasHost?
    private var start = CGPoint.zero
    init(controller: ZoomWritingController, host: CanvasHost) {
        self.controller = controller; self.host = host; super.init(frame: .zero)
        backgroundColor = UIColor.systemTeal.withAlphaComponent(0.08); layer.borderColor = UIColor.systemTeal.cgColor; layer.borderWidth = 2; layer.cornerRadius = 4
        accessibilityLabel = "Zona di scrittura ingrandita"; accessibilityIdentifier = "zoomWritingViewport"
        let pan = UIPanGestureRecognizer(target: self, action: #selector(nnMoveWindow(_:)))
        pan.maximumNumberOfTouches = 1; pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { nil }
    func refresh() {
        guard let host, let value = controller?.geometry else { isHidden = true; return }
        let pageBox = CGRect(x: value.x, y: value.y, width: value.width, height: value.height)
        frame = host.surface.convert(pageBox, to: host); isHidden = false
    }
    @objc private func nnMoveWindow(_ gesture: UIPanGestureRecognizer) {
        guard let host, let controller, let geometry = controller.geometry else { return }
        if gesture.state == .began { start = CGPoint(x: geometry.x, y: geometry.y) }
        let delta = gesture.translation(in: host), scale = max(0.05, host.canvas.zoomScale)
        controller.move(to: CGPoint(x: start.x + delta.x / scale, y: start.y + delta.y / scale))
    }
}
