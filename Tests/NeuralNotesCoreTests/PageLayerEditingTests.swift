import XCTest
@testable import NeuralNotesCore

final class PageLayerEditingTests: XCTestCase {
    func testMetadataEditingKeepsAllContentAndUsesCanonicalOrderAndBounds() throws {
        var original = PageSnapshot(); original.drawingFile = "drawings/base.drawing"; original.texts = [TextElement(text: "Base retained")]
        let added = try PageLayerEditing.adding(to: original, name: "  Annotazioni  "), id = added.layerID
        var page = added.page
        XCTAssertEqual(page.layers?.map(\.name), ["Base", "Annotazioni"])
        page = try PageLayerEditing.renaming(id, to: "Matematica", in: page)
        page = try PageLayerEditing.opacity(id, value: 0.5, in: page)
        page = try PageLayerEditing.visibility(id, visible: false, in: page)
        page = try PageLayerEditing.lock(id, locked: true, in: page)
        page = try PageLayerEditing.reordering([id, page.id], in: page)
        XCTAssertEqual(page.layers?.first?.id, id); XCTAssertEqual(page.layers?.first?.opacity, 0.5)
        XCTAssertFalse(PageLayers.editable(id, page: page))
        XCTAssertEqual(page.texts, original.texts); XCTAssertEqual(page.drawingFile, original.drawingFile)
        XCTAssertThrowsError(try PageLayerEditing.reordering([id, id], in: page))
        XCTAssertThrowsError(try PageLayerEditing.opacity(id, value: .nan, in: page))
        XCTAssertThrowsError(try PageLayerEditing.opacity(id, value: 1.01, in: page))
        XCTAssertThrowsError(try PageLayerEditing.renaming(id, to: "  ", in: page))
        XCTAssertThrowsError(try PageLayerEditing.removing(id, in: page))
        XCTAssertThrowsError(try PageLayerEditing.removing(page.id, in: page))
        page = try PageLayerEditing.lock(id, locked: false, in: page)
        let removed = try PageLayerEditing.removing(id, in: page)
        XCTAssertEqual(removed.layers?.map(\.id), [page.id]); XCTAssertEqual(removed.texts, original.texts)
        while (page.layers?.count ?? 0) < 16 { page = try PageLayerEditing.adding(to: page, name: "Layer").page }
        XCTAssertThrowsError(try PageLayerEditing.adding(to: page, name: "Excess"))
        XCTAssertNil(original.layers); try PageValidation.validate(page)
    }
    func testDuplicateRemapsObjectsInternalEdgesAndAudioWithoutMutatingOrSharingNativeInk() throws {
        var page = PageSnapshot(); page.drawingFile = "drawings/base.drawing"
        var text = TextElement(text: "Inside"); let outside = TextElement(text: "Outside")
        let added = try PageLayerEditing.adding(to: page, name: "Notes"), id = added.layerID
        page = added.page; text.layerID = id; page.texts = [text, outside]
        var shape = ShapeElement(kind: .triangle, x: 100, y: 100, width: 100, height: 80); shape.layerID = id
        var anchor = StrokeAnchor(signature: "same-native-signature", audioSessionID: UUID(), seconds: 17.25); anchor.layerID = id
        shape.audioAnchor = anchor; page.shapes = [shape]; page.anchors = [anchor]
        var connector = ConnectorElement(from: .init(objectID: text.id, x: 60, y: 90), to: .init(objectID: shape.id, x: 140, y: 100))
        connector.layerID = id
        var external = ConnectorElement(from: .init(objectID: shape.id, x: 140, y: 100), to: .init(objectID: outside.id, x: 60, y: 64))
        external.layerID = id; page.connectors = [connector, external]
        page.layers?[1].drawingFile = "drawings/notes.drawing"
        page.aboveInkObjects = [shape.id]; page.lockedObjects = [text.id]
        let before = page
        XCTAssertThrowsError(try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: nil))
        XCTAssertThrowsError(try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: "drawings/notes.drawing"))
        let result = try PageLayerEditing.duplicating(id, in: page, name: "Copy", drawingCopy: "drawings/copy.drawing")
        let copiedText = try XCTUnwrap(result.page.texts.first(where: { $0.layerID == result.layerID }))
        let copiedShape = try XCTUnwrap(result.page.shapes?.first(where: { $0.layerID == result.layerID }))
        let edges = (result.page.connectors ?? []).filter { $0.layerID == result.layerID }
        XCTAssertEqual(edges[0].from.objectID, copiedText.id); XCTAssertEqual(edges[0].to.objectID, copiedShape.id)
        XCTAssertEqual(edges[1].from.objectID, copiedShape.id); XCTAssertEqual(edges[1].to.objectID, outside.id)
        XCTAssertEqual(result.page.layers?.map(\.id), [page.id, id, result.layerID])
        XCTAssertEqual(result.page.layers?.last?.drawingFile, "drawings/copy.drawing")
        XCTAssertEqual(result.page.anchors.last?.signature, anchor.signature); XCTAssertEqual(result.page.anchors.last?.seconds, 17.25)
        XCTAssertEqual(result.page.anchors.last?.layerID, result.layerID); XCTAssertNotEqual(result.page.anchors.last?.id, anchor.id)
        XCTAssertEqual(copiedShape.audioAnchor?.layerID, result.layerID)
        XCTAssertTrue(result.page.aboveInkObjects?.contains(copiedShape.id) == true)
        XCTAssertTrue(result.page.lockedObjects?.contains(copiedText.id) == true)
        XCTAssertEqual(page, before); try PageValidation.validate(result.page)
        let removed = try PageLayerEditing.removing(id, in: result.page)
        XCTAssertFalse(removed.texts.contains { $0.id == text.id }); XCTAssertTrue(removed.texts.contains { $0.id == copiedText.id })
        XCTAssertEqual(removed.anchors.count, 1); XCTAssertEqual(removed.anchors.first?.layerID, result.layerID)
        try PageValidation.validate(removed)
    }
}
