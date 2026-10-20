import XCTest
@testable import NeuralNotesCore

final class LibraryNameTests: XCTestCase {
    func testNamesAreTrimmedAndSupportUnicode() throws {
        XCTAssertEqual(try LibraryName.validated("  Matematica · α 📘  "), "Matematica · α 📘")
    }

    func testEmptyMultilineAndOversizedNamesAreRejected() {
        for name in ["", " \n ", "Lezione\nseconda parte", String(repeating: "a", count: 121)] {
            XCTAssertThrowsError(try LibraryName.validated(name))
        }
        XCTAssertNoThrow(try LibraryName.validated(String(repeating: "a", count: 120)))
    }
}
