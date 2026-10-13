import XCTest
@testable import MarkdownHelpers

final class FindResultTests: XCTestCase {
    func testDecodesCountsAndFlagsFromScriptResult() throws {
        let result = try XCTUnwrap(FindResult(scriptResult: ["index": 3, "total": 12, "capped": true, "error": false]))
        XCTAssertEqual(result.index, 3)
        XCTAssertEqual(result.total, 12)
        XCTAssertTrue(result.capped)
        XCTAssertFalse(result.error)
    }

    func testFlagsDefaultToFalseAndMissingCountsFail() throws {
        let result = try XCTUnwrap(FindResult(scriptResult: ["index": 0, "total": 0]))
        XCTAssertFalse(result.capped)
        XCTAssertFalse(result.error)
        XCTAssertNil(FindResult(scriptResult: ["index": 1]))
        XCTAssertNil(FindResult(scriptResult: nil))
    }

    func testOptionsSerializeForScripts() {
        XCTAssertEqual(SearchOptions().javaScriptLiteral, "{mode:\"substring\",caseSensitive:false}")
        XCTAssertEqual(SearchOptions(mode: .regex, caseSensitive: true).javaScriptLiteral,
                       "{mode:\"regex\",caseSensitive:true}")
    }
}
