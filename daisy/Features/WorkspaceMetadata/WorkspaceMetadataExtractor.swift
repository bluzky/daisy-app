import CryptoKit
import Foundation
import JavaScriptCore

/// What the extractor reads from one Markdown text. Lines are 1-based.
nonisolated struct WorkspaceMetadata: Equatable {
    let tags: [WorkspaceMetadataToken]
    let contexts: [WorkspaceMetadataToken]
    let projects: [WorkspaceMetadataToken]
    let tasks: [WorkspaceTaskMetadata]
    var attributes: [WorkspaceMetadataAttribute] = []
    var links: [WorkspaceMetadataLink] = []

    func tokens(_ kind: WorkspaceMetadataKind) -> [WorkspaceMetadataToken] {
        switch kind {
        case .tag: tags
        case .context: contexts
        case .project: projects
        }
    }
}

nonisolated struct WorkspaceMetadataToken: Equatable, Sendable {
    /// Exact source spelling, marker included. `key` is normalized by shared
    /// JavaScript grammar for deterministic lookup.
    let source: String
    let key: String
    let line: Int
    /// The trimmed source line, shortened when long.
    var excerpt: String = ""
    /// Written as a frontmatter `tags`, `contexts` or `projects` value, so
    /// it applies to the whole file.
    var frontmatter = false
}

/// A token as it appears on a line, with its kind: what a task or file
/// record lists.
nonisolated struct WorkspaceTokenOccurrence: Equatable, Sendable {
    let kind: WorkspaceMetadataKind
    let source: String
    let key: String
    let line: Int
    let excerpt: String
    /// From the frontmatter; a file's tasks match it in queries.
    let frontmatter: Bool

    /// The spelling without its one-character marker.
    var spelling: String { String(source.dropFirst()) }

    init(kind: WorkspaceMetadataKind, source: String, key: String, line: Int, excerpt: String,
         frontmatter: Bool = false) {
        self.kind = kind
        self.source = source
        self.key = key
        self.line = line
        self.excerpt = excerpt
        self.frontmatter = frontmatter
    }

    init(kind: WorkspaceMetadataKind, _ token: WorkspaceMetadataToken) {
        self.init(kind: kind, source: token.source, key: token.key, line: token.line, excerpt: token.excerpt,
                  frontmatter: token.frontmatter)
    }
}

nonisolated struct WorkspaceTaskMetadata: Equatable, Sendable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?
    /// The marker line without its list marker, checkbox and valid fields.
    let text: String
    let checked: Bool
    /// The tokens on the task's line.
    var tokens: [WorkspaceTokenOccurrence] = []
    /// The line as written after its checkbox, fields included.
    var source: String = ""
}

/// A frontmatter value, typed as the extractor read it.
nonisolated indirect enum WorkspaceAttributeValue: Equatable, Sendable {
    case text(String)
    case number(Double, text: String)
    case bool(Bool, text: String)
    case date(JournalDay)
    /// A Markdown link written as the value: `"[Up](../index.md)"`. The
    /// extractor leaves `target` nil; a file record resolves it (see
    /// `WorkspaceFileRecord`), nil again when it leaves the root.
    case link(destination: String, target: String?, text: String)
    case list([WorkspaceAttributeValue])

    /// The value as written.
    var text: String {
        switch self {
        case let .text(text), let .number(_, text), let .bool(_, text), let .link(_, _, text): text
        case let .date(day): day.string
        case let .list(items): items.map(\.text).joined(separator: ", ")
        }
    }
}

nonisolated struct WorkspaceMetadataAttribute: Equatable, Sendable {
    /// Normalized like a token key; `spelling` is the key as written.
    let key: String
    let spelling: String
    let line: Int
    let value: WorkspaceAttributeValue
}

/// An inline link to a local file, `[text](destination)`, as written.
nonisolated struct WorkspaceMetadataLink: Equatable, Sendable {
    let destination: String
    let line: Int
    let excerpt: String
}

nonisolated struct WorkspaceIndexedTask: Equatable, Sendable, Identifiable {
    let path: String
    let task: WorkspaceTaskMetadata
    var id: String { "\(path)\u{0}\(task.line)" }
}

/// Executes bundled JavaScript grammar. JavaScriptCore contexts are mutable,
/// so a bounded pool leases one context to each concurrent extraction.
nonisolated enum WorkspaceMetadataExtractor {
    static var isAvailable: Bool { withEngine { _ in true } ?? false }

    /// Replaces bundled extractor for helper tests. App code loads
    /// `Vendor/WorkspaceMetadata/workspace-metadata.min.js`.
    static func useExtractor(source: String) {
        lock.lock()
        defer { lock.unlock() }
        pool = EnginePool(source: source)
    }

    /// SHA-256 of the extractor script, nil when it is missing. A cache of
    /// extracted names is valid only for the script that extracted them.
    static var parserVersion: String? {
        lock.lock()
        defer { lock.unlock() }
        loadBundledPoolIfNeeded()
        return pool?.version
    }

    /// Nil when the bundle is missing or the script fails. Callers must not
    /// treat that as a file with no metadata, or an index would cache it.
    static func extract(_ markdown: String) -> WorkspaceMetadata? {
        withEngine { $0.extract(markdown) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var pool: EnginePool?

    private static func withEngine<Result>(_ body: (Engine) -> Result?) -> Result? {
        lock.lock()
        loadBundledPoolIfNeeded()
        let activePool = pool
        lock.unlock()
        return activePool?.withEngine(body)
    }

    /// Call holding `lock`.
    private static func loadBundledPoolIfNeeded() {
        if pool == nil, let source = VendorResource.string(
            "workspace-metadata.min", ext: "js", subdir: "Vendor/WorkspaceMetadata"
        ) {
            pool = EnginePool(source: source)
        }
    }

    private final class EnginePool: @unchecked Sendable {
        private let source: String
        let version: String
        private let maximumCount = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
        private let condition = NSCondition()
        private var available: [Engine] = []
        private var count = 0

        init(source: String) {
            self.source = source
            version = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        func withEngine<Result>(_ body: (Engine) -> Result?) -> Result? {
            let engine: Engine
            condition.lock()
            while available.isEmpty && count >= maximumCount {
                condition.wait()
            }
            if let availableEngine = available.popLast() {
                engine = availableEngine
                condition.unlock()
            } else {
                count += 1
                condition.unlock()
                guard let createdEngine = Engine(source: source) else {
                    condition.lock()
                    count -= 1
                    condition.broadcast()
                    condition.unlock()
                    return nil
                }
                engine = createdEngine
            }

            let result = body(engine)
            condition.lock()
            available.append(engine)
            condition.signal()
            condition.unlock()
            return result
        }
    }

    private final class Engine: @unchecked Sendable {
        private let context: JSContext
        private let extractor: JSValue
        private let stringify: JSValue

        init?(source: String) {
            guard let context = JSContext() else { return nil }
            context.exceptionHandler = { _, _ in }
            context.evaluateScript(source)
            guard let extractor = context.objectForKeyedSubscript("WorkspaceMetadataExtractor"),
                  extractor.isObject,
                  extractor.hasProperty("extractMetadata"),
                  let stringify = context.evaluateScript("JSON.stringify"),
                  stringify.isObject else { return nil }
            self.context = context
            self.extractor = extractor
            self.stringify = stringify
        }

        func extract(_ markdown: String) -> WorkspaceMetadata? {
            guard let value = extractor.invokeMethod("extractMetadata", withArguments: [markdown]),
                  value.isObject,
                  let json = stringify.call(withArguments: [value])?.toString(),
                  let data = json.data(using: .utf8) else { return nil }
            return (try? JSONDecoder().decode(Payload.self, from: data))?.metadata
        }
    }
}

nonisolated private struct Payload: Decodable {
    let tags: [Token]
    let contexts: [Token]
    let projects: [Token]
    let tasks: [Task]
    let attributes: [Attribute]
    let links: [Link]

    var metadata: WorkspaceMetadata? {
        let attributes = attributes.compactMap(\.metadata)
        guard attributes.count == self.attributes.count else { return nil }
        return WorkspaceMetadata(
            tags: tags.map(\.metadata),
            contexts: contexts.map(\.metadata),
            projects: projects.map(\.metadata),
            tasks: tasks.compactMap(\.metadata),
            attributes: attributes,
            links: links.map { WorkspaceMetadataLink(destination: $0.destination, line: $0.line, excerpt: $0.excerpt) }
        )
    }

    nonisolated struct Token: Decodable {
        let source: String
        let key: String
        let line: Int
        let excerpt: String
        let frontmatter: Bool?

        var metadata: WorkspaceMetadataToken {
            WorkspaceMetadataToken(source: source, key: key, line: line, excerpt: excerpt,
                                   frontmatter: frontmatter ?? false)
        }
    }

    nonisolated struct TaskToken: Decodable {
        let kind: String
        let source: String
        let key: String
        let line: Int
        let excerpt: String
    }

    nonisolated struct Task: Decodable {
        let text: String
        let checked: Bool
        let line: Int
        let due: String?
        let scheduled: String?
        let priority: String?
        let tokens: [TaskToken]
        let source: String

        var metadata: WorkspaceTaskMetadata {
            WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled, priority: priority,
                                  text: text, checked: checked,
                                  tokens: tokens.compactMap { token in
                                      WorkspaceMetadataKind(payloadName: token.kind).map {
                                          WorkspaceTokenOccurrence(kind: $0, source: token.source, key: token.key,
                                                                   line: token.line, excerpt: token.excerpt)
                                      }
                                  },
                                  source: source)
        }
    }

    nonisolated struct Attribute: Decodable {
        let key: String
        let spelling: String
        let line: Int
        let value: Value

        var metadata: WorkspaceMetadataAttribute? {
            value.metadata.map { WorkspaceMetadataAttribute(key: key, spelling: spelling, line: line, value: $0) }
        }
    }

    nonisolated struct Value: Decodable {
        let type: String
        let text: String
        let number: Double?
        let bool: Bool?
        let date: String?
        let destination: String?
        let items: [Value]?

        var metadata: WorkspaceAttributeValue? {
            switch type {
            case "text": return .text(text)
            case "number": return number.map { .number($0, text: text) }
            case "bool": return bool.map { .bool($0, text: text) }
            case "date": return date.flatMap(JournalDay.init(string:)).map(WorkspaceAttributeValue.date)
            case "link": return destination.map { .link(destination: $0, target: nil, text: text) }
            case "list":
                guard let items else { return nil }
                let values = items.compactMap(\.metadata)
                return values.count == items.count ? .list(values) : nil
            default: return nil
            }
        }
    }

    nonisolated struct Link: Decodable {
        let destination: String
        let line: Int
        let excerpt: String
    }
}

nonisolated extension WorkspaceMetadataKind {
    /// The extractor's name for the kind's array: `tags`, `contexts`, `projects`.
    init?(payloadName: String) {
        switch payloadName {
        case "tags": self = .tag
        case "contexts": self = .context
        case "projects": self = .project
        default: return nil
        }
    }
}
