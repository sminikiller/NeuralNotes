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
        ViewThatFits(in: .horizontal) {
            fullControls(controller)
            compactControls(controller)
        }.buttonStyle(.borderless).frame(minHeight: 44).padding(.horizontal, 8)
            .disabled(model.hasActiveStroke)
    }
    private func navigation(_ controller: ZoomWritingController) -> some View {
        HStack(spacing: 4) {
            Button("Indietro", systemImage: "arrow.left") { controller.step(-1) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            Button("Avanti", systemImage: "arrow.right") { controller.step(1) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            Button("Nuova riga", systemImage: "return") { controller.newLine() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
    }
    private func closeButton() -> some View {
        Button("Chiudi finestra di scrittura", systemImage: "xmark") { model.closeZoomWriting() }.labelStyle(.iconOnly).frame(width: 44, height: 44)
    }
    private func fullControls(_ controller: ZoomWritingController) -> some View {
        HStack(spacing: 8) {
            navigation(controller)
            Text(controller.geometry?.atEnd == true ? "Fine pagina" : "Scrittura zoom").font(.caption).fixedSize()
            Spacer(minLength: 4)
            Text("\(controller.geometry?.zoom ?? 3, specifier: "%.1f")×").font(.caption.monospacedDigit()).fixedSize()
            Slider(value: Binding(get: { controller.geometry?.zoom ?? 3 }, set: { controller.setZoom($0) }), in: 2...4, step: 0.25)
                .frame(width: 120).accessibilityLabel("Ingrandimento finestra di scrittura")
            options(controller)
            closeButton()
        }
    }
    private func compactControls(_ controller: ZoomWritingController) -> some View {
        HStack(spacing: 2) {
            navigation(controller)
            Group {
                if controller.geometry?.atEnd == true { Text("Fine pagina") }
                else { Text("\(controller.geometry?.zoom ?? 3, specifier: "%.1f")×") }
            }.font(.caption.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            options(controller)
            closeButton()
        }
    }
    private func options(_ controller: ZoomWritingController) -> some View {
        Menu("Opzioni zoom", systemImage: "slider.horizontal.3") {
            Picker("Ingrandimento", selection: Binding(get: { controller.geometry?.zoom ?? 3 }, set: { controller.setZoom($0) })) {
                ForEach([2.0, 2.5, 3, 3.5, 4], id: \.self) { value in Text("\(value, specifier: "%.1f")×").tag(value) }
            }
            Toggle("Avanza dopo il tratto", isOn: Binding(get: { controller.automatic }, set: { controller.automatic = $0 }))
            Picker("Margine sinistro", selection: Binding(get: { controller.geometry?.leftMargin ?? 24 }, set: { controller.margins(left: $0, right: controller.geometry?.rightMargin ?? 24) })) {
                Text("0 pt").tag(0.0); Text("24 pt").tag(24.0); Text("48 pt").tag(48.0)
            }
            Picker("Margine destro", selection: Binding(get: { controller.geometry?.rightMargin ?? 24 }, set: { controller.margins(left: controller.geometry?.leftMargin ?? 24, right: $0) })) {
                Text("0 pt").tag(0.0); Text("24 pt").tag(24.0); Text("48 pt").tag(48.0)
            }
        }.labelStyle(.iconOnly).frame(width: 44, height: 44)
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
        isAccessibilityElement = true; accessibilityTraits = .adjustable
        accessibilityLabel = "Zona di scrittura ingrandita"; accessibilityIdentifier = "zoomWritingViewport"
        accessibilityHint = "Trascina con un dito per spostare la zona; scorri verso l’alto o il basso con VoiceOver per avanzare o tornare indietro."
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
    override func accessibilityIncrement() { controller?.step(1) }
    override func accessibilityDecrement() { controller?.step(-1) }
    @objc private func nnMoveWindow(_ gesture: UIPanGestureRecognizer) {
        guard let host, let controller, let geometry = controller.geometry else { return }
        if gesture.state == .began { start = CGPoint(x: geometry.x, y: geometry.y) }
        let delta = gesture.translation(in: host), scale = max(0.05, host.canvas.zoomScale)
        controller.move(to: CGPoint(x: start.x + delta.x / scale, y: start.y + delta.y / scale))
    }
}
