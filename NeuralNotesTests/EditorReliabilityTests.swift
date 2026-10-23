import XCTest
import UIKit
import PencilKit
import PDFKit
import PhotosUI
import UniformTypeIdentifiers
import NeuralNotesCore
@testable import NeuralNotes

final class EditorReliabilityTests: XCTestCase {
    @MainActor func testCloudActionsAndInterruptedUploadStayBoundToOriginalAccount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cloud-isolation-\(UUID())", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let study = URL(string: "https://gateway.example/v1/study")!, first = UUID(), second = UUID(), document = UUID()
        let config = Data(#"{"version":1,"managed":true,"auth":{"url":"https://project.example","publicKey":"sb_publishable_fixture_only"}}"#.utf8)
        let service = try ManagedAIService.decode(config, studyURL: study)
        func tokens(_ id: UUID, email: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["access_token": "fixture-access", "refresh_token": "fixture-refresh", "token_type": "bearer", "expires_in": 3600,
                "user": ["id": id.uuidString, "email": email, "is_anonymous": false]])
        }
        let firstData = try tokens(first, email: "a@example.invalid"), secondData = try tokens(second, email: "b@example.invalid")
        let firstOwner = CloudBackupOwner(studyURL: study, userID: first), secondOwner = CloudBackupOwner(studyURL: study, userID: second)
        let store = CloudIsolationSessionStorage(try ManagedAISession.decode(firstData, service: service, now: Date()))
        let auth = ManagedAIClient(transport: CloudIsolationAuthTransport(first: firstData, second: secondData), storage: store)
        let firstFolder = CloudBackupService.storageFolder(for: firstOwner, under: root)
        let secondFolder = CloudBackupService.storageFolder(for: secondOwner, under: root)
        XCTAssertNotEqual(firstFolder, secondFolder)
        var firstQueue = CloudBackupQueue(owner: firstOwner), secondQueue = CloudBackupQueue(owner: secondOwner)
        let firstJob = CloudBackupJob(documentID: document, title: "Originale A", archiveFile: "first.nnbackup", checksum: String(repeating: "a", count: 64), bytes: 1, expectedRevision: 0)
        var secondJob = CloudBackupJob(documentID: document, title: "Originale B", archiveFile: "second.nnbackup", checksum: String(repeating: "b", count: 64), bytes: 1, expectedRevision: 7)
        secondJob.conflict = true
        try firstQueue.enqueue(firstJob); try secondQueue.enqueue(secondJob)
        for (folder, queue, job, byte) in [(firstFolder, firstQueue, firstJob, UInt8(1)), (secondFolder, secondQueue, secondJob, UInt8(2))] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: folder.appendingPathComponent("queue.json"))
            try Data([byte]).write(to: folder.appendingPathComponent(job.archiveFile))
        }
        let unchangedB = try Data(contentsOf: secondFolder.appendingPathComponent("queue.json"))
        let path = "\(first.uuidString.lowercased())/cloud/\(document.uuidString.lowercased())/\(UUID().uuidString.lowercased()).nnbackup"
        let reservation: [String: Any] = ["objectPath": path, "method": "POST", "uploadURL": "https://project.example/storage/v1/object/neuralnotes-private/" + path,
            "publicKey": "sb_publishable_fixture_only", "expectedBytes": 1, "requiresUserBearer": true, "upsert": false]
        let reservationData = try JSONSerialization.data(withJSONObject: reservation)
        let cloud = CloudBackupService(folder: root, client: auth, transport: { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/uploads") == true, "No upload/commit must follow an account change")
            _ = try await auth.verify(email: "b@example.invalid", code: "123456")
            return ManagedAIHTTPResponse(data: reservationData, status: 201)
        })
        await cloud.prepareAccount(); XCTAssertEqual(cloud.queue.owner, firstOwner)
        _ = try await auth.verify(email: "b@example.invalid", code: "123456")
        await cloud.replaceCloudVersion(document) // action from an old A screen, now B is signed in
        XCTAssertEqual(cloud.queue.owner, secondOwner); XCTAssertEqual(cloud.queue.jobs, [secondJob])
        _ = try await auth.verify(email: "a@example.invalid", code: "123456")
        await cloud.discard(document) // old B screen must not remove A's archive
        XCTAssertEqual(cloud.queue.owner, firstOwner); XCTAssertEqual(cloud.queue.jobs, [firstJob])
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFolder.appendingPathComponent(firstJob.archiveFile).path))
        await cloud.retry() // switches A→B while the reservation request is suspended
        XCTAssertEqual(cloud.queue.owner, firstOwner); XCTAssertEqual(cloud.queue.jobs.first?.stage, .prepared)
        XCTAssertNil(cloud.queue.jobs.first?.objectPath); XCTAssertEqual(cloud.queue.jobs.first?.attempts, 1)
        XCTAssertEqual(try Data(contentsOf: secondFolder.appendingPathComponent("queue.json")), unchangedB)
        XCTAssertEqual(try Data(contentsOf: firstFolder.appendingPathComponent(firstJob.archiveFile)), Data([1]))
        await cloud.prepareAccount(); XCTAssertEqual(cloud.queue.owner, secondOwner); XCTAssertEqual(cloud.queue.jobs, [secondJob])
    }

    @MainActor func testChangingToBlankPageDropsOldPresentationLayersAndKeepsSourceData() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model
            model.pagePresenter = host
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
            host.surface.page = try XCTUnwrap(model.page); host.layoutIfNeeded()
            model.addText(); model.updateLiveText("Contenuto della pagina precedente")
            model.endTextEdit()
            let saved = await model.flush(); XCTAssertTrue(saved)
            let source = try XCTUnwrap(model.page)
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
            let oldBitmap = renderer.image { context in
                UIColor.magenta.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            // Model a retained UIKit backing store at high zoom, including replay.
            host.surface.layer.contents = oldBitmap.cgImage
            host.paperDetail.layer.contents = oldBitmap.cgImage
            host.foregroundObjects.layer.contents = oldBitmap.cgImage
            host.lensNotes.layer.contents = oldBitmap.cgImage
            host.inkReplay.image = oldBitmap; host.inkReplay.isHidden = false
            let blank = try await model.workspace.addPage()
            await model.select(blank)
            XCTAssertEqual(model.page?.id, blank.id)
            XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertTrue(try XCTUnwrap(model.page).texts.isEmpty)
            XCTAssertNil(host.surface.layer.contents)
            XCTAssertNil(host.paperDetail.layer.contents)
            XCTAssertNil(host.foregroundObjects.layer.contents)
            XCTAssertNil(host.lensNotes.layer.contents)
            XCTAssertNil(host.inkReplay.image); XCTAssertTrue(host.inkReplay.isHidden)
            let original = try await model.workspace.pageSnapshot(source.id)
            XCTAssertEqual(original.texts, source.texts)
            await model.select(source)
            XCTAssertEqual(model.page?.texts, source.texts)
        }
    }

    @MainActor func testNewlyCommittedPagesCanLoadBeforeTheUIListHasTheirIDs() async throws {
        try await fixture { model in
            let first = try XCTUnwrap(model.page)
            let added = try await model.workspace.addDefaultPage()
            XCTAssertFalse(model.pages.contains(where: { $0.id == added.id }))
            try await model.load(added)
            XCTAssertEqual(model.page?.id, added.id); XCTAssertEqual(model.pages.map(\.id), [first.id, added.id])
            let duplicate = try await model.workspace.duplicatePage(added.id)
            try await model.load(duplicate)
            XCTAssertEqual(model.page?.id, duplicate.id); XCTAssertEqual(model.pages.count, 3)
        }
    }

    @MainActor func testKeyboardHeightChangePreservesManualZoomAndViewport() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 800); host.layoutIfNeeded()
            model.canvas.zoomScale = 1.5; model.canvas.contentOffset = CGPoint(x: 90, y: 120)
            host.frame.size.height = 500; host.setNeedsLayout(); host.layoutIfNeeded()
            XCTAssertEqual(model.canvas.zoomScale, 1.5, accuracy: 0.001)
            XCTAssertEqual(model.canvas.contentOffset.y, 120, accuracy: 1)
        }
    }
    @MainActor func testOnPageTextDoesNotForceKeyboardOrAddASecondKeyboardToolbar() async throws {
        try await fixture { model in
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 800)), root = UIViewController()
            window.rootViewController = root; window.makeKeyAndVisible(); defer { window.isHidden = true }
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.frame = root.view.bounds; root.view.addSubview(host)
            host.surface.page = try XCTUnwrap(model.page); host.layoutIfNeeded()
            let input = CanvasTextInput(host: host, model: model); host.textInput = input
            model.chooseTool(.text); model.beginTextEdit(at: CGPoint(x: 40, y: 100)); input.refresh()
            XCTAssertFalse(input.view.isFirstResponder); XCTAssertNil(input.view.inputAccessoryView)
            XCTAssertTrue(input.view.inputAssistantItem.leadingBarButtonGroups.isEmpty)
            XCTAssertFalse(input.view.isHidden); XCTAssertEqual(input.view.backgroundColor, .clear)
            input.finishEditing()
        }
    }

    @MainActor func testSelectingAPageDoesNotReloadAnUnrelatedBrokenHeader() async throws {
        try await fixture { model in
            let first = try XCTUnwrap(model.page)
            await model.addPage(); let second = try XCTUnwrap(model.page)
            await model.addPage()
            let file = try await model.workspace.url("pages/\(first.id).json")
            try Data("broken offscreen header".utf8).write(to: file)
            await model.select(second)
            XCTAssertEqual(model.page?.id, second.id); XCTAssertNil(model.error)
            XCTAssertNotNil(model.openingTimings["Foglio pronto"])
        }
    }

    @MainActor func testMaintenanceWaitsForIdleAndDoesNotStartFromCleanFlushOrClose() async throws {
        let key = "backup.automatic", previous = UserDefaults.standard.object(forKey: "backup.automatic")
        UserDefaults.standard.set(true, forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        try await fixture { model in
            let manifest = try await model.workspace.manifest()
            model.backupMetadata = Notebook(id: manifest.notebookID, documentID: manifest.documentID, title: "Idle", createdAt: Date(), updatedAt: Date(), folderID: nil, cover: .lagoon, isFavorite: false)
            model.maintenanceDelay = .milliseconds(50)
            let clean = await model.flush(); XCTAssertTrue(clean)
            try await Task.sleep(for: .milliseconds(100))
            let initially = try await model.workspace.automaticBackups(); XCTAssertTrue(initially.isEmpty)
            model.addText(); let saved = await model.flush(); XCTAssertTrue(saved)
            var copied = false
            for _ in 0..<100 {
                if !(try await model.workspace.automaticBackups()).isEmpty { copied = true; break }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTAssertTrue(copied, "A dirty save still gets its idle backup")
            model.addText(); let closed = await model.close(); XCTAssertTrue(closed)
            try await Task.sleep(for: .milliseconds(100))
            let after = try await model.workspace.automaticBackups(); XCTAssertEqual(after.count, 1)
        }
    }

    @MainActor func testGuidedRulerKeepsAllSamplesOnOneEdgeAndSupportsUndo() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 700); host.layoutIfNeeded()
            let assistant = CanvasDrawingAssistant(host: host, model: model)
            host.drawingAssistant = assistant; model.drawingAssistant = assistant
            model.chooseTool(.pen); model.chooseTool(.ruler)
            let guide = RulerGuideView(host: host, model: model); host.rulerGuide = guide; guide.update()
            XCTAssertFalse(guide.isUserInteractionEnabled, "The visual ruler must never intercept Pencil touches")
            XCTAssertTrue(host.gestureRecognizers?.contains { $0.allowedTouchTypes == [NSNumber(value: UITouch.TouchType.direct.rawValue)] && $0.isEnabled } == true)
            model.rulerGuide = RulerGuide(x: 384, y: 300, angle: .pi / 6)
            assistant.begin(at: CGPoint(x: 100, y: 400))
            assistant.move(samples: [CGPoint(x: 200, y: 900), CGPoint(x: 450, y: 50), CGPoint(x: 700, y: 700)])
            assistant.end(cancelled: false)
            XCTAssertFalse(model.hasActiveStroke)
            let stroke = try XCTUnwrap(model.canvas.drawing.strokes.first)
            for point in stroke.path {
                let distance = (point.location.x - 384) * -sin(Double.pi / 6) + (point.location.y - 300) * cos(Double.pi / 6)
                XCTAssertEqual(distance, RulerGuide.halfWidth, accuracy: 0.01)
            }
            await model.performUndo(); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            assistant.begin(at: CGPoint(x: 100, y: 400)); assistant.move(samples: [CGPoint(x: 400, y: 600)])
            assistant.end(cancelled: true); XCTAssertFalse(model.hasActiveStroke); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testBulkTrashRestoreAndUndoPreserveTheCurrentPage() async throws {
        try await fixture { model in
            let first = try XCTUnwrap(model.page?.id)
            await model.addPage(); let second = try XCTUnwrap(model.page?.id)
            await model.addPage(); let third = try XCTUnwrap(model.page?.id)
            await model.deletePages([first, second]); XCTAssertEqual(model.page?.id, third)
            await model.restorePages([second, first]); XCTAssertEqual(model.pages.map(\.id), [third, second, first])
            await model.performUndo(); XCTAssertEqual(model.pages.map(\.id), [third])
            let trash = try await model.workspace.storageReport().removedPages
            XCTAssertEqual(Set(trash.map(\.id)), [first, second]); XCTAssertNil(model.error)
        }
    }
    @MainActor func testDeleteAnyPageKeepsCurrentPageAndUndoRestoresOrder() async throws {
        try await fixture { model in
            let first = try XCTUnwrap(model.page?.id)
            model.editText([TextElement(text: "Da conservare")]); _ = await model.flush()
            await model.addPage(); let second = try XCTUnwrap(model.page?.id)
            await model.addPage(); let third = try XCTUnwrap(model.page?.id)
            await model.deletePage(second)
            XCTAssertEqual(model.pages.map(\.id), [first, third]); XCTAssertEqual(model.page?.id, third)
            await model.performUndo()
            XCTAssertEqual(model.pages.map(\.id), [first, second, third])
            await model.deletePage(third); XCTAssertNotEqual(model.page?.id, third)
            await model.performUndo(); XCTAssertEqual(model.page?.id, third)
            let saved = try await model.workspace.pages(); XCTAssertEqual(saved.first?.texts.first?.text, "Da conservare")
            XCTAssertNil(model.error)
        }
    }
    @MainActor func testRulerConstrainsPenAndMarkerWithoutChangingTheTool() async throws {
        try await fixture { model in
            model.chooseTool(.marker); model.chooseTool(.ruler)
            XCTAssertTrue(model.rulerActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled); XCTAssertTrue(model.rulerActive)
            XCTAssertEqual(model.tool, .marker); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            model.chooseTool(.pen); XCTAssertTrue(model.rulerActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            model.chooseTool(.ruler); XCTAssertFalse(model.canvas.isRulerActive)
            model.chooseTool(.lasso); model.chooseTool(.ruler)
            XCTAssertEqual(model.tool, .pen); XCTAssertTrue(model.rulerActive); XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            // The assistant stores projected native vectors; physical Pencil routing needs device verification.
        }
    }
    @MainActor func testRichTextHeadingColorsHighlightRoundTripIntoPDFAndUndo() async throws {
        try await fixture { model in
            let view = UITextView(); view.attributedText = NSAttributedString(string: "Titolo di prova\nCorpo del testo", attributes: [.font: UIFont.systemFont(ofSize: 18)])
            let formatting = TextFormatting(view: view) {}
            view.selectedRange = NSRange(location: 0, length: 6)
            formatting.paragraphStyle(size: 30, heading: true); formatting.foreground(.systemRed); formatting.highlight(.systemYellow)
            var element = TextElement(text: view.text); element.rtf = try XCTUnwrap(RichText.data(view.attributedText))
            let attributed = RichText.attributed(element)
            XCTAssertEqual((attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize, 30)
            XCTAssertNotNil(attributed.attribute(.backgroundColor, at: 0, effectiveRange: nil))
            let color = try XCTUnwrap(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)); XCTAssertGreaterThan(red, green)
            model.editText([element]); _ = await model.flush()
            let pdf = try await DocumentServices.exportPDF(workspace: model.workspace); defer { try? FileManager.default.removeItem(at: pdf) }
            XCTAssertTrue(PDFDocument(url: pdf)?.page(at: 0)?.string?.contains("Titolo di prova") == true)
            await model.performUndo(); XCTAssertTrue(model.page?.texts.isEmpty == true)
            await model.performRedo(); XCTAssertEqual(model.page?.texts.first?.rtf, element.rtf)
        }
    }
    @MainActor func testExternalPDFReferenceCanSelectConceptWithoutImportingOrChangingItsFile() async throws {
        try await fixture { model in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Reference-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: url) }
            let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { renderer in
                renderer.beginPage(); ("Entropia" as NSString).draw(at: CGPoint(x: 50, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            }; try bytes.write(to: url)
            let before = try await model.workspace.manifest()
            let view = ConceptPDFView(frame: CGRect(x: 0, y: 0, width: 600, height: 800)); view.autoScales = true
            let lensGesture = try XCTUnwrap(view.gestureRecognizers?.first(where: { $0.name == "NeuralNotes.PDFConcept" }))
            XCTAssertNil(lensGesture.delegate)
            XCTAssertEqual(lensGesture.allowedTouchTypes, [NSNumber(value: UITouch.TouchType.pencil.rawValue)])
            XCTAssertFalse(lensGesture.isEnabled)
            view.conceptMode = true; XCTAssertTrue(lensGesture.isEnabled)
            view.conceptMode = false; XCTAssertFalse(lensGesture.isEnabled)
            let controller = PDFStudyController(); controller.attach(view)
            controller.load(file: url.absoluteString, package: model.workspace.package, index: 0, external: url)
            view.layoutIfNeeded()
            let page = try XCTUnwrap(view.document?.page(at: 0)), selection = try XCTUnwrap(page.selection(for: NSRange(location: 0, length: 8)))
            let box = view.convert(selection.bounds(for: page), from: page).insetBy(dx: -2, dy: -2)
            let points = [StrokeSample(x: box.minX, y: box.minY), StrokeSample(x: box.maxX, y: box.minY), StrokeSample(x: box.maxX, y: box.maxY), StrokeSample(x: box.minX, y: box.maxY), StrokeSample(x: box.minX, y: box.minY)]
            XCTAssertTrue(view.selectedConcept(trace: points, page: page)?.contains("Entropia") == true)
            let after = try await model.workspace.manifest(); XCTAssertEqual(after.pageIDs, before.pageIDs)
            XCTAssertEqual(try Data(contentsOf: url), bytes); controller.detach()
        }
    }
    @MainActor func testPDFSearchHighlightsMatchesAndClearsWithoutChangingTheOriginal() async throws {
        try await fixture { model in
            let file = model.workspace.package.appendingPathComponent("attachments/search.pdf")
            let original = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600)).pdfData { renderer in
                for _ in 0..<2 { renderer.beginPage(); ("Entropia e calore" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
            }; try original.write(to: file)
            let view = PDFView(), controller = PDFStudyController()
            controller.attach(view); controller.load(file: "attachments/search.pdf", package: model.workspace.package, index: 0)
            controller.search("entropia")
            for _ in 0..<250 { if !controller.finding { break }; try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(controller.finding); XCTAssertEqual(controller.matches.count, 2)
            XCTAssertEqual(view.highlightedSelections?.count, 2)
            controller.search(""); XCTAssertTrue(controller.matches.isEmpty); XCTAssertTrue(view.highlightedSelections?.isEmpty ?? true)
            XCTAssertEqual(try Data(contentsOf: file), original); controller.detach()
        }
    }
    @MainActor func testZoomNavigatorUsesTheSameCanvasAndKeepsInkUntouched() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model; host.surface.page = try XCTUnwrap(model.page)
            host.frame = CGRect(x: 0, y: 0, width: 1000, height: 700); host.layoutIfNeeded()
            model.canvas.drawing = PKDrawing(strokes: [stroke(.pen)]); let before = model.canvas.drawing.dataRepresentation()
            let fit = model.canvas.minimumZoomScale; model.showZoomNavigator = true; host.alignSurface()
            XCTAssertFalse(host.zoomNavigator.isHidden)
            host.centerWritingArea(CGPoint(x: 500, y: 600))
            XCTAssertGreaterThan(model.canvas.zoomScale, fit * 2)
            XCTAssertTrue(host.canvas === model.canvas); XCTAssertEqual(model.canvas.drawing.dataRepresentation(), before)
            model.showZoomNavigator = false; host.alignSurface(); XCTAssertTrue(host.zoomNavigator.isHidden)
            host.fitPage(animated: false); XCTAssertEqual(model.canvas.zoomScale, fit, accuracy: 0.01)
        }
    }
    @MainActor func testPhotoPickerLoadsAConcretePNGProviderBeforeItsTemporaryFileDisappears() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image { context in UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 80, height: 60)) }
        let data = try XCTUnwrap(image.pngData()), provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in completion(data, nil); return nil }
        let received: Data? = try await withCheckedThrowingContinuation { continuation in
            let coordinator = PhotoLibraryImport.Coordinator { continuation.resume(with: $0) }
            coordinator.load(provider)
        }
        let decoded = try DocumentServices.photoPreview(try XCTUnwrap(received))
        XCTAssertEqual(decoded.cgImage?.width, image.cgImage?.width); XCTAssertEqual(decoded.cgImage?.height, image.cgImage?.height)
    }
    @MainActor func testAudioReplayDoesNotMutateInkAndRestoresDrawingInteraction() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model
            model.canvas.drawing = PKDrawing(strokes: [stroke(.pen), stroke(.marker)])
            let original = model.canvas.drawing.dataRepresentation(), session = UUID()
            let firstKey = "\(model.canvas.drawing.strokes[0].path.creationDate.timeIntervalSince1970):0"
            model.page?.anchors = [StrokeAnchor(signature: firstKey, audioSessionID: session, seconds: 10)]
            host.surface.page = try XCTUnwrap(model.page)
            model.audio?.replayInk = true; model.audio?.playingSessionID = session; model.audio?.playback = 0
            host.inkReplay.update(host)
            XCTAssertFalse(host.inkReplay.isHidden); XCTAssertEqual(model.canvas.layer.opacity, 0)
            XCTAssertFalse(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), original)
            model.audio?.playingSessionID = nil; host.inkReplay.update(host)
            XCTAssertTrue(host.inkReplay.isHidden); XCTAssertEqual(model.canvas.layer.opacity, 1)
            XCTAssertTrue(model.canvas.drawingGestureRecognizer.isEnabled)
            XCTAssertEqual(model.canvas.drawing.dataRepresentation(), original)
        }
    }
    @MainActor func testPageImageAndMarkdownExportKeepContentAndDoNotChangeNotebook() async throws {
        try await fixture { model in
            model.editText([TextElement(text: "Appunto esportabile")]); _ = await model.flush()
            let original = try await model.workspace.pages()
            let png = try model.exportPageImage(), jpeg = try model.exportPageImage(jpeg: true)
            let markdown = try await model.exportNotebookText()
            defer { for file in [png, jpeg, markdown] { try? FileManager.default.removeItem(at: file) } }
            XCTAssertNotNil(UIImage(contentsOfFile: png.path)); XCTAssertNotNil(UIImage(contentsOfFile: jpeg.path))
            XCTAssertTrue(try String(contentsOf: markdown, encoding: .utf8).contains("Appunto esportabile"))
            let after = try await model.workspace.pages(); XCTAssertEqual(original, after)
        }
    }
    @MainActor func testSelectionWidthKeepsOtherStrokesAndSupportsUndo() async throws {
        try await fixture { model in
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke(.pen), stroke(.marker)]); model.strokeEnded(); model.finishInkGesture()
            let second = model.canvas.drawing.strokes[1].path[0].size
            model.chooseTool(.objects); model.selectionIncludesInk = true; model.selectedStrokeIndices = [0]
            model.changeSelectionWidth(3)
            XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].size.width, 3, accuracy: 0.01)
            XCTAssertEqual(model.canvas.drawing.strokes[1].path[0].size, second)
            await model.performUndo(); XCTAssertEqual(model.canvas.drawing.strokes[0].path[0].size.width, 12, accuracy: 0.01)
        }
    }
    @MainActor func testStudyTapeStickyNotesAndLocksSurviveUndoAndPageDuplication() async throws {
        try await fixture { model in
            model.addStickyNote("Definizione")
            let note = try XCTUnwrap(model.page?.texts.first)
            XCTAssertNotNil(note.background)
            model.arrangeSelection(front: true); XCTAssertTrue(model.page?.aboveInkObjects?.contains(note.id) == true)
            model.lockSelection(); model.selectAll(); XCTAssertFalse(model.selectedIDs.contains(note.id))
            model.unlockObjects(); model.selectedObjectID = nil
            model.addStudyTape(); let tape = try XCTUnwrap(model.page?.tapes?.first)
            model.toggleTape(tape.id); XCTAssertTrue(model.page?.tapes?.first?.revealed == true)
            await model.performUndo(); XCTAssertFalse(model.page?.tapes?.first?.revealed ?? true)
            let saved = await model.flush(); XCTAssertTrue(saved)
            let copy = try await model.workspace.duplicatePage(try XCTUnwrap(model.page?.id))
            XCTAssertNotEqual(copy.texts.first?.id, note.id); XCTAssertNotEqual(copy.tapes?.first?.id, tape.id)
            XCTAssertEqual(copy.aboveInkObjects?.first, copy.texts.first?.id)
            XCTAssertNoThrow(try NativePackageInspector.inspect(model.workspace.package))
        }
    }
    @MainActor func testListReturnKeepsFormattingAndEndsAnEmptyItem() {
        let view = UITextView(); view.attributedText = NSAttributedString(string: "1. Primo", attributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
        view.typingAttributes = [.font: UIFont.boldSystemFont(ofSize: 24)]
        var changes = 0; let commands = TextFormatting(view: view) { changes += 1 }
        XCTAssertTrue(commands.replaceNewline(in: NSRange(location: view.text.utf16.count, length: 0), replacement: "\n"))
        XCTAssertEqual(view.text, "1. Primo\n2. ")
        XCTAssertTrue(commands.replaceNewline(in: NSRange(location: view.text.utf16.count, length: 0), replacement: "\n"))
        XCTAssertEqual(view.text, "1. Primo\n"); XCTAssertEqual(changes, 2)
        let font = view.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }
    @MainActor func testChecklistCanBeToggledWithoutEnteringTextModeAndUndone() async throws {
        try await fixture { model in
            var text = TextElement(text: "☐ Attività"); text.x = 50; text.y = 60
            model.editText([text]); model.chooseTool(.pen)
            XCTAssertTrue(model.toggleChecklist(at: CGPoint(x: 56, y: 75)))
            XCTAssertEqual(model.page?.texts.first?.text, "☑ Attività")
            await model.performUndo(); XCTAssertEqual(model.page?.texts.first?.text, "☐ Attività")
        }
    }
    @MainActor private func fixture(_ body: (EditorViewModel) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try NativeDocumentStore(root: root), manifest = DocumentManifest(documentID: UUID(), notebookID: UUID())
        try store.create(manifest)
        let model = EditorViewModel(workspace: DocumentWorkspace(package: store.packageURL(for: manifest.documentID), documentID: manifest.documentID, notebookID: manifest.notebookID))
        await model.open()
        do { try await body(model) } catch { _ = await model.close(); throw error }; _ = await model.close()
    }
    @MainActor private func stroke(_ kind: PKInkingTool.InkType) -> PKStroke {
        let points = [CGPoint(x: 20, y: 80), CGPoint(x: 300, y: 80)].enumerated().map { i, point in
            PKStrokePoint(location: point, timeOffset: Double(i), size: CGSize(width: 12, height: 12), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(kind, color: kind == .marker ? .yellow : .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
    @MainActor func testPencilTextInputIsTransparentOverPaperAndPDF() async throws {
        try await fixture { model in
            let host = CanvasHost(canvas: model.canvas); host.model = model
            let input = CanvasTextInput(host: host, model: model); host.textInput = input
            model.chooseTool(.text); model.beginTextEdit(at: CGPoint(x: 50, y: 60)); host.surface.page = try XCTUnwrap(model.page)
            input.refresh()
            XCTAssertFalse(input.view.isOpaque); XCTAssertEqual(input.view.backgroundColor, .clear); XCTAssertEqual(input.view.layer.borderWidth, 0)
            model.page?.pdfFile = "attachments/test.pdf"; input.refresh()
            XCTAssertEqual(input.view.backgroundColor, .clear)
        }
    }
    @MainActor func testPDFImportAfterUnsavedInkNeverCopiesInkOrTextToImportedPages() async throws {
        try await fixture { model in
            let original = try XCTUnwrap(model.page?.id)
            model.strokeBegan(); model.canvas.drawing = PKDrawing(strokes: [stroke(.pen)]); model.strokeEnded()
            model.editText([TextElement(text: "Appunti della pagina precedente")])
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: file) }
            let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { renderer in
                for _ in 0..<3 { renderer.beginPage(); ("Pagina PDF" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
            }
            try data.write(to: file); await model.importPages(from: file)
            XCTAssertNil(model.error); XCTAssertNotEqual(model.page?.id, original); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            XCTAssertTrue(model.page?.texts.isEmpty == true); XCTAssertEqual(model.pages.count, 4)
            let imported = model.pages.filter { $0.id != original }
            for page in imported {
                let bytes = try await model.workspace.drawing(page)
                XCTAssertNil(bytes); XCTAssertTrue(page.texts.isEmpty); XCTAssertTrue(page.images.isEmpty)
            }
            let templateSaved = await model.useCurrentPDFAsTemplate(); XCTAssertTrue(templateSaved)
            await model.addPage()
            XCTAssertEqual(model.page?.pdfFile, imported.first?.pdfFile); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
            await model.select(try XCTUnwrap(model.pages.first(where: { $0.id == original })))
            XCTAssertEqual(model.canvas.drawing.strokes.count, 1); XCTAssertEqual(model.page?.texts.first?.text, "Appunti della pagina precedente")
            await model.select(try XCTUnwrap(imported.first)); XCTAssertTrue(model.canvas.drawing.strokes.isEmpty)
        }
    }
    @MainActor func testMarkerEraserShowsChangesDuringGestureAndCancelRestoresInk() async throws {
        try await fixture { model in
            model.canvas.drawing = PKDrawing(strokes: [stroke(.pen), stroke(.marker)])
            let original = model.canvas.drawing
            model.chooseTool(.eraser); model.editWriting { $0.markerOnly = true }
            let session = MarkerEraseSession(model: model); model.drawingShape = true
            session.append([StrokeSample(x: 140, y: 60), StrokeSample(x: 140, y: 100)])
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertNil(model.canvas.drawing.strokes[0].mask); XCTAssertNotNil(model.canvas.drawing.strokes[1].mask)
            XCTAssertFalse(model.dirty)
            session.finish(cancelled: true); model.drawingShape = false
            XCTAssertEqual(model.canvas.drawing.strokes.count, original.strokes.count); XCTAssertNil(model.canvas.drawing.strokes[1].mask)
        }
    }
    @MainActor func testPhotoPickerCancellationIsAnExplicitEmptyResult() {
        var finished = false
        let picker = PhotoLibraryImport { result in
            finished = true
            switch result { case .success(let data): XCTAssertNil(data); case .failure(let error): XCTFail(error.localizedDescription) }
        }
        let coordinator = picker.makeCoordinator()
        coordinator.picker(PHPickerViewController(configuration: PHPickerConfiguration()), didFinishPicking: [])
        XCTAssertTrue(finished)
    }
}


private final class CloudIsolationSessionStorage: ManagedAISessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ManagedAISession?
    init(_ value: ManagedAISession) { self.value = value }
    func load() throws -> ManagedAISession? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ session: ManagedAISession?) throws { lock.lock(); defer { lock.unlock() }; value = session }
}
private struct CloudIsolationAuthTransport: ManagedAITransport {
    let first: Data; let second: Data
    func send(_ request: URLRequest) async throws -> ManagedAIHTTPResponse {
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        return ManagedAIHTTPResponse(data: body?["email"] as? String == "a@example.invalid" ? first : second, status: 200)
    }
}
