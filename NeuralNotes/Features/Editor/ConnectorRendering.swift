import UIKit
import NeuralNotesCore

@MainActor
enum ConnectorRendering {
    static func draw(_ connector: ConnectorElement, objects: [UUID: ConnectorObject], page: PageSnapshot?, context: CGContext) {
        let style = connector.effectiveStyle, color = style.color ?? .blue, width = style.width ?? 2
        context.saveGState(); defer { context.restoreGState() }
        let stroke = UIColor(red: color.red, green: color.green, blue: color.blue, alpha: style.strokeOpacity ?? 1)
        context.setStrokeColor(stroke.cgColor); context.setFillColor(stroke.cgColor)
        context.setLineWidth(width); context.setLineCap(.round); context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: (style.dash ?? .solid).lengths(width: width).map { CGFloat($0) })
        context.addPath(ShapePathRendering.path(ConnectorGeometry.path(connector, objects: objects))); context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        for head in ConnectorGeometry.arrowPaths(connector, objects: objects) {
            context.addPath(ShapePathRendering.path(head))
            if style.arrowStyle == .filled { context.drawPath(using: .fillStroke) } else { context.strokePath() }
        }
        if let label = DiagramLabels.connector(connector, objects: objects, page: page) {
            let background: UIColor = page?.appearance?.tone == .slate && page?.pdfFile == nil ? .darkGray : .white
            context.setFillColor(background.withAlphaComponent(0.95).cgColor)
            context.addPath(UIBezierPath(roundedRect: label.box.insetBy(dx: -4, dy: -2), cornerRadius: 5).cgPath); context.fillPath()
            DiagramLabels.draw(label, context: context)
        }
    }
}
