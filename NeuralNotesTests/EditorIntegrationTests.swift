import XCTest
import SwiftUI
import UIKit
import CoreGraphics
import PencilKit
import PDFKit
import NeuralNotesCore
@testable import NeuralNotes

final class EditorIntegrationTests: XCTestCase {
    @MainActor
    func testInkStillSavesWhenWorkspaceSettingsCatalogIsUnreadable() async throws {
        try await withEditor { model in
            try await model.workspace.setEditorWorkspaces(model.workspaces)
            try await model.workspace.setCoverAppearance(image: nil, design: CoverDesign())
            var paused = AudioSession(title: "Registrazione in memoria"); paused.state = "paused"; paused.revision = 2
            var segment = AudioTimelineSegment(file: "audio/recover-active.caf", start: 0, hostStart: 10)
            segment.duration = 7; paused.segments = [segment]
            let media = try await model.workspace.url(segment.file); try Data([1, 2, 3]).write(to: media)
            model.audio?.active = paused; model.audio?.paused = true
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture(); model.workspaceSaveTask?.cancel()
            let file = try await model.workspace.url("catalog.json")
            try Data("broken catalog".utf8).write(to: file)
            let result = await model.flush(); XCTAssertFalse(result)
            let pages = try await model.workspace.pages(), page = try XCTUnwrap(pages.first)
            let savedBytes = try await model.workspace.drawing(page), data = try XCTUnwrap(savedBytes)
            XCTAssertEqual(try PKDrawing(data: data).strokes.count, 1)
            XCTAssertTrue(model.workspaceSettingsDirty); XCTAssertFalse(model.dirty)
            let recovered = await model.recoverCatalog(); XCTAssertTrue(recovered)
            XCTAssertTrue(model.hasLease); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let catalog = try await model.workspace.catalog()
            XCTAssertEqual(catalog.sessions.first?.id, paused.id); XCTAssertEqual(catalog.sessions.first?.duration, 7)
            XCTAssertEqual(model.audio?.active?.revision, 3)
            let retried = await model.flush(); XCTAssertTrue(retried); XCTAssertFalse(model.workspaceSettingsDirty)
        }
    }

    @MainActor
    func testFlushDrainsEditsArrivingWhileFirstSnapshotIsBeingWritten() async throws {
        try await withEditor { original in
            _ = await original.close()
            let started = expectation(description: "First page write suspended")
            var released = false, count = 0
            var release: CheckedContinuation<Void, Never>?
            let workspace = original.workspace
            let model = EditorViewModel(workspace: workspace, pageWriter: { page, bytes, recovered in
                count += 1
                if count == 1 {
                    started.fulfill()
                    if !released { await withCheckedContinuation { release = $0 } }
                }
                return try await workspace.save(page, drawing: bytes, recoveredFromPrevious: recovered)
            })
            await model.open(); model.addText()
            let saving = Task { @MainActor in await model.flush() }
            await fulfillment(of: [started], timeout: 5)
            model.addText(); released = true; release?.resume(); release = nil
            let result = await saving.value; XCTAssertTrue(result); XCTAssertFalse(model.dirty)
            let pages = try await workspace.pages()
            XCTAssertEqual(pages.first?.texts.count, 2); XCTAssertGreaterThanOrEqual(count, 2)
            _ = await model.close()
        }
    }

    @MainActor
    func testFailedPageWriteKeepsDirtyStateAndCanRetryWithoutLosingInk() async throws {
        try await withEditor { original in
            _ = await original.close()
            var attempts = 0
            let workspace = original.workspace
            let model = EditorViewModel(workspace: workspace, pageWriter: { page, bytes, recovered in
                attempts += 1
                if attempts == 1 { throw CocoaError(.fileWriteOutOfSpace) }
                return try await workspace.save(page, drawing: bytes, recoveredFromPrevious: recovered)
            })
            await model.open()
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            let failed = await model.flush(); XCTAssertFalse(failed); XCTAssertTrue(model.dirty)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let retry = await model.flush(); XCTAssertTrue(retry); XCTAssertFalse(model.dirty)
            let page = try XCTUnwrap(model.page), bytes = try await workspace.drawing(page)
            XCTAssertEqual(try PKDrawing(data: try XCTUnwrap(bytes)).strokes.count, 1)
            _ = await model.close()
        }
    }

    @MainActor
    func testAnActivePencilStrokePreventsNavigationCloseAndToolReplacement() async throws {
        try await withEditor { model in
            let first = try XCTUnwrap(model.page); await model.addPage()
            let current = try XCTUnwrap(model.page)
            model.strokeBegan()
            await model.select(first); XCTAssertEqual(model.page?.id, current.id)
            let closed = await model.close(); XCTAssertFalse(closed); XCTAssertTrue(model.hasLease)
            model.chooseTool(.marker); XCTAssertEqual(model.tool, .pen)
            model.addText(); model.addShape(.ellipse)
            XCTAssertEqual(model.tool, .pen); XCTAssertTrue(model.page?.texts.isEmpty ?? false)
            XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            await model.select(first); XCTAssertEqual(model.page?.id, first.id)
            await model.select(current); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }
    @MainActor
    func testWorkspacesPersistPerNotebookAndKeepToolPalettesAndPersonalPreferencesSeparate() async throws {
        let scratch = UserDefaults.standard.object(forKey: "editor.scratchErase") as? Bool
        let pull = UserDefaults.standard.object(forKey: "editor.pullNextPage") as? Bool
        try await withEditor { model in
            let writingID = model.workspaces.selectedID
            model.chooseTool(.pen); model.chooseInk(InkColor.blue.color); model.chooseWidth(2)
            model.chooseTool(.marker)
            XCTAssertEqual(InkColor(model.ink), .yellow)
            model.chooseInk(InkColor.orange.color); model.chooseWidth(6)
            model.chooseTool(.pen); XCTAssertEqual(InkColor(model.ink), .blue); XCTAssertEqual(model.thickness, 2)
            let mathID = model.workspaces.profiles[1].id; model.selectWorkspace(mathID)
            model.editWorkspace { $0.dock = .leading; $0.scratchErase = false; $0.showStatus = false }
            XCTAssertTrue(model.currentWorkspace.favorites.contains(.ruler))
            XCTAssertEqual(InkColor(model.ink), .black)
            let saved = await model.flush(); XCTAssertTrue(saved)
            let snapshot = model.workspaces
            _ = await model.close()
            let reopened = EditorViewModel(workspace: model.workspace); await reopened.open()
            XCTAssertEqual(reopened.workspaces, snapshot)
            reopened.selectWorkspace(writingID); reopened.chooseTool(.marker)
            XCTAssertEqual(InkColor(reopened.ink), .orange); XCTAssertEqual(reopened.thickness, 6)
            _ = await reopened.close()
        }
        XCTAssertEqual(UserDefaults.standard.object(forKey: "editor.scratchErase") as? Bool, scratch)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "editor.pullNextPage") as? Bool, pull)
    }

    @MainActor
    func testDraggedArrowDirectionSurvivesUndoRedoAndDiskReload() async throws {
        try await withEditor { model in
            model.chooseTool(.arrow)
            model.addDraggedShape(.arrow, from: StrokeSample(x: 330, y: 260), to: StrokeSample(x: 60, y: 80))
            let shape = try XCTUnwrap(model.page?.shapes?.first)
            XCTAssertEqual(shape.start, ShapeEndpoint(x: 1, y: 1)); XCTAssertEqual(shape.end, ShapeEndpoint(x: 0, y: 0))
            await model.performUndo(); XCTAssertTrue(model.page?.shapes?.isEmpty ?? true)
            await model.performRedo(); XCTAssertEqual(model.page?.shapes?.first, shape)
            _ = await model.flush()
            let page = try XCTUnwrap(model.page); try await model.load(page)
            XCTAssertEqual(model.page?.shapes?.first, shape); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertEqual(model.tool, .shape)
        }
    }

    @MainActor
    func testHeldShapeCorrectionKeepsPreviousInkMarkerStyleAndUndo() async throws {
        try await withEditor { model in
            let old = inkStroke([CGPoint(x: 10, y: 20), CGPoint(x: 80, y: 20)])
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [old]); model.strokeEnded(); model.finishInkGesture()
            _ = await model.flush()
            model.chooseTool(.marker)
            let samples = (0...20).map { StrokeSample(x: 100 + Double($0) * 6, y: 180 + sin(Double($0))) }
            let points = samples.enumerated().map { i, p in PKStrokePoint(location: CGPoint(x: p.x, y: p.y), timeOffset: Double(i) * 0.03, size: CGSize(width: 16, height: 16), opacity: 0.4, force: 1, azimuth: 0, altitude: .pi / 2) }
            let rough = PKStroke(ink: PKInk(.marker, color: .yellow), path: PKStrokePath(controlPoints: points, creationDate: Date()))
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [old, rough])
            model.pendingHeldShape = (try XCTUnwrap(model.page?.id), .line, samples)
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path.creationDate, old.path.creationDate)
            XCTAssertEqual(model.canvas.drawing.strokes[1].ink.inkType, .marker)
            XCTAssertEqual(model.canvas.drawing.strokes[1].path.creationDate, rough.path.creationDate)
            XCTAssertNil(model.pendingHeldShape)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
        }
    }

    @MainActor
    func testHeldLineAndEllipseRemainConfirmedThroughFinalPencilMotionAndReload() async throws {
        for kind in [ShapeKind.line, .ellipse] {
            try await withEditor { model in
                model.editWorkspace { $0.holdShapes = true }
                let host = CanvasHost(canvas: model.canvas); host.model = model
                host.surface.page = try XCTUnwrap(model.page)
                host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
                let assistant = CanvasDrawingAssistant(host: host, model: model); model.drawingAssistant = assistant
                var locations: [CGPoint] = []
                for i in 0...60 {
                    let t = Double(i) / 60
                    if kind == .line { locations.append(CGPoint(x: 80 + t * 240, y: 180 + sin(t * 15))) }
                    else {
                        let angle = t * 2 * Double.pi
                        locations.append(CGPoint(x: 200 + cos(angle) * 60, y: 200 + sin(angle) * 45))
                    }
                }
                model.strokeBegan(); assistant.begin(at: locations[0]); assistant.move(samples: Array(locations.dropFirst()))
                model.canvas.drawing = PKDrawing(strokes: [inkStroke(locations)])
                assistant.recognizeHold()
                XCTAssertEqual(model.pendingHeldShape?.kind, kind)
                let confirmed = try XCTUnwrap(model.pendingHeldShape?.samples.count)
                let end = try XCTUnwrap(locations.last)
                // Includes the final coalesced samples delivered by touchesEnded.
                assistant.move(samples: [CGPoint(x: end.x + 8, y: end.y + 5), CGPoint(x: end.x + 12, y: end.y + 6)])
                XCTAssertEqual(model.pendingHeldShape?.kind, kind)
                XCTAssertEqual(model.pendingHeldShape?.samples.count, confirmed)
                assistant.end(cancelled: false); model.strokeEnded(); model.finishInkGesture()
                XCTAssertNil(model.pendingHeldShape); XCTAssertEqual(model.canvas.layer.opacity, 1)
                let corrected = try XCTUnwrap(model.canvas.drawing.strokes.first)
                if kind == .line {
                    // Lines are sampled for PencilKit, just like the other
                    // corrected shapes. Verify the geometry, not two-point storage.
                    XCTAssertGreaterThan(corrected.path.count, 2)
                    let start = try XCTUnwrap(corrected.path.first?.location)
                    let end = try XCTUnwrap(corrected.path.last?.location)
                    let dx = end.x - start.x, dy = end.y - start.y
                    let length = hypot(dx, dy)
                    XCTAssertGreaterThan(length, 200)
                    XCTAssertEqual(start.x, locations[0].x, accuracy: 2)
                    XCTAssertEqual(end.x, locations.last!.x, accuracy: 2)
                    for point in corrected.path {
                        let offsetX = point.location.x - start.x
                        let offsetY = point.location.y - start.y
                        let distance = abs(dx * offsetY - dy * offsetX) / length
                        XCTAssertLessThan(distance, 0.01)
                    }
                } else { XCTAssertEqual(corrected.path.count, 121) }
                await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
                await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
                let saved = await model.flush(); XCTAssertTrue(saved)
                try await model.load(try XCTUnwrap(model.page))
                XCTAssertEqual(model.canvas.drawing.strokes.first?.path.count, corrected.path.count)
                assistant.cancel()
            }
        }
    }

    @MainActor
    func testCancelledHoldRestoresCanvasVisibilityAndKeepsFreehandInk() async throws {
        try await withEditor { model in
            model.editWorkspace { $0.holdShapes = true }
            let host = CanvasHost(canvas: model.canvas); host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model); model.drawingAssistant = assistant
            let locations = (0...30).map { CGPoint(x: 80 + Double($0) * 6, y: 180 + sin(Double($0))) }
            model.strokeBegan(); assistant.begin(at: locations[0]); assistant.move(samples: Array(locations.dropFirst()))
            model.canvas.drawing = PKDrawing(strokes: [inkStroke(locations)])
            assistant.recognizeHold(); XCTAssertNotNil(model.pendingHeldShape)
            assistant.end(cancelled: true)
            XCTAssertNil(model.pendingHeldShape); XCTAssertEqual(model.canvas.layer.opacity, 1)
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertGreaterThan(try XCTUnwrap(model.canvas.drawing.strokes.first?.path.count), 2)
        }
    }

    @MainActor
    func testReopenPrefersLastEditedPageOverLastViewedAndCoverUsesItsFormat() async throws {
        try await withEditor { model in
            let editedID = try XCTUnwrap(model.page?.id)
            _ = await model.applyTemplate(PageTemplate(format: .square), useForNext: false)
            model.addText()
            let saved = await model.flush(); XCTAssertTrue(saved)
            let edited = try XCTUnwrap(model.page)
            let timestamp = try XCTUnwrap(edited.lastEditedAt)
            let other = try await model.workspace.addPage()
            await model.select(other)
            // Viewing and changing the order must not replace the content edit date.
            await model.reorder([other.id, editedID])
            _ = await model.close()
            let reopened = EditorViewModel(workspace: model.workspace); await reopened.open()
            XCTAssertEqual(reopened.page?.id, editedID)
            XCTAssertEqual(reopened.page?.lastEditedAt, timestamp)
            let cover = try await LastEditedCover.image(workspace: model.workspace)
            let image = try XCTUnwrap(cover)
            XCTAssertEqual(image.size.width, image.size.height, accuracy: 0.01)
            _ = await reopened.close()
        }
    }

    @MainActor
    func testLegacyNotebookWithoutEditDatesStillRestoresTheLastViewedPage() async throws {
        try await withEditor { model in
            await model.addPage()
            let viewed = try XCTUnwrap(model.page?.id)
            XCTAssertNil(model.page?.lastEditedAt)
            _ = await model.close()
            let reopened = EditorViewModel(workspace: model.workspace); await reopened.open()
            XCTAssertEqual(reopened.page?.id, viewed)
            _ = await reopened.close()
        }
    }

    @MainActor
    func testRulerUsesConstrainedVectorsAndShapeModeNeverEnablesPencilPanning() async throws {
        try await withEditor { model in
            model.chooseTool(.ellipse); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            model.chooseTool(.ruler)
            XCTAssertEqual(model.tool, .pen); XCTAssertTrue(model.rulerActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertFalse(model.canvas.panGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.pencil.rawValue)))
            model.chooseTool(.ruler); XCTAssertFalse(model.canvas.isRulerActive)
            model.chooseTool(.arrow); XCTAssertEqual(model.canvas.panGestureRecognizer.minimumNumberOfTouches, 2)
        }
    }

    @MainActor
    func testContinuousScrollRebasePreservesScreenPositionAndPageLocalInk() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let first = try XCTUnwrap(model.page)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            await model.addPage()
            let changedFormat = await model.applyTemplate(PageTemplate(format: .square), useForNext: false)
            XCTAssertTrue(changedFormat)
            let second = try XCTUnwrap(model.page)
            await model.addPage(); await model.select(first)
            model.pageNavigation = .vertical
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.surface.package = model.workspace.package; host.surface.page = try XCTUnwrap(model.page)
            let flow = ContinuousCanvasFlow(host: host, model: model); host.flow = flow
            host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
            let frame = try XCTUnwrap(flow.layout.frame(second.id)), z = host.canvas.zoomScale
            host.canvas.setContentOffset(CGPoint(x: -host.canvas.contentInset.left, y: CGFloat(frame.y) * z - 80), animated: false)
            host.alignSurface(); await flow.prepareVisiblePages()
            let documentY = host.canvas.contentOffset.y / z
            XCTAssertTrue(flow.prepareInput(at: CGPoint(x: host.bounds.midX, y: 160)))
            XCTAssertEqual(model.page?.id, second.id)
            XCTAssertEqual(host.surface.frame.minY, 80, accuracy: 1)
            let rebasedY = host.canvas.contentOffset.y / z + CGFloat(frame.y)
            // UIScrollView rounds offsets to display pixels when rebasing.
            let pixel = 1 / max(1, host.traitCollection.displayScale)
            XCTAssertEqual((rebasedY - documentY) * z, 0, accuracy: pixel)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.select(first)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let stroke = try XCTUnwrap(model.canvas.drawing.strokes.first)
            let points = stroke.path.interpolatedPoints(by: .distance(4)).map(\.location)
            XCTAssertEqual(try XCTUnwrap(points.first?.y), 80, accuracy: 0.1)
        }
    }

    @MainActor
    func testPreparedPageActivationRefusesUnsavedEditsOrAStaleHeader() async throws {
        try await withEditor { model in
            let first = try XCTUnwrap(model.page); await model.addPage(); let second = try XCTUnwrap(model.page)
            await model.select(first); model.addText()
            XCTAssertFalse(model.activatePreparedPage(second, drawing: PKDrawing()))
            XCTAssertEqual(model.page?.id, first.id); XCTAssertEqual(model.page?.texts.count, 1)
            _ = await model.flush()
            var stale = second; stale.revision += 1
            XCTAssertFalse(model.activatePreparedPage(stale, drawing: PKDrawing()))
            XCTAssertTrue(model.activatePreparedPage(second, drawing: PKDrawing()))
            await model.select(first); XCTAssertEqual(model.page?.texts.count, 1)
        }
    }

    @MainActor
    func testHorizontalCurlCompletesBothWaysAndKeepsNativeInk() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let first = try XCTUnwrap(model.page)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            await model.addPage(); let second = try XCTUnwrap(model.page); await model.select(first)
            model.pageNavigation = .horizontal
            let host = CanvasHost(canvas: model.canvas); host.model = model; model.pagePresenter = host
            host.surface.package = model.workspace.package; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1024, height: 768); host.setNeedsLayout(); host.layoutIfNeeded()
            let controller = UIViewController(); controller.view.addSubview(host)
            let window = UIWindow(frame: host.bounds); window.rootViewController = controller; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            await model.select(second)
            XCTAssertEqual(model.page?.id, second.id); XCTAssertFalse(model.navigating)
            XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "bookPageTurn" })
            await model.select(first)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertFalse(host.subviews.contains { $0.accessibilityIdentifier == "bookPageTurn" })
        }
    }

    @MainActor
    func testEveryNavigationModeUsesTheSameFullSizeCanvasWithoutAnOuterScrollView() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let controller = UIHostingController(rootView: DocumentPageViewport(model: model))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = controller; window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            var originalHost: CanvasHost?
            for mode in PageNavigationMode.allCases {
                model.pageNavigation = mode
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                await Task.yield(); controller.view.layoutIfNeeded()
                let host = try XCTUnwrap(model.canvas.superview as? CanvasHost)
                if let originalHost { XCTAssertTrue(originalHost === host) } else { originalHost = host }
                let expected = controller.view.bounds.inset(by: controller.view.safeAreaInsets).size
                XCTAssertGreaterThan(expected.height, 0)
                XCTAssertEqual(host.bounds.width, expected.width, accuracy: 1)
                XCTAssertEqual(host.bounds.height, expected.height, accuracy: 1)
                XCTAssertEqual(model.canvas.frame, host.bounds)
                var ancestor = host.superview
                while let view = ancestor { XCTAssertFalse(view is UIScrollView); ancestor = view.superview }
                XCTAssertTrue(model.canvas.panGestureRecognizer.isEnabled)
            }
        }
    }

    @MainActor
    func testPageNavigationAndCanvasPanExcludePencilForBothDrawingPolicies() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let host = CanvasHost(canvas: model.canvas), interaction = CanvasInteraction(host: host, model: model)
            host.interaction = interaction; host.model = model
            host.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            host.setNeedsLayout(); host.layoutIfNeeded()
            let pinch = try XCTUnwrap(model.canvas.pinchGestureRecognizer)
            let pencil = NSNumber(value: UITouch.TouchType.pencil.rawValue)
            let finger = NSNumber(value: UITouch.TouchType.direct.rawValue)
            let swipes = (model.canvas.gestureRecognizers ?? []).compactMap { $0 as? UISwipeGestureRecognizer }.filter { $0.delegate === interaction }
            XCTAssertEqual(swipes.count, 4)
            for fingerDrawing in [false, true] {
                model.fingerDrawing = fingerDrawing; model.configureTool()
                XCTAssertTrue(model.canvas.drawingGestureRecognizer.isEnabled)
                XCTAssertEqual(model.canvas.drawingPolicy, fingerDrawing ? .anyInput : .pencilOnly)
                XCTAssertTrue(model.canvas.panGestureRecognizer.allowedTouchTypes.contains(finger))
                XCTAssertFalse(model.canvas.panGestureRecognizer.allowedTouchTypes.contains(pencil))
                XCTAssertEqual(model.canvas.panGestureRecognizer.minimumNumberOfTouches, fingerDrawing ? 2 : 1)
                XCTAssertFalse(pinch.allowedTouchTypes.contains(pencil))
                for mode in PageNavigationMode.allCases {
                    model.pageNavigation = mode; interaction.refresh()
                    let enabled = swipes.filter(\.isEnabled)
                    XCTAssertEqual(enabled.count, mode == .horizontal ? 2 : 0)
                    for swipe in enabled {
                        XCTAssertEqual(swipe.allowedTouchTypes, [finger])
                        XCTAssertEqual(swipe.numberOfTouchesRequired, fingerDrawing ? 2 : 1)
                        let expected: [UISwipeGestureRecognizer.Direction] = mode == .vertical ? [.up, .down] : [.left, .right]
                        XCTAssertTrue(expected.contains(swipe.direction))
                    }
                }
            }
        }
    }

    @MainActor
    func testPageNavigationCannotRunWhilePencilOrTextEditingIsActive() async throws {
        try await withEditor { model in
            await model.addPage(); let last = try XCTUnwrap(model.page)
            model.strokeBegan()
            await model.turnPage(-1); await model.advanceOrAddPage()
            XCTAssertEqual(model.page?.id, last.id); XCTAssertEqual(model.pages.count, 2)
            model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 200, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            model.tool = .text; model.beginTextEdit(at: CGPoint(x: 100, y: 120))
            await model.turnPage(-1); XCTAssertEqual(model.page?.id, last.id)
            model.endTextEdit(); await model.turnPage(-1)
            XCTAssertNotEqual(model.page?.id, last.id)
            await model.turnPage(1); XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }

    @MainActor
    func testLatePencilDrawingAfterToolEndStillAppliesBlackeningAndCanUndo() async throws {
        let key = "editor.scratchErase", previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        try await withEditor { model in
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            var points: [CGPoint] = []
            for i in 0...240 {
                let angle: Double = Double(i) * 8.0 * Double.pi / 240.0
                points.append(CGPoint(x: CGFloat(130 + 30 * cos(angle)), y: CGFloat(80 + 10 * sin(angle))))
            }
            let before = model.canvas.drawing
            model.strokeBegan(); model.strokeEnded(); model.finishInkGesture()
            XCTAssertNotNil(model.editBeforeGesture)
            // Match the real callback order: end-of-tool first, drawing later.
            model.canvas.drawing = PKDrawing(strokes: before.strokes + [inkStroke(points)])
            model.drawingChanged()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertNil(model.editBeforeGesture)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo(); XCTAssertNil(model.canvas.drawing.strokes.first?.mask)
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
        }
    }

    @MainActor
    func testPageTurningWorksInBothDirectionsWithoutCreatingPagesAndModePersists() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            let first = try XCTUnwrap(model.page)
            await model.addPage(); let second = try XCTUnwrap(model.page)
            model.pageNavigation = .horizontal
            await model.turnPage(-1); XCTAssertEqual(model.page?.id, first.id)
            await model.turnPage(-1); XCTAssertEqual(model.page?.id, first.id)
            await model.turnPage(1); XCTAssertEqual(model.page?.id, second.id)
            await model.turnPage(1); XCTAssertEqual(model.pages.count, 2)
            let recreated = EditorViewModel(workspace: model.workspace)
            XCTAssertEqual(recreated.pageNavigation, .horizontal)
        }
    }

    @MainActor
    func testLivePencilTextPersistsThroughPageChangeAndUndoDoesNotCreateAnotherEdit() async throws {
        try await withEditor { model in
            model.tool = .text; model.configureTool()
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            model.beginTextEdit(at: CGPoint(x: 100, y: 100))
            model.updateLiveText("prima seconda")
            await model.performUndo()
            XCTAssertEqual(model.page?.texts.first?.text, "")
            await model.performRedo()
            XCTAssertEqual(model.page?.texts.first?.text, "prima seconda")
            let first = try XCTUnwrap(model.page)
            await model.addPage(); await model.select(first)
            XCTAssertEqual(model.page?.texts.first?.text, "prima seconda")
            model.tool = .pen; model.configureTool()
            XCTAssertTrue(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertNil(model.editingTextID)
        }
    }

    @MainActor
    func testFitRecognizerAllowsPencilKitScrollingAndDoesNotUsePencilTouches() async throws {
        try await withEditor { model in
            let host = CanvasHost(canvas: model.canvas)
            let interaction = CanvasInteraction(host: host, model: model); host.interaction = interaction
            let taps = (host.canvas.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }.filter { $0.numberOfTapsRequired == 2 && $0.delegate === interaction }
            XCTAssertEqual(taps.count, 2)
            for tap in taps {
                XCTAssertFalse(tap.cancelsTouchesInView)
                XCTAssertFalse(tap.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.pencil.rawValue)))
                XCTAssertTrue(interaction.gestureRecognizer(tap, shouldRecognizeSimultaneouslyWith: host.canvas.panGestureRecognizer))
            }
        }
    }
    @MainActor
    private func inkStroke(_ locations: [CGPoint]) -> PKStroke {
        var points: [PKStrokePoint] = []
        let altitude: CGFloat = CGFloat.pi / 2.0
        for (index, location) in locations.enumerated() {
            points.append(PKStrokePoint(location: location, timeOffset: Double(index) * 0.05,
                size: CGSize(width: 5, height: 5), opacity: 1, force: 1, azimuth: 0, altitude: altitude))
        }
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    @MainActor
    func testScratchMaskKeepsConnectedInkOutsideBothErasedAreasAfterReopening() throws {
        let original = inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])
        let drawing = PKDrawing(strokes: [original])
        let first = InkScratchEraser.erase(drawing, in: CGRect(x: 100, y: 70, width: 40, height: 20))
        let second = InkScratchEraser.erase(first.drawing, in: CGRect(x: 200, y: 70, width: 40, height: 20))
        XCTAssertTrue(first.erased); XCTAssertTrue(second.erased)
        let reopened = try PKDrawing(data: second.drawing.dataRepresentation())
        let stroke = try XCTUnwrap(reopened.strokes.first), mask = try XCTUnwrap(stroke.mask)
        XCTAssertEqual(stroke.path.creationDate, original.path.creationDate)
        XCTAssertTrue(mask.contains(CGPoint(x: 40, y: 80)))
        XCTAssertFalse(mask.contains(CGPoint(x: 120, y: 80))); XCTAssertFalse(mask.contains(CGPoint(x: 220, y: 80)))
        XCTAssertTrue(mask.contains(CGPoint(x: 280, y: 80)))
        var circle: [CGPoint] = []
        for i in 0...60 {
            let angle: Double = Double(i) * 2.0 * Double.pi / 60.0
            circle.append(CGPoint(x: CGFloat(200.0 + cos(angle) * 50.0), y: CGFloat(200.0 + sin(angle) * 50.0)))
        }
        let untouched = InkScratchEraser.erase(PKDrawing(strokes: [inkStroke(circle)]), in: CGRect(x: 195, y: 195, width: 10, height: 10))
        XCTAssertFalse(untouched.erased)
    }

    @MainActor
    func testLoopedScratchRemovesCrossedStrokesAndLeavesInteriorAndNearbyInkAfterUndoAndReload() async throws {
        try await withEditor { model in
            model.editWorkspace { $0.scratchErase = true }
            let crossing = inkStroke([CGPoint(x: 20, y: 200), CGPoint(x: 320, y: 200)])
            let interior = inkStroke([CGPoint(x: 185, y: 210), CGPoint(x: 215, y: 210)])
            let nearby = inkStroke([CGPoint(x: 270, y: 200), CGPoint(x: 320, y: 200)])
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [crossing, interior, nearby])
            model.strokeEnded(); model.finishInkGesture()
            var loop: [CGPoint] = []
            for i in 0...240 {
                let angle = Double(i) * 6 * Double.pi / 240
                loop.append(CGPoint(x: 200 + cos(angle) * 60, y: 200 + sin(angle) * 40))
            }
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [crossing, interior, nearby, inkStroke(loop)])
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            XCTAssertEqual(model.canvas.drawing.strokes.map { $0.path.creationDate }, [interior, nearby].map { $0.path.creationDate })
            XCTAssertTrue(model.canvas.drawing.strokes.allSatisfy { $0.mask == nil })
            await model.performUndo()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 3)
            XCTAssertEqual(model.canvas.drawing.strokes.first?.renderBounds, crossing.renderBounds)
            await model.performRedo()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertEqual(model.canvas.drawing.strokes.map { $0.path.creationDate }, [interior, nearby].map { $0.path.creationDate })
            XCTAssertTrue(model.canvas.drawing.strokes.allSatisfy { $0.mask == nil })
        }
    }

    @MainActor
    func testScratchRemovesEveryCrossedStrokeAsOneUndoableEdit() async throws {
        try await withEditor { model in
            model.editWorkspace { $0.scratchErase = true }
            let crossed = [110, 130, 150].map { x in
                inkStroke([CGPoint(x: x, y: 60), CGPoint(x: x, y: 160)])
            }
            let nearby = inkStroke([CGPoint(x: 180, y: 60), CGPoint(x: 180, y: 160)])
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: crossed + [nearby])
            model.strokeEnded(); model.finishInkGesture()
            var points: [CGPoint] = []
            for index in 0..<12 {
                let x: CGFloat = index % 2 == 0 ? 100 : 160
                let y: CGFloat = 80 + CGFloat(index) * 3
                points.append(CGPoint(x: x, y: y))
            }
            model.strokeBegan()
            model.canvas.drawing = PKDrawing(strokes: crossed + [nearby, inkStroke(points)])
            model.strokeEnded(); model.finishInkGesture()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertEqual(model.canvas.drawing.strokes.first?.renderBounds, nearby.renderBounds)
            XCTAssertNil(model.canvas.drawing.strokes.first?.mask)
            await model.performUndo()
            XCTAssertEqual(model.canvas.drawing.strokes.map { $0.renderBounds }, (crossed + [nearby]).map { $0.renderBounds })
            await model.performRedo()
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            let saved = await model.flush(); XCTAssertTrue(saved)
            try await model.load(try XCTUnwrap(model.page))
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1)
            XCTAssertEqual(model.canvas.drawing.strokes.first?.renderBounds, nearby.renderBounds)
        }
    }

    @MainActor
    func testWholeStrokeErasureIgnoresAnAlreadyErasedGapAndRemovesAllRemainingPiecesOnContact() throws {
        let original = inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])
        let partial = InkScratchEraser.erase(PKDrawing(strokes: [original]), in: CGRect(x: 100, y: 65, width: 80, height: 30))
        let drawing = try PKDrawing(data: partial.drawing.dataRepresentation())
        XCTAssertNotNil(drawing.strokes.first?.mask)
        let gap = CGPath(rect: CGRect(x: 125, y: 70, width: 20, height: 20), transform: nil)
        let untouched = InkScratchEraser.erase(drawing, in: gap, wholeStroke: true)
        XCTAssertFalse(untouched.erased)
        XCTAssertEqual(untouched.drawing.strokes.count, 1)
        let contact = CGPath(rect: CGRect(x: 210, y: 70, width: 20, height: 20), transform: nil)
        let erased = InkScratchEraser.erase(drawing, in: contact, wholeStroke: true)
        XCTAssertTrue(erased.erased)
        XCTAssertTrue(try PKDrawing(data: erased.drawing.dataRepresentation()).strokes.isEmpty)
    }

    @MainActor
    func testWholeStrokeErasureFindsTransformedInkAndDotsWithoutErasingTheirBoundingBox() throws {
        let original = inkStroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        let transform = CGAffineTransform(a: 0, b: 2, c: -2, d: 0, tx: 200, ty: 100)
        let moved = PKStroke(ink: original.ink, path: original.path, transform: transform)
        let dot = inkStroke([CGPoint(x: 205, y: 200)])
        let nearby = inkStroke([CGPoint(x: 240, y: 200), CGPoint(x: 240, y: 250)])
        let area = CGPath(rect: CGRect(x: 190, y: 190, width: 25, height: 20), transform: nil)
        let erased = InkScratchEraser.erase(PKDrawing(strokes: [moved, dot, nearby]), in: area, wholeStroke: true)
        XCTAssertTrue(erased.erased)
        XCTAssertEqual(erased.drawing.strokes.count, 1)
        XCTAssertEqual(erased.drawing.strokes.first?.renderBounds, nearby.renderBounds)
        XCTAssertNil(erased.drawing.strokes.first?.mask)
    }

    @MainActor
    func testSparseScratchDoesNotDeleteAnEnclosedTypedWordOrAWordTouchedOnlyAtItsEdge() {
        var text = TextElement(text: "parola"); text.x = 170; text.y = 180; text.width = 200
        let loop = UIBezierPath(ovalIn: CGRect(x: 145, y: 160, width: 170, height: 100))
        let area = loop.cgPath.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round, miterLimit: 1)
        XCTAssertEqual(TextScratchEraser.eraseWords(text, in: area, pageHeight: 1024), text.text)
        XCTAssertEqual(TextScratchEraser.eraseWords(text, in: CGRect(x: 170, y: 180, width: 2, height: 30), pageHeight: 1024), text.text)
    }

    @MainActor
    func testScratchCutsTransformedInkInDocumentCoordinatesAndKeepsItsNativePath() throws {
        let original = inkStroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        let transform = CGAffineTransform(a: 0, b: 2, c: -2, d: 0, tx: 200, ty: 100)
        let moved = PKStroke(ink: original.ink, path: original.path, transform: transform)
        let scratch = inkStroke([CGPoint(x: 170, y: 200), CGPoint(x: 230, y: 200)])
        let result = InkScratchEraser.erase(PKDrawing(strokes: [moved]), in: InkScratchEraser.coverage(of: scratch))
        XCTAssertTrue(result.erased)
        let reopened = try PKDrawing(data: result.drawing.dataRepresentation())
        let stroke = try XCTUnwrap(reopened.strokes.first), mask = try XCTUnwrap(stroke.mask)
        XCTAssertEqual(stroke.transform, transform)
        XCTAssertEqual(stroke.path.creationDate, original.path.creationDate)
        XCTAssertTrue(mask.contains(CGPoint(x: 10, y: 0))); XCTAssertTrue(mask.contains(CGPoint(x: 90, y: 0)))
        XCTAssertFalse(mask.contains(CGPoint(x: 50, y: 0)))
    }

    @MainActor
    func testScratchDeletesOnlyTheCrossedTypedWord() {
        var text = TextElement(text: "prima seconda terza"); text.x = 0; text.y = 0
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: CGFloat(text.fontSize))]
        let start = ("prima " as NSString).size(withAttributes: attributes).width
        let width = ("seconda" as NSString).size(withAttributes: attributes).width
        let result = TextScratchEraser.eraseWords(text, in: CGRect(x: start + 1, y: 0, width: width - 2, height: 28), pageHeight: 1024)
        XCTAssertTrue(result.contains("prima")); XCTAssertTrue(result.contains("terza")); XCTAssertFalse(result.contains("seconda"))
        XCTAssertEqual(TextScratchEraser.eraseWords(text, in: CGRect(x: 0, y: 200, width: 400, height: 20), pageHeight: 1024), text.text)
    }

    @MainActor
    func testDoubleTapZoomFillsWidthAndReturnsToCenteredWholePage() {
        let canvas = PKCanvasView(), host = CanvasHost(canvas: canvas)
        canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])])
        let originalInk = canvas.drawing.dataRepresentation()
        for size in [CGSize(width: 1200, height: 900), CGSize(width: 800, height: 1100)] {
            host.frame = CGRect(origin: .zero, size: size); host.setNeedsLayout(); host.layoutIfNeeded()
            let initial = host.surface.frame
            XCTAssertGreaterThan(initial.minX, 0)
            for _ in 0..<3 {
                host.togglePageZoom(animated: false)
                XCTAssertEqual(host.surface.frame.minX, 0, accuracy: 0.5)
                XCTAssertEqual(host.surface.frame.maxX, host.bounds.width, accuracy: 0.5)
                XCTAssertEqual(canvas.contentInset.left, 0, accuracy: 0.001)
                XCTAssertEqual(canvas.contentInset.right, 0, accuracy: 0.001)
                host.togglePageZoom(animated: false)
                XCTAssertEqual(canvas.zoomScale, canvas.minimumZoomScale, accuracy: 0.0001)
                XCTAssertEqual(host.surface.frame.minX, initial.minX, accuracy: 0.5)
                XCTAssertEqual(host.surface.frame.minY, initial.minY, accuracy: 0.5)
                XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(host.surface.frame))
            }
        }
        host.togglePageZoom(animated: false); host.fitPage(animated: false)
        XCTAssertFalse(host.fitsPageWidth)
        XCTAssertEqual(canvas.drawing.dataRepresentation(), originalInk)
    }

    @MainActor
    func testZoomStateSettlesAfterTheFinalAnimationWithoutChangingInk() async throws {
        try await withEditor { model in
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1200, height: 900))
            let controller = UIViewController()
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true }
            let host = CanvasHost(canvas: model.canvas); host.model = model
            host.surface.page = try XCTUnwrap(model.page)
            host.frame = controller.view.bounds; controller.view.addSubview(host); host.layoutIfNeeded()
            model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])])
            let drawing = model.canvas.drawing.dataRepresentation()
            host.togglePageZoom(animated: true)
            let widthSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !host.viewportAnimationActive && !model.canvasViewportMoving && model.canvasZoomed
            }, object: nil)
            await fulfillment(of: [widthSettled], timeout: 5)
            XCTAssertEqual(host.surface.frame.minX, 0, accuracy: 0.5)
            XCTAssertEqual(host.surface.frame.maxX, host.bounds.width, accuracy: 0.5)
            // A newer explicit fit request must win over an earlier completion.
            host.togglePageZoom(animated: true)
            host.togglePageZoom(animated: true)
            host.fitPage(animated: true)
            let pageSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !host.viewportAnimationActive && !model.canvasViewportMoving && !model.canvasZoomed
            }, object: nil)
            await fulfillment(of: [pageSettled], timeout: 5)
            XCTAssertFalse(host.fitsPageWidth)
            XCTAssertEqual(model.canvas.zoomScale, model.canvas.minimumZoomScale, accuracy: 0.0001)
            XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(host.surface.frame))
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), drawing)
        }
    }

    @MainActor
    func testWidthZoomTargetsTheActivePageInEveryNavigationMode() async throws {
        try await withEditor { model in
            let key = "editor.navigation.\(model.workspace.documentID)"
            defer { UserDefaults.standard.removeObject(forKey: key) }
            _ = await model.applyTemplate(PageTemplate(format: .square), useForNext: false)
            await model.addPage()
            let active = try XCTUnwrap(model.page)
            for mode in PageNavigationMode.allCases {
                model.pageNavigation = mode
                let host = CanvasHost(canvas: model.canvas); host.model = model
                host.surface.package = model.workspace.package; host.surface.page = active
                host.flow = ContinuousCanvasFlow(host: host, model: model)
                host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
                host.togglePageZoom(animated: false)
                XCTAssertEqual(host.surface.frame.minX, 0, accuracy: 0.5)
                XCTAssertEqual(host.surface.frame.maxX, host.bounds.width, accuracy: 0.5)
                XCTAssertEqual(host.flow?.page(at: CGPoint(x: 600, y: 450)) ?? active.id, active.id)
                host.togglePageZoom(animated: false)
                XCTAssertGreaterThan(host.surface.frame.minX, 0)
                XCTAssertEqual(model.page?.id, active.id)
                XCTAssertEqual(host.canvas.zoomScale, host.canvas.minimumZoomScale, accuracy: 0.0001)
            }
        }
    }

    @MainActor
    func testFitPageRestoresWholePageWithoutChangingDrawing() {
        let canvas = PKCanvasView(), host = CanvasHost(canvas: canvas)
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 900); host.setNeedsLayout(); host.layoutIfNeeded()
        canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])])
        canvas.setZoomScale(canvas.minimumZoomScale * 2, animated: false)
        canvas.setContentOffset(CGPoint(x: 200, y: 200), animated: false)
        host.fitPage(animated: false)
        XCTAssertEqual(canvas.zoomScale, canvas.minimumZoomScale, accuracy: 0.0001)
        XCTAssertTrue(host.bounds.insetBy(dx: -1, dy: -1).contains(host.surface.frame))
        XCTAssertEqual(canvas.drawing.strokes.count, 1)
    }

    @MainActor
    func testScratchInkErasureUndoRedoRestoresTheOriginalStroke() async throws {
        let key = "editor.scratchErase", previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        try await withEditor { model in
            model.strokeBegan()
            model.canvas.drawing = PKDrawing(strokes: [inkStroke([CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)])])
            model.strokeEnded(); model.finishInkGesture()
            var scratch: [CGPoint] = []
            for i in 0..<12 { scratch.append(CGPoint(x: i % 2 == 0 ? 100 : 160, y: CGFloat(76 + i))) }
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: model.canvas.drawing.strokes + [inkStroke(scratch)]); model.strokeEnded(); model.finishInkGesture()
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 1); XCTAssertNil(model.canvas.drawing.strokes.first?.mask)
            await model.performRedo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }

    @MainActor
    func testPageTemplateResizesContentUndoRestoresAndNextPageUsesDefault() async throws {
        try await withEditor { model in
            model.addText()
            let originalWidth = try XCTUnwrap(model.page?.width)
            let originalTextX = try XCTUnwrap(model.page?.texts.first?.x)
            let originalAppearance = model.page?.appearance
            let template = PageTemplate(paper: .grid, appearance: PaperAppearance(tone: .cream, spacing: 28), format: .a4)
            let applied = await model.applyTemplate(template, useForNext: true)
            XCTAssertTrue(applied); XCTAssertEqual(model.page?.appearance?.tone, .cream)
            XCTAssertEqual(try XCTUnwrap(model.page?.texts.first?.x), originalTextX * template.format.size.width / originalWidth, accuracy: 0.01)
            await model.performUndo(); XCTAssertEqual(model.page?.width, originalWidth); XCTAssertEqual(model.page?.appearance, originalAppearance)
            await model.addPage(); XCTAssertEqual(model.page?.paper, .grid); XCTAssertEqual(model.page?.appearance?.tone, .cream)
        }
    }

    @MainActor
    func testAdvancingCreatesOnlyAtTheEndAndTheNewPageIsUndoable() async throws {
        try await withEditor { model in
            let first = try XCTUnwrap(model.page)
            await model.addPage(); await model.select(first)
            await model.advanceOrAddPage(); XCTAssertEqual(model.pages.count, 2)
            await model.advanceOrAddPage(); XCTAssertEqual(model.pages.count, 3)
            await model.performUndo(); XCTAssertEqual(model.pages.count, 2)
        }
    }

    func testSquareCropHasEqualPixelSidesForPortraitAndLandscapeImages() {
        let sizes = [CGSize(width: 1600, height: 900), CGSize(width: 900, height: 1600)]
        for size in sizes {
            let crop = PhotoCropGeometry.square(image: size)
            let pixelWidth: Double = Double(size.width) * crop.width
            let pixelHeight: Double = Double(size.height) * crop.height
            XCTAssertEqual(pixelWidth, pixelHeight, accuracy: 0.001)
            XCTAssertEqual(crop.x * 2.0 + crop.width, 1.0, accuracy: 0.001)
            XCTAssertEqual(crop.y * 2.0 + crop.height, 1.0, accuracy: 0.001)
        }
    }

    func testCropSelectionMapsTheFittedPreviewBackToTheImage() {
        let image = CGSize(width: 1600, height: 900)
        let preview = PhotoCropGeometry.fittedSize(image: image, available: CGSize(width: 800, height: 800))
        XCTAssertEqual(preview, CGSize(width: 800, height: 450))
        let a = CGPoint(x: 200, y: 90), b = CGPoint(x: 600, y: 360)
        let crop = PhotoCropGeometry.dragged(start: a, end: b, size: preview)
        let reversed = PhotoCropGeometry.dragged(start: b, end: a, size: preview)
        XCTAssertEqual(crop, reversed)
        let frame = PhotoCropGeometry.frame(crop: crop, size: preview)
        XCTAssertEqual(frame.minX, 200, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 90, accuracy: 0.001)
        XCTAssertEqual(frame.width, 400, accuracy: 0.001)
        XCTAssertEqual(frame.height, 270, accuracy: 0.001)
    }

    @MainActor
    private func withEditor(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model); _ = await model.close() }
        catch { _ = await model.close(); try? FileManager.default.removeItem(at: root); throw error }
        try FileManager.default.removeItem(at: root)
    }

    @MainActor
    func testPartialInkDeletionUndoKeepsUnselectedStrokes() async throws {
        try await withEditor { model in
            let strokes = (0..<3).map { index -> PKStroke in
                let points = [CGPoint(x: 30, y: CGFloat(50 + index * 80)), CGPoint(x: 200, y: CGFloat(50 + index * 80))].map {
                    PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }
                return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date().addingTimeInterval(Double(index))))
            }
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: strokes); model.strokeEnded(); model.finishInkGesture()
            model.selectionIncludesInk = true; model.selectedStrokeIndices = [1]
            model.deleteSelectedObject(); XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 3)
            await model.performRedo(); XCTAssertEqual(model.canvas.drawing.strokes.count, 2)
        }
    }

    @MainActor
    func testTextShapeAndPageUndoRedoUseChronologicalHistory() async throws {
        try await withEditor { model in
            model.addText(); model.addShape(.ellipse)
            XCTAssertEqual(model.page?.texts.count, 1); XCTAssertEqual(model.page?.shapes?.count, 1)
            await model.performUndo(); XCTAssertEqual(model.page?.shapes?.count ?? 0, 0)
            await model.performUndo(); XCTAssertEqual(model.page?.texts.count, 0)
            await model.performRedo(); XCTAssertEqual(model.page?.texts.count, 1)
            let id = model.page?.id
            await model.addPage(); XCTAssertEqual(model.pages.count, 2)
            await model.performUndo(); XCTAssertEqual(model.pages.count, 1); XCTAssertEqual(model.page?.id, id)
            await model.performRedo(); XCTAssertEqual(model.pages.count, 2)
        }
    }

    @MainActor
    func testLastPageDeletionIsUndoableAfterReplacementPageWasCreated() async throws {
        try await withEditor { model in
            model.addText(); _ = await model.flush(); let id = model.page?.id
            await model.deletePage(); XCTAssertNotEqual(model.page?.id, id)
            await model.performUndo(); XCTAssertEqual(model.page?.id, id); XCTAssertEqual(model.page?.texts.count, 1)
            await model.performRedo(); XCTAssertNotEqual(model.page?.id, id)
        }
    }

    @MainActor
    func testMultiwindowLeaseRejectsSecondWriterAndReleasesAfterClose() async throws {
        try await withEditor { model in
            let second = EditorViewModel(workspace: model.workspace)
            await second.open(); XCTAssertFalse(second.hasLease); XCTAssertNotNil(second.error)
            _ = await model.close(); await second.open(); XCTAssertTrue(second.hasLease)
            _ = await second.close()
        }
    }

    @MainActor
    func testCropUndoPreservesOriginalImageFile() async throws {
        try await withEditor { model in
            let data = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50)).pngData { context in
                UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
                UIColor.blue.setFill(); context.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
            }
            let item = try await DocumentServices.importImage(data: data, into: model.workspace)
            model.addImage(item); model.cropSelectedImage(NormalizedCrop(x: 0.5, y: 0, width: 0.5, height: 1))
            XCTAssertEqual(model.page?.images[0].crop?.x, 0.5)
            await model.performUndo(); XCTAssertNil(model.page?.images[0].crop)
            await model.performRedo(); XCTAssertEqual(model.page?.images[0].crop?.width, 0.5)
            let path = try await model.workspace.url(item.file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
        }
    }

    @MainActor
    func testPDFExportPreservesDifferentPageSizesAndSearchableText() async throws {
        try await withEditor { model in
            model.addText(); model.editText([TextElement(text: "Testo ricercabile originale")]); _ = await model.flush()
            var second = PageSnapshot(); second.width = 512; second.height = 768
            _ = try await model.workspace.addPage(second)
            let output = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: output) }
            let pdf = try XCTUnwrap(PDFDocument(url: output))
            XCTAssertEqual(pdf.pageCount, 2)
            XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 768, height: 1024))
            XCTAssertEqual(pdf.page(at: 1)?.bounds(for: .mediaBox).size, CGSize(width: 512, height: 768))
            XCTAssertTrue(pdf.page(at: 0)?.string?.contains("Testo ricercabile originale") == true)
        }
    }

    @MainActor
    func testCancelledPDFExportDoesNotReportSuccess() async throws {
        try await withEditor { model in
            let job = Task { try await DocumentServices.exportPDF(workspace: model.workspace) }
            job.cancel()
            do {
                let output = try await job.value
                try? FileManager.default.removeItem(at: output)
                XCTFail("An already cancelled export must not report a finished PDF")
            } catch is CancellationError { }
        }
    }

    @MainActor
    func testVectorPDFHasNoInkImageXObjectsAndRendersVisibleInk() async throws {
        try await withEditor { model in
            let points = [CGPoint(x: 40, y: 80), CGPoint(x: 300, y: 80)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1, size: CGSize(width: 8, height: 8),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            model.strokeBegan()
            model.canvas.drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
            model.strokeEnded(); _ = await model.flush()
            let output = try await DocumentServices.exportPDF(workspace: model.workspace)
            defer { try? FileManager.default.removeItem(at: output) }
            let document = try XCTUnwrap(CGPDFDocument(output as CFURL)), page = try XCTUnwrap(document.page(at: 1))
            let dictionary = try XCTUnwrap(page.dictionary)
            XCTAssertFalse(PDFResourceProbe.hasImages(dictionary))
            let pdf = try XCTUnwrap(PDFDocument(url: output)), preview = try XCTUnwrap(pdf.page(at: 0))
            let cgImage = try XCTUnwrap(preview.thumbnail(of: CGSize(width: 192, height: 256), for: .mediaBox).cgImage)
            var pixels = [UInt8](repeating: 255, count: 192 * 256 * 4)
            pixels.withUnsafeMutableBytes { bytes in
                if let context = CGContext(data: bytes.baseAddress, width: 192, height: 256, bitsPerComponent: 8,
                    bytesPerRow: 192 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 192, height: 256))
                }
            }
            let dark = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 80 && pixels[$0 + 1] < 80 && pixels[$0 + 2] < 80 }.count
            XCTAssertGreaterThan(dark, 20)
        }
    }
}

private final class PDFResourceProbe {
    var found = false
    let depth: Int
    init(depth: Int) { self.depth = depth }
    static func hasImages(_ dictionary: CGPDFDictionaryRef, depth: Int = 0) -> Bool {
        guard depth < 8 else { return false }
        var resources: CGPDFDictionaryRef?, xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
              CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return false }
        let box = PDFResourceProbe(depth: depth)
        // Core Graphics visits synchronously. A standalone C callback avoids a
        // Swift 6.1 region-analysis crash on the nested recursive closure.
        CGPDFDictionaryApplyFunction(xobjects, inspectPDFXObject, Unmanaged.passUnretained(box).toOpaque())
        return box.found
    }
}

private func inspectPDFXObject(_ key: UnsafePointer<CChar>, _ object: CGPDFObjectRef, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<PDFResourceProbe>.fromOpaque(context).takeUnretainedValue()
    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream), let stream else { return }
    guard let dictionary = CGPDFStreamGetDictionary(stream) else { return }
    var name: UnsafePointer<CChar>?
    if CGPDFDictionaryGetName(dictionary, "Subtype", &name), let name, String(cString: name) == "Image" { box.found = true }
    if PDFResourceProbe.hasImages(dictionary, depth: box.depth + 1) { box.found = true }
}
