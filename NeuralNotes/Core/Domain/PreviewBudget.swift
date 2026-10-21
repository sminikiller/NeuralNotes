import Foundation

public enum PreviewBudget {
    public static let maximumBytes = 48 * 1024 * 1024
    public static let maximumEncodedDrawing = 8 * 1024 * 1024
    /// Conservative accounting, not a measurement of PencilKit's private heap.
    public static func drawingCost(encodedBytes: Int, controlPoints: Int) -> Int {
        guard encodedBytes >= 0, controlPoints >= 0 else { return Int.max }
        let (points, overflow) = controlPoints.multipliedReportingOverflow(by: 96)
        if overflow { return Int.max }; return max(encodedBytes, points)
    }
    public static func canRetainDrawing(encodedBytes: Int, controlPoints: Int, imageBytes: Int) -> Bool {
        let drawing = drawingCost(encodedBytes: encodedBytes, controlPoints: controlPoints)
        guard imageBytes >= 0, imageBytes <= maximumBytes, encodedBytes <= maximumEncodedDrawing else { return false }
        return drawing <= maximumBytes - imageBytes
    }
}
