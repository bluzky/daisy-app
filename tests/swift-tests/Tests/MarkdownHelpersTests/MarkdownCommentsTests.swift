import Foundation
import XCTest
@testable import MarkdownHelpers

final class MarkdownCommentsTests: XCTestCase {

    // MARK: - Reading

    func testAnchoredCommentHasLineAnchorAndNote() {
        let markdown = "# Title\n\nThe API returns {==a 404==}{>>Should be 410<<} today."
        XCTAssertEqual(MarkdownComments.comments(in: markdown),
                       [.init(line: 3, anchor: "a 404", notes: ["Should be 410"])])
    }

    func testCommentOnASpotHasNoAnchor() {
        XCTAssertEqual(MarkdownComments.comments(in: "a {>>clarify<<} b"),
                       [.init(line: 1, anchor: nil, notes: ["clarify"])])
    }

    func testAdjacentNotesAreRepliesToTheSameComment() {
        let comments = MarkdownComments.comments(in: "{==x==}{>>first<<}{>>AI: done<<} {>>separate<<}")
        XCTAssertEqual(comments.map(\.notes), [["first", "AI: done"], ["separate"]])
    }

    func testAnchorCanSpanLinesButNotABlankLine() {
        XCTAssertEqual(MarkdownComments.comments(in: "{==one\ntwo==}{>>n<<}").first?.anchor, "one\ntwo")
        // The paragraph break ends the anchor, so only the bare note is left.
        XCTAssertEqual(MarkdownComments.comments(in: "{==one\n\ntwo==}{>>n<<}"),
                       [.init(line: 3, anchor: nil, notes: ["n"])])
    }

    func testNoteMustStayOnOneLine() {
        XCTAssertEqual(MarkdownComments.comments(in: "{==x==}{>>one\ntwo<<}"), [])
    }

    func testHighlightWithoutANoteIsNotAComment() {
        XCTAssertEqual(MarkdownComments.comments(in: "{==x==} and {>><<}"), [])
    }

    func testCodeAndHTMLCommentsAreLeftAlone() {
        let markdown = """
        `{>>inline<<}`

        ```
        {>>fenced<<}
        ```

        <!-- {>>hidden<<} -->

        \\{>>escaped<<}

        {>>real<<}
        """
        let comments = MarkdownComments.comments(in: markdown)
        XCTAssertEqual(comments.map(\.notes), [["real"]])
        XCTAssertEqual(comments.first?.line, 11)
    }

    // MARK: - Read mode

    func testRenderingWrapsTheAnchorAndKeepsEveryLine() {
        let markdown = "a {==**bold**\ntext==}{>>why <b> & \"q\"<<} z"
        let html = MarkdownComments.rendering(markdown)
        XCTAssertEqual(html, "a <mark class=\"mdp-comment\" tabindex=\"0\" data-comment=\"why &lt;b&gt; &amp; &quot;q&quot;\">**bold**\ntext</mark> z")
        XCTAssertEqual(html.filter(\.isNewline).count, markdown.filter(\.isNewline).count)
    }

    func testRenderingJoinsRepliesAndLeavesOtherTextAlone() {
        let html = MarkdownComments.rendering("{==x==}{>>a<<}{>>b<<}")
        XCTAssertTrue(html.contains("data-comment=\"\u{2022} a&#10;\u{2022} b\" data-list"), html)
        // A single note has no bullet and no list marker.
        let single = MarkdownComments.rendering("{==x==}{>>only<<}")
        XCTAssertTrue(single.contains("data-comment=\"only\">"), single)
        XCTAssertFalse(single.contains("data-list"))
        XCTAssertEqual(MarkdownComments.rendering("nothing here"), "nothing here")
        XCTAssertEqual(MarkdownComments.rendering("`{>>no<<}`"), "`{>>no<<}`")
    }

    func testRenderedPageShowsTheHighlightAndNoteAttribute() {
        let page = MarkdownHTML.render(markdown: "Hello {==world==}{>>greet the planet<<}.").html
        XCTAssertTrue(page.contains("class=\"mdp-comment\""), page)
        XCTAssertTrue(page.contains("data-comment=\"greet the planet\""))
        XCTAssertTrue(page.contains(".mdp-comment::after"), "the stylesheet ships with the page")
    }

    func testDisablingTheExtensionLeavesTheSyntaxLiteral() {
        let page = MarkdownHTML.render(
            markdown: "Hello {==world==}{>>note<<}.",
            renderExtensionConfiguration: .init(enabledIDs: [])
        ).html
        XCTAssertFalse(page.contains("class=\"mdp-comment\""))
    }

    // MARK: - Copy for AI

    func testBriefListsLinesAnchorsAndReplies() {
        let comments = MarkdownComments.comments(in: "x\n{==two\nlines==}{>>fix<<}{>>AI: ok<<}\n{>>spot<<}")
        let brief = MarkdownComments.brief(for: comments, fileName: "notes.md")
        XCTAssertTrue(brief.hasPrefix("2 comments in notes.md."))
        XCTAssertTrue(brief.contains("1. Line 2, on: \"two lines\"\n   Comment: fix\n   Reply: AI: ok\n"))
        XCTAssertTrue(brief.contains("2. Line 4\n   Comment: spot\n"))
    }

    // MARK: - Resolving and replying

    func testResolveKeepsTheAnchorAndDropsTheMarkup() throws {
        let text = "a {==x==}{>>n<<}{>>r<<} b {==y==}{>>m<<}"
        let first = try XCTUnwrap(MarkdownComments.resolveEdit(commentAt: 0, in: text))
        XCTAssertEqual(first.applied(to: text), "a x b {==y==}{>>m<<}")
        let second = try XCTUnwrap(MarkdownComments.resolveEdit(commentAt: 1, in: text))
        XCTAssertEqual(second.applied(to: text), "a {==x==}{>>n<<}{>>r<<} b y")
        XCTAssertNil(MarkdownComments.resolveEdit(commentAt: 2, in: text))
    }

    func testResolvingASpotCommentLeavesNoDoubleSpace() throws {
        let text = "one {>>note<<} two"
        let edit = try XCTUnwrap(MarkdownComments.resolveEdit(commentAt: 0, in: text))
        XCTAssertEqual(edit.applied(to: text), "one two")
        let end = "line {>>note<<}"
        XCTAssertEqual(MarkdownComments.resolveEdit(commentAt: 0, in: end)?.applied(to: end), "line ")
    }

    func testOffsetsAreUTF16SoEmojiBeforeTheCommentDoNotShiftIt() throws {
        let text = "😀 é {==x==}{>>n<<}"
        let edit = try XCTUnwrap(MarkdownComments.resolveEdit(commentAt: 0, in: text))
        XCTAssertEqual(edit.range, 5..<19)
        XCTAssertEqual(edit.applied(to: text), "😀 é x")
    }

    func testReplyGoesAfterTheLastNoteOnOneLine() throws {
        let text = "{==x==}{>>n<<} tail"
        let edit = try XCTUnwrap(MarkdownComments.replyEdit(toCommentAt: 0, note: "AI: done\nok <<} x", in: text))
        XCTAssertEqual(edit.applied(to: text), "{==x==}{>>n<<}{>>AI: done ok << } x<<} tail")
        XCTAssertNil(MarkdownComments.replyEdit(toCommentAt: 0, note: "  ", in: text))
        XCTAssertEqual(MarkdownComments.comments(in: edit.applied(to: text)).first?.notes.count, 2)
    }

    // MARK: - Commenting from Read mode

    private func add(_ note: String, _ text: String, lines: ClosedRange<Int> = 1...1,
                     occurrence: Int = 0, in markdown: String) -> String? {
        let selection = MarkdownComments.PageSelection(text: text, startLine: lines.lowerBound,
                                                       endLine: lines.upperBound, occurrence: occurrence)
        return MarkdownComments.addEdit(note: note, selection: selection, in: markdown)?.applied(to: markdown)
    }

    func testTableCellCommentStaysInItsRow() {
        let table = "| a | b |\n| - | - |\n| cell | x |"
        XCTAssertEqual(add("why | how", "cell", lines: 3...3, in: table),
                       "| a | b |\n| - | - |\n| {==cell==}{>>why &#124; how<<} | x |")
    }

    func testSelectionIsWrappedWhereItSitsInTheSource() {
        XCTAssertEqual(add("why", "second word", in: "first second word third"),
                       "first {==second word==}{>>why<<} third")
    }

    func testSelectionFindsTextAcrossMarkdownMarks() {
        XCTAssertEqual(add("n", "bold and link", in: "a **bold** and [link](http://x.y) z"),
                       "a **{==bold** and [link==}{>>n<<}](http://x.y) z")
        XCTAssertEqual(add("n", "a b", in: "a   b"), "{==a   b==}{>>n<<}")
    }

    func testRepeatedTextIsCommentedWhereItWasSelected() {
        let text = "go go go"
        XCTAssertEqual(add("n", "go", occurrence: 2, in: text), "go go {==go==}{>>n<<}")
        XCTAssertEqual(add("n", "go", occurrence: 0, in: text), "{==go==}{>>n<<} go go")
    }

    func testOnlyTheSelectedBlockIsSearchedAndLinesCountFromOne() {
        let text = "# Title\n\nfind me here\n\nfind me again"
        XCTAssertEqual(add("n", "find me", lines: 5...5, in: text),
                       "# Title\n\nfind me here\n\n{==find me==}{>>n<<} again")
    }

    func testUnfoundTextFallsBackToACommentAtTheEndOfTheBlock() {
        XCTAssertEqual(add("n", "rendered only", lines: 1...2, in: "one  \ntwo  \n\nthree"),
                       "one  \ntwo {>>n<<}  \n\nthree")
    }

    func testBadInputIsRefused() {
        XCTAssertNil(add("  ", "x", in: "x"))
        XCTAssertNil(add("n", " ", in: "x"))
        XCTAssertNil(add("n", "x", lines: 9...9, in: "x"))
    }

    func testAddedCommentsReadBackAsComments() {
        let updated = add("check", "limit", in: "the limit is 5") ?? ""
        XCTAssertEqual(MarkdownComments.comments(in: updated),
                       [.init(line: 1, anchor: "limit", notes: ["check"])])
    }

    // MARK: - Code is never a comment

    func testIndentedCodeBlockIsLeftAlone() throws {
        let markdown = "text\n\n    print(\"{>>literal<<}\")\n    {==x==}{>>also literal<<}\n\nafter {>>real<<}"
        let comments = MarkdownComments.comments(in: markdown)
        XCTAssertEqual(comments.map(\.notes), [["real"]])
        XCTAssertEqual(comments.first?.line, 6)
        // Resolving must not touch the code.
        let edit = try XCTUnwrap(MarkdownComments.resolveEdit(commentAt: 0, in: markdown))
        XCTAssertEqual(edit.applied(to: markdown), "text\n\n    print(\"{>>literal<<}\")\n    {==x==}{>>also literal<<}\n\nafter ")
        XCTAssertEqual(MarkdownComments.rendering(markdown).components(separatedBy: "<span class=\"mdp-comment").count, 2)
    }

    func testInlineCodeSpanOverSeveralLinesIsLeftAlone() {
        let markdown = "see `code\n{>>literal<<} more` and {>>real<<}"
        XCTAssertEqual(MarkdownComments.comments(in: markdown).map(\.notes), [["real"]])
        let double = "x ``a ` b\n{>>literal<<}`` {>>real<<}"
        XCTAssertEqual(MarkdownComments.comments(in: double).map(\.notes), [["real"]])
    }

    func testTildeFenceAndCodeInsideAListAreLeftAlone() {
        let markdown = "~~~\n{>>one<<}\n~~~\n\n- item\n\n      {>>two<<}\n\n- real {>>three<<}"
        XCTAssertEqual(MarkdownComments.comments(in: markdown).map(\.notes), [["three"]])
    }

    func testAnIndentedListParagraphIsNotMistakenForCode() {
        // Four spaces under a two-space list marker is a nested item, not code.
        let markdown = "- item\n\n    - nested {>>real<<}"
        XCTAssertEqual(MarkdownComments.comments(in: markdown).map(\.notes), [["real"]])
        let paragraph = "1. item\n\n   continued {>>real<<}"
        XCTAssertEqual(MarkdownComments.comments(in: paragraph).map(\.notes), [["real"]])
    }

    // MARK: - Review fixes

    func testARepeatedPhraseInAnEarlierNoteIsNotCounted() {
        // The page sees "limit" once before the selection; the note's copy is not on the page.
        let markdown = "the {==cap==}{>>the limit is low<<} and the limit is 5"
        // The reader selected the second "limit" on the page: occurrence 0, as the page counts.
        XCTAssertEqual(add("n", "limit", occurrence: 0, in: markdown),
                       "the {==cap==}{>>the limit is low<<} and the {==limit==}{>>n<<} is 5")
    }

    func testAPhraseInsideAnExistingAnchorIsNotWrappedAgain() {
        let markdown = "see {==the limit==}{>>why<<} here"
        let result = add("n", "limit", in: markdown)
        // It is on the page, so it counts, but nesting is refused: a spot comment instead.
        XCTAssertEqual(result, "see {==the limit==}{>>why<<} here {>>n<<}")
        XCTAssertEqual(MarkdownComments.comments(in: result ?? "").count, 2)
    }

    func testASelectionNeverReachesAcrossABlankLine() {
        let markdown = "> first words\n>\n> more words"
        // A whitespace run in the selection must not match the blank quote line.
        XCTAssertEqual(add("n", "words more", lines: 1...3, in: markdown),
                       "> first words\n>\n> more words {>>n<<}")
    }

    func testLineNumbersCountOnlyTheBreaksTheParserCounts() {
        // U+2028 is not a Markdown line break, so the comment is on line 1, not 2.
        let separator = "\u{2028}"
        XCTAssertEqual(MarkdownComments.comments(in: "a\(separator)b {>>n<<}").first?.line, 1)
        XCTAssertEqual(MarkdownComments.comments(in: "a\rb {>>n<<}").first?.line, 2)
        XCTAssertEqual(MarkdownComments.comments(in: "a\r\nb {>>n<<}").first?.line, 2)
        // addEdit counts the same lines.
        XCTAssertEqual(add("n", "b", lines: 2...2, in: "a\rb"), "a\r{==b==}{>>n<<}")
    }

    func testAnAnchorNeverReachesPastItsFirstClosingMark() {
        // `==}` not followed by a note closes nothing: no comment anchors here.
        let comments = MarkdownComments.comments(in: "{==a==} x ==}{>>n<<}")
        XCTAssertEqual(comments, [.init(line: 1, anchor: nil, notes: ["n"])])
    }
}
