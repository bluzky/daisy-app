import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceMetadataTests: XCTestCase {
    func testSharedFixtureCorpus() throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtureURL))
        for fixture in fixtures {
            let source = fixture.source
            XCTAssertEqual(WorkspaceMetadata.extract(source), fixture.expected.metadata, fixture.name)
            XCTAssertEqual(source, fixture.source, "\(fixture.name): extraction must be read-only")
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "fixtures/workspace-metadata.json")
    }
}

private struct Fixture: Decodable {
    let name: String
    let source: String
    let expected: Expected
}

private struct Expected: Decodable {
    let tags: [ExpectedToken]
    let contexts: [ExpectedToken]
    let projects: [ExpectedToken]
    let tasks: [ExpectedTask]

    var metadata: WorkspaceMetadata {
        WorkspaceMetadata(
            tags: tags.map(\.token),
            contexts: contexts.map(\.token),
            projects: projects.map(\.token),
            tasks: tasks.map(\.task)
        )
    }
}

private struct ExpectedToken: Decodable {
    let source: String
    let key: String
    let line: Int

    var token: WorkspaceMetadataToken { WorkspaceMetadataToken(source: source, key: key, line: line) }
}

private struct ExpectedTask: Decodable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?

    var task: WorkspaceTaskMetadata {
        WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled, priority: priority)
    }
}
