import Foundation

/// Page-coordinate geometry only. Advancing is navigation after a completed
/// stroke; it never transforms or truncates that stroke's stored points.
public struct ZoomWritingGeometry: Equatable, Sendable {
    public let pageWidth: Double, pageHeight: Double
    private var panelWidth: Double
    public private(set) var leftMargin: Double, rightMargin: Double
    public private(set) var x: Double, y: Double, width: Double, height: Double, zoom: Double
    public private(set) var atEnd = false
    public init?(pageWidth: Double, pageHeight: Double, panelWidth: Double, panelHeight: Double, zoom: Double = 3,
                 leftMargin: Double = 24, rightMargin: Double = 24) {
        guard [pageWidth, pageHeight, panelWidth, panelHeight, zoom, leftMargin, rightMargin].allSatisfy(\.isFinite),
              (40...20_000).contains(pageWidth), (40...20_000).contains(pageHeight), panelWidth > 0, panelHeight > 0,
              (2...4).contains(zoom), leftMargin >= 0, rightMargin >= 0, leftMargin + rightMargin <= pageWidth - 20 else { return nil }
        self.panelWidth = panelWidth
        self.pageWidth = pageWidth; self.pageHeight = pageHeight; self.leftMargin = leftMargin; self.rightMargin = rightMargin; self.zoom = zoom
        width = min(pageWidth - leftMargin - rightMargin, panelWidth / zoom); height = min(pageHeight, panelHeight / zoom)
        x = leftMargin; y = 0
    }
    public mutating func move(to point: StrokeSample) {
        guard point.x.isFinite, point.y.isFinite else { return }
        x = min(pageWidth - rightMargin - width, max(leftMargin, point.x))
        y = min(pageHeight - height, max(0, point.y)); atEnd = false
    }
    public mutating func resize(panelWidth: Double, panelHeight: Double, zoom: Double) {
        guard panelWidth.isFinite, panelHeight.isFinite, panelWidth > 0, panelHeight > 0, zoom.isFinite, (2...4).contains(zoom) else { return }
        self.panelWidth = panelWidth
        self.zoom = zoom; width = min(pageWidth - leftMargin - rightMargin, panelWidth / zoom); height = min(pageHeight, panelHeight / zoom)
        move(to: .init(x: x, y: y))
    }
    public mutating func margins(left: Double, right: Double) {
        guard left.isFinite, right.isFinite, left >= 0, right >= 0, left + right <= pageWidth - 20 else { return }
        leftMargin = left; rightMargin = right; width = min(pageWidth - left - right, panelWidth / zoom)
        move(to: .init(x: x, y: y))
    }
    public func pagePoint(fromPanel point: StrokeSample) -> StrokeSample? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return .init(x: x + point.x / zoom, y: y + point.y / zoom)
    }
    public func panelPoint(fromPage point: StrokeSample) -> StrokeSample? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return .init(x: (point.x - x) * zoom, y: (point.y - y) * zoom)
    }
    public mutating func step(_ direction: Int) { move(to: .init(x: x + Double(direction.signum()) * width * 0.85, y: y)) }
    public mutating func newLine(spacing: Double?) {
        let distance = spacing.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? height
        let next = min(pageHeight - height, y + distance)
        atEnd = next <= y + 0.001
        x = leftMargin; y = next
    }
    public mutating func advance(after point: StrokeSample, lineSpacing: Double?) {
        guard point.x.isFinite, point.y.isFinite, point.x >= x + width * 0.85 else { return }
        if x + width >= pageWidth - rightMargin - 0.001 { newLine(spacing: lineSpacing) }
        else { step(1) }
    }
}
