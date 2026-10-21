import XCTest
@testable import NeuralNotesCore

final class SystemSearchIdentityTests: XCTestCase {
    func testStableIdentityPointsToDocumentNotRenamableTitle() {
        let document = UUID(), identifier = SystemSearchIdentity.identifier(documentID: document)
        XCTAssertEqual(SystemSearchIdentity.documentID(from: identifier), document)
        XCTAssertEqual(SystemSearchIdentity.identifier(documentID: document), identifier)
        XCTAssertNotEqual(SystemSearchIdentity.identifier(documentID: UUID()), identifier)
    }
    func testExternalAndMalformedActivitiesCannotChooseANotebook() {
        for value in ["https://example.test", "neuralnotes:document:", "neuralnotes:book:\(UUID())", "neuralnotes:document:../private", "neuralnotes:document:\(UUID())?file=other"] {
            XCTAssertNil(SystemSearchIdentity.documentID(from: value))
        }
    }
}
