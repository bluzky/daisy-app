import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceMetadataExtractorTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        TestVendor.installWorkspaceMetadataExtractor()
    }

    func testSharedFixtureCorpus() throws {
        XCTAssertTrue(WorkspaceMetadataExtractor.isAvailable)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: fixtureURL))
        for fixture in fixtures {
            let source = fixture.source
            let metadata = try XCTUnwrap(WorkspaceMetadataExtractor.extract(source), fixture.name)
            XCTAssertEqual(metadata, fixture.expected.metadata, fixture.name)
            XCTAssertEqual(source, fixture.source, "\(fixture.name): extraction must be read-only")
        }
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "fixtures/workspace-metadata/grammar.json")
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
    let attributes: [ExpectedAttribute]
    let links: [ExpectedLink]

    var metadata: WorkspaceMetadata {
        WorkspaceMetadata(
            tags: tags.map(\.token),
            contexts: contexts.map(\.token),
            projects: projects.map(\.token),
            tasks: tasks.map(\.task),
            attributes: attributes.map(\.attribute),
            links: links.map { WorkspaceMetadataLink(destination: $0.destination, line: $0.line, excerpt: $0.excerpt) }
        )
    }
}

private struct ExpectedToken: Decodable {
    let source: String
    let key: String
    let line: Int
    let excerpt: String

    var token: WorkspaceMetadataToken {
        WorkspaceMetadataToken(source: source, key: key, line: line, excerpt: excerpt)
    }
}

private struct ExpectedTaskToken: Decodable {
    let kind: String
    let source: String
    let key: String
    let line: Int
    let excerpt: String
}

private struct ExpectedTask: Decodable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?
    let text: String
    let checked: Bool
    let tokens: [ExpectedTaskToken]
    let source: String

    var task: WorkspaceTaskMetadata {
        WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled, priority: priority,
                              text: text, checked: checked,
                              tokens: tokens.map { token in
                                  let kind: WorkspaceMetadataKind = switch token.kind {
                                  case "tags": .tag
                                  case "contexts": .context
                                  default: .project
                                  }
                                  return WorkspaceTokenOccurrence(kind: kind, source: token.source, key: token.key,
                                                                  line: token.line, excerpt: token.excerpt)
                              },
                              source: source)
    }
}

private struct ExpectedAttribute: Decodable {
    let key: String
    let spelling: String
    let line: Int
    let value: ExpectedValue

    var attribute: WorkspaceMetadataAttribute {
        WorkspaceMetadataAttribute(key: key, spelling: spelling, line: line, value: value.value)
    }
}

private struct ExpectedValue: Decodable {
    let type: String
    let text: String
    let number: Double?
    let bool: Bool?
    let date: String?
    let destination: String?
    let items: [ExpectedValue]?

    var value: WorkspaceAttributeValue {
        switch type {
        case "number": .number(number!, text: text)
        case "bool": .bool(bool!, text: text)
        case "date": .date(JournalDay(string: date!)!)
        case "link": .link(destination: destination!, target: nil, text: text)
        case "list": .list(items!.map(\.value))
        default: .text(text)
        }
    }
}

private struct ExpectedLink: Decodable {
    let destination: String
    let line: Int
    let excerpt: String
}
