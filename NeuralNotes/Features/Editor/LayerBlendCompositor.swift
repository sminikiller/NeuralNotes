import UIKit

/// Normal source-over and Multiply are affine in the opaque backdrop: F(c)=a*c+b.
/// Render the layer over black (b) and white (w=a+b), then use two standard PDF
/// blend modes: Multiply by (w-b)/(1-b), followed by Screen with b. Their result
/// is a*c+b. This preserves non-isolated markers AND whole-group opacity without
/// replaying the PDF/backdrop inside each layer or rasterizing PDF ink paths.
/// White/black probes include group opacity before deriving these coefficients.
/// Standard blend equations: ISO32000-1 table136 (Screen, Difference, ColorDodge).
@MainActor
enum LayerBlendCompositor {
    struct Maps {
        let multiply: UIImage
        let screen: UIImage
        var byteCost: Int {
            [multiply, screen].reduce(0) { $0 + ($1.cgImage.map { $0.bytesPerRow * $0.height } ?? 0) }
        }
        func draw(in context: CGContext, bounds: CGRect) {
            context.saveGState()
            context.setAlpha(1); context.setBlendMode(.multiply); multiply.draw(in: bounds)
            context.setBlendMode(.screen); screen.draw(in: bounds)
            context.restoreGState()
        }
    }

    /// The closure paints content only, with Normal/Multiply operations and no
    /// paper/PDF. Existing export callers keep their single backdrop drawing.
    /// For opaque groups the original vector commands can be emitted directly.
    static func drawGroup(opacity: Double, bounds: CGRect, in context: CGContext,
                          content: (CGContext) -> Void) {
        guard opacity.isFinite, opacity > 0, !bounds.isEmpty else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.clip(to: bounds)
        if opacity >= 1 { content(context); return }
        context.setAlpha(1); context.setBlendMode(.multiply)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.normal)
        coefficient(opacity: opacity, bounds: bounds, in: context, content: content)
        context.endTransparencyLayer()
        context.setAlpha(1); context.setBlendMode(.screen)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        probe(white: false, opacity: opacity, bounds: bounds, in: context, content: content)
        context.endTransparencyLayer()
    }

    /// Cache two opaque maps, never an opaque picture of the actual paper.
    /// The caller bounds region/scale and charges both images to its cache.
    static func maps(opacity: Double, bounds: CGRect, scale: CGFloat,
                     content: (CGContext) -> Void) -> Maps? {
        guard opacity.isFinite, (0...1).contains(opacity), scale.isFinite, scale > 0,
              [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite),
              bounds.width > 0, bounds.height > 0,
              bounds.width * scale <= 8192, bounds.height * scale <= 8192,
              bounds.width * bounds.height * scale * scale <= 4_000_000 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = scale; format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        func render(_ action: (CGContext) -> Void) -> UIImage {
            renderer.image { result in
                let context = result.cgContext
                context.translateBy(x: -bounds.minX, y: -bounds.minY)
                action(context)
            }
        }
        let black = render { probe(white: false, opacity: opacity, bounds: bounds, in: $0, content: content) }
        let multiplier = render { context in
            probe(white: true, opacity: opacity, bounds: bounds, in: context, content: content)
            context.setBlendMode(.difference); black.draw(in: bounds)
            context.setBlendMode(.colorDodge); black.draw(in: bounds)
        }
        return Maps(multiply: multiplier, screen: black)
    }

    private static func coefficient(opacity: Double, bounds: CGRect, in context: CGContext,
                                    content: (CGContext) -> Void) {
        context.saveGState()
        context.setAlpha(1); context.setBlendMode(.normal)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        probe(white: true, opacity: opacity, bounds: bounds, in: context, content: content)
        context.setBlendMode(.difference)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        probe(white: false, opacity: opacity, bounds: bounds, in: context, content: content)
        context.endTransparencyLayer()
        context.setBlendMode(.colorDodge)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        probe(white: false, opacity: opacity, bounds: bounds, in: context, content: content)
        context.endTransparencyLayer()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func probe(white: Bool, opacity: Double, bounds: CGRect, in context: CGContext,
                              content: (CGContext) -> Void) {
        context.saveGState(); defer { context.restoreGState() }
        let color = white ? UIColor.white.cgColor : UIColor.black.cgColor
        context.setAlpha(1); context.setBlendMode(.normal)
        context.setFillColor(color); context.fill(bounds)
        guard opacity > 0 else { return }
        context.setAlpha(CGFloat(min(1, opacity)))
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setAlpha(1); context.setBlendMode(.normal)
        context.setFillColor(color); context.fill(bounds)
        content(context)
        context.endTransparencyLayer()
    }
}
