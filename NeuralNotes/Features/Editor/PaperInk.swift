import SwiftUI
import PencilKit

/// Page colors are physical colors on white paper. PencilKit otherwise adapts
/// ink to the inherited interface appearance, independently of our paper view.
@MainActor
enum PaperInk {
    private static let traits = UITraitCollection(userInterfaceStyle: .light)

    static func configure(_ canvas: PKCanvasView) {
        canvas.overrideUserInterfaceStyle = .light
    }

    static func configureNavigation(_ canvas: PKCanvasView, fingerDrawing: Bool) {
        // Explicitly exclude Pencil from scrolling. It belongs to PencilKit's
        // drawing recognizer; finger drawing reserves two fingers for panning.
        let scrollingTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
                              NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        canvas.panGestureRecognizer.allowedTouchTypes = scrollingTypes
        canvas.panGestureRecognizer.minimumNumberOfTouches = fingerDrawing ? 2 : 1
        let host = canvas.superview as? CanvasHost
        let locked = host?.drawingAssistant?.locksPageNavigation == true || host?.diagramHandles?.isInteracting == true || host?.shapeHandles?.isInteracting == true
        canvas.panGestureRecognizer.isEnabled = !locked
        canvas.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    static func color(_ value: Color) -> UIColor {
        UIColor(cgColor: UIColor(value).resolvedColor(with: traits).cgColor)
    }

    static func image(_ drawing: PKDrawing, from rect: CGRect, scale: CGFloat) -> UIImage {
        var rendered = UIImage()
        traits.performAsCurrent { rendered = drawing.image(from: rect, scale: scale) }
        return rendered
    }

    /// Bake a subtle edge into the transparent drag image once, at gesture start.
    static func selectionPreview(_ drawing: PKDrawing, from rect: CGRect, scale: CGFloat) -> UIImage {
        let ink = image(drawing, from: rect, scale: scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { output in
            output.cgContext.setShadow(offset: .zero, blur: 3 / scale,
                color: UIColor(white: 0.32, alpha: 0.95).cgColor)
            ink.draw(in: CGRect(origin: .zero, size: rect.size))
        }
    }
}
