import SwiftUI
import PDFKit
import NeuralNotesCore

struct PDFResearchTerm: Identifiable {
    let id = UUID()
    let text: String
}

/// Pencil gestures are opt-in. Finger scrolling and PDFKit's native selection
/// remain available, and no annotation is written to an external document.
@MainActor
final class ConceptPDFView: PDFView, UIGestureRecognizerDelegate {
    var conceptMode = false { didSet { conceptGesture.isEnabled = conceptMode } }
    var onConcept: ((String) -> Void)?
    private var trace: [StrokeSample] = []
    private weak var tracePage: PDFPage?
    private let traceLayer = CAShapeLayer()
    private lazy var conceptGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(concept(_:)))
        gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        gesture.maximumNumberOfTouches = 1; gesture.cancelsTouchesInView = true
        gesture.delegate = self; gesture.isEnabled = false
        return gesture
    }()
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(conceptGesture)
        traceLayer.fillColor = UIColor.clear.cgColor; traceLayer.strokeColor = UIColor.systemTeal.cgColor
        traceLayer.lineWidth = 2; traceLayer.lineCap = .round; layer.addSublayer(traceLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        conceptMode && touch.type == .pencil
    }
    @objc private func concept(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            trace = []; tracePage = page(for: point, nearest: false)
            append(point)
        case .changed: append(point)
        case .ended:
            append(point); defer { trace = []; tracePage = nil; traceLayer.path = nil }
            onConcept?(selectedConcept(trace: trace, page: tracePage) ?? "")
        default: trace = []; tracePage = nil; traceLayer.path = nil
        }
    }
    private func append(_ point: CGPoint) {
        trace.append(StrokeSample(x: Double(point.x), y: Double(point.y)))
        if trace.count > 2000 { trace = trace.enumerated().filter { $0.offset % 2 == 0 || $0.offset == trace.count - 1 }.map(\.element) }
        let path = UIBezierPath()
        for (index, sample) in trace.enumerated() {
            let p = CGPoint(x: sample.x, y: sample.y)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        traceLayer.path = path.cgPath
    }
    func selectedConcept(trace: [StrokeSample], page: PDFPage?) -> String? {
        guard let page, let box = LensGeometry.selection(trace: trace, pageWidth: bounds.width, pageHeight: bounds.height) else { return nil }
        let selected = page.selection(for: convert(box, to: page))
        if let selected { setCurrentSelection(selected, animate: true) }
        return selected?.string
    }
}

@MainActor
struct PDFResearchSheet: View {
    let model: EditorViewModel
    let term: String
    @State private var configuration = AIEngineStore.load()
    @State private var consentKey: String?
    @State private var configuring = false
    var body: some View {
        LookupPanel(model: model, sources: [], configuration: configuration, consentKey: consentKey,
            initialTerm: term, onConfigure: { configuring = true })
            .sheet(isPresented: $configuring) { AIConnectionPanel(configuration: $configuration, consentKey: $consentKey) }
    }
}
