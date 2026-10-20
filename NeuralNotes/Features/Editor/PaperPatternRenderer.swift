import UIKit
import NeuralNotesCore

@MainActor
enum PaperPatternRenderer {
    static func draw(_ style: PaperStyle, step: CGFloat, in rect: CGRect, context: CGContext) {
        func line(_ a: CGPoint, _ b: CGPoint) { context.move(to: a); context.addLine(to: b) }
        switch style {
        case .plain: break
        case .ruled, .grid, .dotted:
            for y in stride(from: CGFloat(48), through: rect.height, by: step) {
                if style == .dotted {
                    for x in stride(from: CGFloat(24), through: rect.width, by: step) { context.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5)) }
                } else { line(CGPoint(x: 0, y: y), CGPoint(x: rect.width, y: y)) }
            }
            if style == .grid { for x in stride(from: CGFloat(24), through: rect.width, by: step) { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: rect.height)) } }
        case .cornell:
            let bottom = rect.height * 0.8, left = rect.width * 0.28
            line(CGPoint(x: left, y: 48), CGPoint(x: left, y: bottom))
            line(CGPoint(x: 24, y: bottom), CGPoint(x: rect.width - 24, y: bottom))
            for y in stride(from: CGFloat(48), to: bottom, by: step) { line(CGPoint(x: left, y: y), CGPoint(x: rect.width - 24, y: y)) }
        case .weekly:
            let box = rect.insetBy(dx: 24, dy: 48), column = box.width / 7
            context.addRect(box)
            for i in 1..<7 { line(CGPoint(x: box.minX + CGFloat(i) * column, y: box.minY), CGPoint(x: box.minX + CGFloat(i) * column, y: box.maxY)) }
            for (i, day) in ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"].enumerated() {
                (day as NSString).draw(at: CGPoint(x: box.minX + CGFloat(i) * column + 5, y: 26), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray])
            }
        case .music:
            for y in stride(from: CGFloat(72), to: rect.height - 48, by: step * 4) {
                for i in 0..<5 { let at = y + CGFloat(i) * step / 3; line(CGPoint(x: 36, y: at), CGPoint(x: rect.width - 36, y: at)) }
            }
        case .isometric:
            let rise = rect.width * 0.57735
            for y in stride(from: -rise, through: rect.height + rise, by: step) {
                line(CGPoint(x: 0, y: y), CGPoint(x: rect.width, y: y + rise))
                line(CGPoint(x: 0, y: y), CGPoint(x: rect.width, y: y - rise))
            }
            for x in stride(from: CGFloat(24), through: rect.width, by: step) { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: rect.height)) }
        case .millimeter:
            context.saveGState(); context.setAlpha(0.3)
            for x in stride(from: CGFloat(0), through: rect.width, by: step / 4) { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: rect.height)) }
            for y in stride(from: CGFloat(0), through: rect.height, by: step / 4) { line(CGPoint(x: 0, y: y), CGPoint(x: rect.width, y: y)) }
            context.strokePath(); context.restoreGState()
            for x in stride(from: CGFloat(0), through: rect.width, by: step) { line(CGPoint(x: x, y: 0), CGPoint(x: x, y: rect.height)) }
            for y in stride(from: CGFloat(0), through: rect.height, by: step) { line(CGPoint(x: 0, y: y), CGPoint(x: rect.width, y: y)) }
        case .mindMap:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            context.addEllipse(in: CGRect(x: center.x - 70, y: center.y - 35, width: 140, height: 70))
            for x in [rect.width * 0.2, rect.width * 0.8] {
                for y in [rect.height * 0.25, rect.height * 0.75] {
                    line(center, CGPoint(x: x, y: y)); context.addEllipse(in: CGRect(x: x - 60, y: y - 30, width: 120, height: 60))
                }
            }
        }
        context.strokePath()
    }
}
