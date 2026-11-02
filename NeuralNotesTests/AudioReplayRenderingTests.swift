import XCTest
import UIKit
import PencilKit
import NeuralNotesCore
@testable import NeuralNotes

final class AudioReplayRenderingTests: XCTestCase {
    @MainActor func testShowAllActuallyShowsFutureInkHighlightsTheCurrentStrokeAndNeverChangesStoredInk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do {
            model.page?.paper = .plain
            let points = [CGPoint(x: 100, y: 160), CGPoint(x: 300, y: 180)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index), size: .init(width: 6, height: 6), opacity: 1, force: 0.8, azimuth: 0.2, altitude: 1.3)
            }
            let stroke = PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
            model.installNativeInk(PKDrawing(strokes: [stroke]))
            let bytes = model.canvas.drawing.dataRepresentation(), session = UUID(), signature = try XCTUnwrap(EditorInkSignatures.make(model.canvas.drawing).first)
            model.page?.anchors = [StrokeAnchor(signature: signature, audioSessionID: session, seconds: 10)]
            let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800); host.synchronizePage(); host.layoutIfNeeded()
            let audio = try XCTUnwrap(model.audio)
            audio.replayInk = true; audio.playingSessionID = session; audio.playback = 0; audio.replayMode = .follow
            host.inkReplay.update(host)
            let before = try colors(XCTUnwrap(host.inkReplay.image)); XCTAssertEqual(before.black, 0)
            audio.replayMode = .showAll; host.inkReplay.update(host)
            let all = try colors(XCTUnwrap(host.inkReplay.image)); XCTAssertGreaterThan(all.black, 100)
            audio.playback = 10.2; host.inkReplay.update(host)
            let hot = try colors(XCTUnwrap(host.inkReplay.image)); XCTAssertGreaterThan(hot.teal, all.teal + 100)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            audio.replayMode = .keyPoints; audio.playback = 0; host.inkReplay.update(host)
            XCTAssertEqual(try colors(XCTUnwrap(host.inkReplay.image)).black, 0)
            audio.stopPlayback(); host.inkReplay.update(host)
            XCTAssertTrue(host.inkReplay.isHidden); XCTAssertEqual(model.canvas.layer.opacity, 1)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), bytes)
            _ = await model.close()
        } catch { _ = await model.close(); throw error }
    }
    @MainActor private func colors(_ image: UIImage) throws -> (black: Int, teal: Int) {
        let image = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = buffer.bindMemory(to: UInt8.self); var black = 0, teal = 0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                if pixels[i] < 50 && pixels[i + 1] < 50 && pixels[i + 2] < 50 { black += 1 }
                if pixels[i] < 70 && pixels[i + 1] > 70 && pixels[i + 2] > 60 { teal += 1 }
            }
            return (black, teal)
        }
    }
}
