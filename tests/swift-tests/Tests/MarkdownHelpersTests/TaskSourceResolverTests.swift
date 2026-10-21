import Foundation
import XCTest
@testable import MarkdownHelpers

final class TaskSourceResolverTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestVendor.installWorkspaceMetadataExtractor()
    }

    private func task(_ text: String, line: Int, checked: Bool = false) -> WorkspaceTaskMetadata {
        WorkspaceTaskMetadata(line: line, due: nil, scheduled: nil, priority: nil, text: text, checked: checked)
    }

    func testLineUnchanged() {
        let change = TaskSourceResolver.settingChecked(true, task: task("Ship", line: 2),
                                                       in: "# Notes\n- [ ] Ship due:2026-10-21\n- [ ] Ship later")
        XCTAssertEqual(change, .init(line: 2, markdown: "# Notes\n- [x] Ship due:2026-10-21\n- [ ] Ship later",
                                     isChange: true))
    }

    func testLineMoved() {
        let change = TaskSourceResolver.settingChecked(true, task: task("Ship", line: 1),
                                                       in: "Intro\n\n> - [ ] Ship")
        XCTAssertEqual(change?.line, 3)
        XCTAssertEqual(change?.markdown, "Intro\n\n> - [x] Ship")
    }

    func testDuplicateTextOnStaleLineIsRefused() {
        XCTAssertNil(TaskSourceResolver.settingChecked(true, task: task("Same", line: 9),
                                                       in: "- [ ] Same\n- [ ] Same"))
    }

    func testDuplicateTextOnRightLineIsUsed() {
        XCTAssertEqual(TaskSourceResolver.settingChecked(true, task: task("Same", line: 2),
                                                         in: "- [ ] Same\n- [ ] Same")?.markdown,
                       "- [ ] Same\n- [x] Same")
    }

    func testAlreadyCheckedChangesNothing() {
        let source = "- [X] Done"
        XCTAssertEqual(TaskSourceResolver.settingChecked(true, task: task("Done", line: 1), in: source),
                       .init(line: 1, markdown: source, isChange: false))
    }

    func testRemovedOrCodeTaskIsNotFound() {
        XCTAssertNil(TaskSourceResolver.settingChecked(true, task: task("Gone", line: 1), in: "- [ ] Other"))
        XCTAssertNil(TaskSourceResolver.settingChecked(true, task: task("Code", line: 2),
                                                       in: "```\n- [ ] Code\n```"))
    }
}
