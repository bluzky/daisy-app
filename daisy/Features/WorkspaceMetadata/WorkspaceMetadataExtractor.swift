import CryptoKit
import Foundation
import JavaScriptCore

nonisolated struct WorkspaceMetadata: Equatable {
    let tags: [WorkspaceMetadataToken]
    let contexts: [WorkspaceMetadataToken]
    let projects: [WorkspaceMetadataToken]
    let tasks: [WorkspaceTaskMetadata]
}

nonisolated struct WorkspaceMetadataToken: Equatable {
    /// Exact source spelling, marker included. `key` is normalized by shared
    /// JavaScript grammar for deterministic lookup.
    let source: String
    let key: String
    let line: Int
}

nonisolated struct WorkspaceTaskMetadata: Equatable, Sendable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?
    /// The marker line without its list marker, checkbox and valid fields.
    let text: String
    let checked: Bool
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
            return try? JSONDecoder().decode(Payload.self, from: data).metadata
        }
    }
}

nonisolated private struct Payload: Decodable {
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

    nonisolated struct Token: Decodable {
        let source: String
        let key: String
        let line: Int

        var metadata: WorkspaceMetadataToken {
            WorkspaceMetadataToken(source: source, key: key, line: line)
        }
    }

    nonisolated struct Task: Decodable {
        let text: String
        let checked: Bool
        let line: Int
        let due: String?
        let scheduled: String?
        let priority: String?

        var metadata: WorkspaceTaskMetadata {
            WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled, priority: priority,
                                  text: text, checked: checked)
        }
    }
}
