import XCTest
@testable import NeuralNotesCore

final class AppInformationTests: XCTestCase {
    func testVersionAndSupportTextUseProvidedBundleValuesOnly() {
        let information = AppInformation(version: "1.0.0", build: "120", system: "18.7", device: "iPad (iPad13,18)")
        XCTAssertEqual(information.versionLabel, "Versione 1.0.0 (build 120)")
        XCTAssertTrue(information.diagnosticText.contains("iPadOS 18.7"))
        XCTAssertTrue(information.diagnosticText.contains("iPad13,18"))
        XCTAssertEqual(AppInformation(version: nil, build: nil, system: "", device: "").versionLabel, "Versione — (build —)")
    }
    func testEmptyNamedAndMalformedCreditsAreSafe() {
        XCTAssertEqual(AppInformation.credits(Data(#"{"names":[]}"#.utf8)), [])
        XCTAssertEqual(AppInformation.credits(Data(#"{"names":[" Anna ","Luca","Anna",""]}"#.utf8)), ["Anna", "Luca"])
        for data in [nil, Data(), Data("broken".utf8), Data(#"{"names":34}"#.utf8), Data(repeating: 1, count: 33_000)] {
            XCTAssertTrue(AppInformation.credits(data).isEmpty)
        }
    }
    func testMissingLinksAndEmailDoNotProduceBrokenActions() {
        XCTAssertNil(AppInformation.publicLink(nil)); XCTAssertNil(AppInformation.feedbackEmail(nil))
        for raw in ["http://example.com", "javascript:alert(1)", "https://user:secret@example.com", "https:"] { XCTAssertNil(AppInformation.publicLink(raw)) }
        XCTAssertEqual(AppInformation.publicLink("https://example.com/support")?.host, "example.com")
        for raw in ["", "bad", "a@b.com\nBcc:other@example.com", "User <a@example.com>"] { XCTAssertNil(AppInformation.feedbackEmail(raw)) }
    }
    func testFeedbackURLDoesNotAllowMailHeaderInjection() throws {
        let information = AppInformation(version: "0.25", build: "53", system: "18", device: "iPad")
        let url = try XCTUnwrap(information.mailURL(email: "feedback@example.com", problem: true))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto"); XCTAssertEqual(components.path, "feedback@example.com")
        XCTAssertEqual(components.queryItems?.count, 2)
        XCTAssertTrue(components.queryItems?.first(where: { $0.name == "body" })?.value?.contains(information.diagnosticText) == true)
        XCTAssertNil(information.mailURL(email: "a@b.com?bcc=other@example.com", problem: false))
    }
}
