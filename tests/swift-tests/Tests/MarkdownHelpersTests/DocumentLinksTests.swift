import XCTest
@testable import MarkdownHelpers

final class DocumentLinksTests: XCTestCase {
    func testCollectsInlineLinksInOrderOnly() {
        let markdown = """
        # Notes

        See [the guide](guides/setup.md) and [Apple](https://apple.com).
        ![logo](assets/logo.png)
        Mail <mailto:team@example.com> or [write](mailto:team@example.com).
        Jump to [Usage](#usage). Reference [docs][d], [d][] and [d].
        A [wrapped
        link](notes/wrapped.md) and [Ünïcode → text](a.md).

        [d]: https://example.com/docs
        """
        let links = DocumentLink.collect(from: markdown)
        XCTAssertEqual(links.map(\.destination), [
            "guides/setup.md", "https://apple.com", "mailto:team@example.com", "#usage",
            "notes/wrapped.md", "a.md"
        ])
        XCTAssertEqual(links.map(\.text), ["the guide", "Apple", "write", "Usage", "wrapped link", "Ünïcode → text"])
        XCTAssertEqual(links.map(\.kind), [.file, .web, .web, .section, .file, .file])
    }

    func testRepeatedLinkIsListedOnceAndCodeIsIgnored() {
        let markdown = """
        [a](x.md) and again [a](x.md), but [b](x.md) differs.

            [not](a-link.md)

        `[nor](this.md)`
        """
        XCTAssertEqual(DocumentLink.collect(from: markdown).map(\.text), ["a", "b"])
    }

    func testBareURLsAreNotListed() {
        XCTAssertEqual(DocumentLink.collect(from: "Visit https://example.com today."), [])
    }

    func testFileTargetsResolveAgainstTheDocumentFolder() {
        let document = URL(fileURLWithPath: "/project/guides/setup.md")
        func target(_ destination: String) -> LinkTarget? {
            DocumentLink(id: 0, text: "", destination: destination).target(relativeTo: document)
        }
        XCTAssertEqual(target("../My%20Notes/plan.md#next-steps"),
                       .file(URL(fileURLWithPath: "/project/My Notes/plan.md"), fragment: "next-steps"))
        XCTAssertEqual(target("/abs/file.pdf"), .file(URL(fileURLWithPath: "/abs/file.pdf"), fragment: nil))
        XCTAssertEqual(target("#usage"), .section("usage"))
        XCTAssertEqual(target("https://apple.com"), .external(URL(string: "https://apple.com")!))
        XCTAssertNil(DocumentLink(id: 0, text: "", destination: "x.md").target(relativeTo: nil))
    }
}
