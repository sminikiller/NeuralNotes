import XCTest
@testable import NeuralNotesCore

final class HeldLineToleranceTests: XCTestCase {
    private func path(_ vertices: [StrokeSample], samples: Int = 20) -> [StrokeSample] {
        var result: [StrokeSample] = []
        for (a, b) in zip(vertices, vertices.dropFirst()) {
            for step in 0..<samples {
                let t = Double(step) / Double(samples)
                result.append(StrokeSample(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        if let last = vertices.last { result.append(last) }; return result
    }
    func testSmallInitialHookRecognizesInEveryDirectionAndProjectsTheStart() throws {
        let points = path([.init(x: 0, y: 8), .init(x: 4, y: 0), .init(x: 120, y: 0)])
        for angle in [0.0, 0.4, .pi / 2, .pi, -.pi / 3] {
            let rotated = points.map { p in StrokeSample(x: 300 + p.x * cos(angle) - p.y * sin(angle), y: 300 + p.x * sin(angle) + p.y * cos(angle)) }
            XCTAssertEqual(HeldShapeRecognition.recognize(rotated), .line)
            let ends = try XCTUnwrap(HeldShapeRecognition.lineEndpoints(rotated))
            XCTAssertEqual(ends.0.x, 300, accuracy: 0.001); XCTAssertEqual(ends.0.y, 300, accuracy: 0.001)
            XCTAssertEqual(ends.1.x, rotated.last!.x, accuracy: 0.001)
            XCTAssertEqual(ends.1.y, rotated.last!.y, accuracy: 0.001)
        }
    }
    func testAllowanceDoesNotDependOnCoalescedOrStationarySampleCount() throws {
        let vertices: [StrokeSample] = [.init(x: 0, y: 8), .init(x: 4, y: 0), .init(x: 120, y: 0)]
        for count in [3, 20, 500] {
            var points = path(vertices, samples: count)
            points.insert(contentsOf: Array(repeating: points[0], count: 100), at: 0)
            XCTAssertEqual(HeldShapeRecognition.recognize(points), .line)
            XCTAssertEqual(try XCTUnwrap(HeldShapeRecognition.lineEndpoints(points)).0.y, 0, accuracy: 0.001)
        }
    }
    func testLargerHooksMiddleAndFinalBendsRemainFreehand() {
        let paths: [[StrokeSample]] = [
            [.init(x: 0, y: 25), .init(x: 4, y: 0), .init(x: 120, y: 0)],
            [.init(x: 0, y: 0), .init(x: 60, y: 15), .init(x: 120, y: 0)],
            [.init(x: 0, y: 0), .init(x: 110, y: 0), .init(x: 120, y: 15)],
            [.init(x: 0, y: 0), .init(x: 60, y: 0), .init(x: 60, y: 60)]
        ]
        for vertices in paths { XCTAssertNil(HeldShapeRecognition.lineEndpoints(path(vertices))) }
        let scratch = (0...30).map { StrokeSample(x: $0 % 2 == 0 ? 0 : 100, y: Double($0)) }
        XCTAssertNil(HeldShapeRecognition.lineEndpoints(scratch))
    }
    func testShortOrNonFiniteStrokeNeverProducesCorrectedEndpoints() {
        XCTAssertNil(HeldShapeRecognition.lineEndpoints(path([.init(x: 0, y: 3), .init(x: 4, y: 0), .init(x: 16, y: 0)])))
        XCTAssertNil(HeldShapeRecognition.lineEndpoints(Array(repeating: .init(x: .nan, y: 0), count: 5)))
    }
}
