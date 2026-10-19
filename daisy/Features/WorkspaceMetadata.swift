import Foundation
import JavaScriptCore

struct WorkspaceMetadata: Equatable {
    let tags: [WorkspaceMetadataToken]
    let contexts: [WorkspaceMetadataToken]
    let projects: [WorkspaceMetadataToken]
    let tasks: [WorkspaceTaskMetadata]

    static func extract(_ markdown: String) -> WorkspaceMetadata {
        WorkspaceMetadataExtractor.extract(markdown) ?? .empty
    }

    private static let empty = WorkspaceMetadata(tags: [], contexts: [], projects: [], tasks: [])
}

struct WorkspaceMetadataToken: Equatable {
    /// Exact source spelling, marker included. `key` is normalized by shared
    /// JavaScript grammar for deterministic lookup.
    let source: String
    let key: String
    let line: Int
}

struct WorkspaceTaskMetadata: Equatable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?
}

/// Executes bundled JavaScript grammar. Context stays behind a lock because
/// JavaScriptCore contexts are mutable; extraction itself is read-only.
nonisolated enum WorkspaceMetadataExtractor {
    static var isAvailable: Bool { withEngine { $0 != nil } }

    /// Replaces bundled extractor for helper tests. App code loads
    /// `Vendor/WorkspaceMetadata/workspace-metadata.min.js`.
    static func useExtractor(source: String) {
        lock.lock()
        defer { lock.unlock() }
        engine = Engine(source: source)
    }

    static func extract(_ markdown: String) -> WorkspaceMetadata? {
        withEngine { $0?.extract(markdown) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var engine: Engine??

    private static func withEngine<Result>(_ body: (Engine?) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        if engine == nil {
            let source = VendorResource.string(
                "workspace-metadata.min", ext: "js", subdir: "Vendor/WorkspaceMetadata"
            )
            engine = .some(source.flatMap(Engine.init(source:)))
        }
        return body(engine!)
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
            return try? JSONDecoder().decode(Payload.self, from: data).metadata
        }
    }
}

private struct Payload: Decodable {
    let tags: [Token]
    let contexts: [Token]
    let projects: [Token]
    let tasks: [Task]

    var metadata: WorkspaceMetadata {
        WorkspaceMetadata(
            tags: tags.map(\.metadata),
            contexts: contexts.map(\.metadata),
            projects: projects.map(\.metadata),
            tasks: tasks.map(\.metadata)
        )
    }

    struct Token: Decodable {
        let source: String
        let key: String
        let line: Int

        var metadata: WorkspaceMetadataToken {
            WorkspaceMetadataToken(source: source, key: key, line: line)
        }
    }

    struct Task: Decodable {
        let line: Int
        let due: String?
        let scheduled: String?
        let priority: String?

        var metadata: WorkspaceTaskMetadata {
            WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled, priority: priority)
        }
    }
}
