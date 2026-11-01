import XCTest
@testable import NeuralNotesCore

final class ShapeRecognizerTests: XCTestCase {
    private func samples(_ shape: ShapeElement, noise: Double = 0) -> [StrokeSample] {
        let paths = [ShapeGeometry.path(for: shape)] + ShapeGeometry.arrowPaths(for: shape)
        var result: [StrokeSample] = []
        for path in paths {
            for line in ShapeGeometry.polylines(path, steps: 32) {
                guard let first = line.first else { continue }; result.append(first)
                for i in 1..<line.count {
                    let a = line[i - 1], b = line[i], count = max(2, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 4)))
                    for j in 1...count {
                        let t = Double(j) / Double(count), jitter = sin(Double(result.count) * 2.3) * noise
                        result.append(.init(x: a.x + (b.x - a.x) * t + jitter, y: a.y + (b.y - a.y) * t - jitter))
                    }
                }
            }
        }
        return result
    }
    func testRecognizesEveryRequestedOutlineInBothModes() throws {
        for kind in [ShapeKind.line, .arrow, .ellipse, .rectangle, .triangle, .diamond, .polygon, .star, .arc] {
            var shape = ShapeElement(kind: kind, x: 100, y: 100, width: 220, height: 160)
            if kind == .ellipse { shape.height = 220 }
            if kind == .star || kind == .polygon { shape.height = 220; shape.sides = 5 }
            if kind == .arc { shape.height = 220; shape.arcStart = 0.3; shape.arcSweep = .pi * 1.25 }
            for mode in [ShapeRecognitionMode.hold, .automatic] {
                guard let value = ShapeRecognizer.recognize(samples(shape, noise: 0.4), mode: mode) else {
                    XCTFail("\(kind) in \(mode)"); continue
                }
                XCTAssertEqual(value.shape.kind, kind, "\(kind) in \(mode)")
                XCTAssertGreaterThanOrEqual(value.confidence, mode == .automatic ? 0.85 : 0.6)
            }
        }
    }
    func testNoisyRotatedRectangleAndRegularHexagon() throws {
        var rectangle = ShapeElement(kind: .rectangle, width: 240, height: 100); rectangle.rotation = 28
        let value = try XCTUnwrap(ShapeRecognizer.recognize(samples(rectangle, noise: 1.5)))
        XCTAssertEqual(value.shape.kind, .rectangle)
        var hexagon = ShapeElement(kind: .polygon, width: 200, height: 200); hexagon.sides = 6; hexagon.rotation = 17
        let result = try XCTUnwrap(ShapeRecognizer.recognize(samples(hexagon, noise: 0.7), mode: .automatic))
        XCTAssertEqual(result.shape.kind, .polygon); XCTAssertEqual(result.shape.sides, 6)
    }
    func testAllPolygonAndStarPointCounts() {
        for kind in [ShapeKind.polygon, .star] {
            for count in (kind == .star ? 4 : 5)...12 {
                var shape = ShapeElement(kind: kind, x: 100, y: 100, width: 300, height: 300)
                shape.sides = count; shape.innerRatio = kind == .star ? 0.5 : nil
                let result = ShapeRecognizer.recognize(samples(shape, noise: 0.3), mode: .automatic)
                XCTAssertEqual(result?.shape.kind, kind, "\(kind), \(count)")
                XCTAssertEqual(result?.shape.sides, count, "\(kind), \(count)")
            }
        }
    }
    func testSmoothRoundAndElongatedEllipsesDoNotBecomePolygons() {
        for width in [160.0, 300, 480] {
            var shape = ShapeElement(kind: .ellipse, width: width, height: 160); shape.rotation = 27
            let result = ShapeRecognizer.recognize(samples(shape, noise: 0.3), mode: .automatic)
            XCTAssertEqual(result?.shape.kind, .ellipse, "Ellisse \(width) × 160")
            XCTAssertNil(ShapeRecognizer.recognize(samples(shape), enabled: [.polygon, .star]))
        }
    }
    func testAutomaticRecognitionRejectsWritingContextAndFastSmallStrokes() {
        let shapes = [ShapeElement(kind: .ellipse), ShapeElement(kind: .triangle), ShapeElement(kind: .line)]
        for shape in shapes {
            XCTAssertNil(ShapeRecognizer.recognize(samples(shape), mode: .automatic, context: .init(nearWriting: true)))
            XCTAssertNil(ShapeRecognizer.recognize(samples(shape), mode: .automatic, context: .init(duration: 0.08)))
        }
        let scribble = (0..<100).map { StrokeSample(x: Double($0) * 2, y: Double($0 % 7) * 12) }
        XCTAssertNil(ShapeRecognizer.recognize(scribble, mode: .automatic))
        XCTAssertNil(ShapeRecognizer.recognize([.init(x: .nan, y: 0)]))
        XCTAssertNil(ShapeRecognizer.recognize(samples(shapes[0]), mode: .off))
        XCTAssertNil(ShapeRecognizer.recognize(samples(shapes[0]), enabled: [.line]))
    }
    func testBoundedRecognitionCostWithTwoThousandSamples() {
        let shape = ShapeElement(kind: .ellipse, width: 400, height: 400)
        let input = (0..<2000).map { i -> StrokeSample in
            let a = Double(i) / 1999 * 2 * .pi
            return .init(x: shape.x + 200 + cos(a) * 200, y: shape.y + 200 + sin(a) * 200)
        }
        let start = Date()
        for _ in 0..<20 { XCTAssertNotNil(ShapeRecognizer.recognize(input)) }
        // Generous CI regression budget; the iPad 10 frame budget needs physical measurement.
        XCTAssertLessThan(Date().timeIntervalSince(start) / 20, 0.016)
    }
    func testRoundedImperfectClosedShapesDoNotBecomeFreePolygons() throws {
        let outlines: [(ShapeKind, [StrokeSample])] = [
            (.rectangle, [.init(x: 110, y: 110), .init(x: 280, y: 119), .init(x: 289, y: 125), .init(x: 286, y: 267), .init(x: 279, y: 276), .init(x: 111, y: 269), .init(x: 103, y: 260), .init(x: 104, y: 119), .init(x: 110, y: 110)]),
            (.rectangle, [.init(x: 110, y: 110), .init(x: 278, y: 120), .init(x: 286, y: 127), .init(x: 295, y: 360), .init(x: 288, y: 369), .init(x: 113, y: 363), .init(x: 104, y: 355), .init(x: 102, y: 121), .init(x: 110, y: 110)]),
            (.triangle, [.init(x: 120, y: 320), .init(x: 213, y: 108), .init(x: 222, y: 103), .init(x: 230, y: 113), .init(x: 328, y: 319), .init(x: 324, y: 327), .init(x: 130, y: 326), .init(x: 120, y: 320)])
        ]
        for (kind, outline) in outlines {
            var trace: [StrokeSample] = []
            for i in 1..<outline.count {
                let a = outline[i - 1], b = outline[i]
                for step in 0..<20 {
                    let t = Double(step) / 20, jitter = sin(Double(step) * 1.7) * 1.3
                    trace.append(.init(x: a.x + (b.x - a.x) * t + jitter, y: a.y + (b.y - a.y) * t - jitter))
                }
            }
            trace.append(outline[0])
            // Starting on a side must not create an extra vertex at the seam.
            let cut = 9; trace = Array(trace[cut...]) + Array(trace.prefix(cut + 1))
            for mode in [ShapeRecognitionMode.hold, .automatic] {
                let result = try XCTUnwrap(ShapeRecognizer.recognize(trace, mode: mode))
                XCTAssertEqual(result.shape.kind, kind, "\(kind) / \(mode)")
                if kind == .rectangle { XCTAssertNil(result.shape.vertices) }
            }
        }
    }

}
