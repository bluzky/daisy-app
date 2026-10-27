//
//  WorkspaceIndexStore.swift
//  daisy
//
//  The on-disk copy of one workspace's index: a SQLite file in the app
//  container's Caches folder, never in the workspace. It only saves the
//  index from rescanning on the next open. Every byte of it is treated as
//  untrusted, anything doubtful is thrown away, and a store that cannot be
//  opened or written leaves the index working in memory. All SQLite calls
//  are in this file.
//

import CryptoKit
import Foundation
import SQLite3

actor WorkspaceIndexStore {
    /// One saved file as the index last read it.
    nonisolated struct Record: Sendable, Equatable {
        let modificationDate: Date?
        let size: Int?
        /// SHA-256 of the file's bytes.
        let hash: Data
        let record: WorkspaceFileRecord
    }

    /// The file cannot be used; the index carries on in memory.
    nonisolated enum StoreError: Error {
        /// Another connection held the file past `busyTimeoutMilliseconds`.
        case busy
        /// It cannot be created, opened, read or written.
        case failed(String)
    }

    /// Bump when the tables change; an older file is rebuilt.
    nonisolated static let schemaVersion = 5
    /// Files saved per transaction, so a write never holds the file long.
    nonisolated static let transactionSize = 256
    /// How long a write waits for another connection before giving up.
    nonisolated static let busyTimeoutMilliseconds: Int32 = 200
    /// The most rows of one kind one file may have. The index reads files of
    /// at most 1 MiB, and each token takes a marker and a character, so a
    /// real file stays far below this; capped, no sum of counts across files
    /// can overflow.
    nonisolated static let maximumOccurrencesPerFile = 1 << 20
    /// A cache nobody opened for this long is deleted at launch.
    nonisolated static let staleInterval: TimeInterval = 30 * 24 * 60 * 60

    /// `Library/Caches/WorkspaceIndex` inside the app container.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "WorkspaceIndex", directoryHint: .isDirectory)
    }

    // MARK: - Locating a workspace's file

    nonisolated struct RootIdentity: Sendable, Equatable {
        let path: String
        let volume: String
    }

    /// The canonical root's path and the UUID of the volume it is on.
    nonisolated static func identity(of root: URL) -> RootIdentity {
        let volume = (try? root.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        var path = root.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return RootIdentity(path: path, volume: volume ?? "")
    }

    /// `<root-id>.sqlite`, the id hashed from the root's path and volume, so
    /// a moved root, or another disk mounted at the same path, gets a file
    /// of its own.
    nonisolated static func cacheURL(for identity: RootIdentity, in directory: URL) -> URL {
        let digest = SHA256.hash(data: Data("\(identity.path)\u{0}\(identity.volume)".utf8))
        let id = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(id).sqlite", directoryHint: .notDirectory)
    }

    /// Deletes the workspace's cache file and SQLite's files beside it.
    nonisolated static func deleteCache(root: URL, in directory: URL) {
        deleteFiles(of: cacheURL(for: identity(of: root), in: directory))
    }

    /// Deletes every cache not opened for `staleInterval`.
    nonisolated static func purgeStaleCaches(in directory: URL, now: Date = Date()) {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
        else { return }
        for url in urls where url.pathExtension == "sqlite" {
            guard let opened = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate,
                  now.timeIntervalSince(opened) > staleInterval else { continue }
            deleteFiles(of: url)
        }
    }

    nonisolated private static func deleteFiles(of url: URL) {
        for suffix in ["", "-wal", "-shm", "-journal"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
        }
    }

    // MARK: - Opening

    nonisolated let url: URL
    private let identity: RootIdentity
    private let parserVersion: String
    /// Only touched on the actor, and by `deinit` once nothing else can.
    nonisolated(unsafe) private var database: OpaquePointer?

    private init(url: URL, identity: RootIdentity, parserVersion: String, database: OpaquePointer) {
        self.url = url
        self.identity = identity
        self.parserVersion = parserVersion
        self.database = database
    }

    deinit {
        if let database { sqlite3_close_v2(database) }
    }

    /// Opens the workspace's cache, creating it, or recreating it when it is
    /// corrupt, from another schema or parser, or for another root. Marks
    /// the file opened now, for `purgeStaleCaches`.
    @concurrent
    nonisolated static func open(root: URL, in directory: URL, parserVersion: String) async throws -> WorkspaceIndexStore {
        let identity = identity(of: root)
        let url = cacheURL(for: identity, in: directory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw StoreError.failed("cannot create \(directory.path): \(error)")
        }
        let database: OpaquePointer
        do {
            database = try connectCompatible(url, identity: identity, parserVersion: parserVersion)
        } catch StoreError.busy {
            throw StoreError.busy
        } catch {
            // Corrupt, foreign or old: it is only derived data, so start over.
            deleteFiles(of: url)
            database = try connect(url)
        }
        do {
            try createSchema(database, identity: identity, parserVersion: parserVersion)
        } catch {
            // Busy, usually: the index falls back to memory and must not
            // keep the file open.
            sqlite3_close_v2(database)
            throw error
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
        return WorkspaceIndexStore(url: url, identity: identity, parserVersion: parserVersion, database: database)
    }

    /// Throws for a file that is not a compatible cache.
    nonisolated private static func connectCompatible(_ url: URL, identity: RootIdentity,
                                                      parserVersion: String) throws -> OpaquePointer {
        let database = try connect(url)
        do {
            guard try isCompatible(database, identity: identity, parserVersion: parserVersion) else {
                throw StoreError.failed("incompatible")
            }
            return database
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
    }

    nonisolated private static func connect(_ url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(url.path(percentEncoded: false), &database, flags, nil)
        guard status == SQLITE_OK, let database else {
            if let database { sqlite3_close_v2(database) }
            throw StoreError.failed("open: \(status)")
        }
        sqlite3_busy_timeout(database, busyTimeoutMilliseconds)
        do {
            // Fails with SQLITE_NOTADB on a file that is not a database.
            try execute(database, "PRAGMA journal_mode = WAL")
            try execute(database, "PRAGMA foreign_keys = ON")
        } catch {
            sqlite3_close_v2(database)
            throw error
        }
        return database
    }

    /// False for a file that holds another schema, parser or root, or fails
    /// SQLite's own check. True for an empty new file.
    nonisolated private static func isCompatible(_ database: OpaquePointer, identity: RootIdentity,
                                                 parserVersion: String) throws -> Bool {
        guard try query(database, "PRAGMA quick_check", { text($0, 0) }) == ["ok"] else { return false }
        let tables = try query(database, "SELECT name FROM sqlite_master WHERE type = 'table'") { text($0, 0) }
        guard !tables.isEmpty else { return true }
        guard Set(tables.compactMap { $0 }) == ["meta", "files", "attributes", "tokens", "links", "tasks"]
        else { return false }
        let rows = try query(database, "SELECT key, value FROM meta") { (text($0, 0), text($0, 1)) }
        let meta = Dictionary(rows.compactMap { key, value in key.flatMap { key in value.map { (key, $0) } } }) {
            first, _ in first
        }
        return meta["schema"] == String(schemaVersion)
            && meta["parser"] == parserVersion
            && meta["root"] == identity.path
            && meta["volume"] == identity.volume
    }

    nonisolated private static func createSchema(_ database: OpaquePointer, identity: RootIdentity,
                                                 parserVersion: String) throws {
        try execute(database, """
            CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS files (
                path TEXT PRIMARY KEY,
                modified REAL,
                size INTEGER,
                hash BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS attributes (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                task_line INTEGER,
                key TEXT NOT NULL,
                spelling TEXT NOT NULL,
                line INTEGER NOT NULL,
                item INTEGER,
                type TEXT NOT NULL,
                text TEXT,
                num REAL,
                destination TEXT,
                target TEXT
            );
            CREATE INDEX IF NOT EXISTS attributes_by_path ON attributes(path);
            CREATE INDEX IF NOT EXISTS attributes_by_text ON attributes(key, text);
            CREATE INDEX IF NOT EXISTS attributes_by_number ON attributes(key, num);
            CREATE TABLE IF NOT EXISTS tokens (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                line INTEGER NOT NULL,
                kind INTEGER NOT NULL,
                key TEXT NOT NULL,
                spelling TEXT NOT NULL,
                excerpt TEXT NOT NULL,
                frontmatter INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS tokens_by_path ON tokens(path);
            CREATE INDEX IF NOT EXISTS tokens_by_key ON tokens(kind, key);
            CREATE TABLE IF NOT EXISTS links (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                line INTEGER NOT NULL,
                destination TEXT NOT NULL,
                target TEXT,
                excerpt TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS links_by_path ON links(path);
            CREATE INDEX IF NOT EXISTS links_by_target ON links(target);
            CREATE TABLE IF NOT EXISTS tasks (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                line INTEGER NOT NULL,
                text TEXT NOT NULL,
                checked INTEGER NOT NULL,
                source TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS tasks_by_path ON tasks(path);
            """)
        let meta = ["schema": String(schemaVersion), "parser": parserVersion,
                    "root": identity.path, "volume": identity.volume]
        try transaction(database) {
            for (key, value) in meta {
                try run(database, "INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)") { statement in
                    bind(statement, 1, key)
                    bind(statement, 2, value)
                }
            }
        }
    }

    // MARK: - Reading and writing

    /// Every saved file, by workspace-relative path. A row that could not
    /// have come from the index means the file cannot be trusted: the cache
    /// is emptied and nothing is returned. That is a path leaving the root,
    /// an unknown kind or type, a spelling that is not a name, a key with
    /// spaces or control characters, text with a line break, a line below
    /// one, a link target leaving the root, an impossible date or priority,
    /// a task field with no task, an attribute twice, more than
    /// `maximumOccurrencesPerFile` rows of a kind for a file, a malformed
    /// hash, or rows for a file that is not there.
    func load() throws -> [String: Record] {
        do {
            return try loadRecords()
        } catch let error as StoreError {
            throw error
        } catch {
            return try discardContents()
        }
    }

    /// A row that fails a check.
    private struct Untrusted: Error {}

    private func loadRecords() throws -> [String: Record] {
        let database = try connection()
        let fileRows = try Self.query(database, "SELECT path, modified, size, hash FROM files") { statement in
            (Self.text(statement, 0), Self.double(statement, 1), Self.int(statement, 2), Self.blob(statement, 3))
        }
        var records: [String: WorkspaceFileRecord] = [:]
        var files: [String: (modified: Double?, size: Int?, hash: Data)] = [:]
        for (path, modified, size, hash) in fileRows {
            guard let path, Self.isSafeRelativePath(path), let hash, hash.count == SHA256.byteCount,
                  size.map({ $0 >= 0 }) ?? true else { throw Untrusted() }
            files[path] = (modified, size, hash)
            records[path] = WorkspaceFileRecord(path: path)
        }
        func check(_ path: String?, _ rows: inout [String: Int]) throws -> String {
            guard let path, records[path] != nil else { throw Untrusted() }
            rows[path, default: 0] += 1
            guard rows[path, default: 0] <= Self.maximumOccurrencesPerFile else { throw Untrusted() }
            return path
        }

        var tokenRows: [String: Int] = [:]
        for row in try Self.query(database, """
            SELECT path, line, kind, key, spelling, excerpt, frontmatter FROM tokens ORDER BY rowid
            """, {
            (Self.text($0, 0), Self.int($0, 1), Self.int($0, 2), Self.text($0, 3), Self.text($0, 4), Self.text($0, 5),
             Self.int($0, 6))
        }) {
            let path = try check(row.0, &tokenRows)
            guard let line = row.1, line > 0, let kind = row.2.flatMap(Self.kind(_:)), let key = row.3,
                  Self.isKey(key), let spelling = row.4, Self.isName(spelling), let excerpt = row.5,
                  Self.isOneLine(excerpt), let frontmatter = row.6, frontmatter == 0 || frontmatter == 1
            else { throw Untrusted() }
            records[path]?.tokens.append(WorkspaceTokenOccurrence(kind: kind, source: kind.marker + spelling,
                                                                  key: key, line: line, excerpt: excerpt,
                                                                  frontmatter: frontmatter == 1))
        }

        var linkRows: [String: Int] = [:]
        for row in try Self.query(database, "SELECT path, line, destination, target, excerpt FROM links ORDER BY rowid", {
            (Self.text($0, 0), Self.int($0, 1), Self.text($0, 2), Self.optionalText($0, 3), Self.text($0, 4))
        }) {
            let path = try check(row.0, &linkRows)
            guard let line = row.1, line > 0, let destination = row.2, !destination.isEmpty,
                  Self.isOneLine(destination), let target = row.3, target.map(Self.isSafeRelativePath) ?? true,
                  let excerpt = row.4, Self.isOneLine(excerpt) else { throw Untrusted() }
            records[path]?.links.append(WorkspaceLinkOccurrence(destination: destination, target: target,
                                                                line: line, excerpt: excerpt))
        }

        var taskRows: [String: Int] = [:]
        var tasks: [String: [Int: (text: String, checked: Bool, source: String)]] = [:]
        var taskOrder: [String: [Int]] = [:]
        for row in try Self.query(database, "SELECT path, line, text, checked, source FROM tasks ORDER BY rowid", {
            (Self.text($0, 0), Self.int($0, 1), Self.text($0, 2), Self.int($0, 3), Self.text($0, 4))
        }) {
            let path = try check(row.0, &taskRows)
            guard let line = row.1, line > 0, let text = row.2, Self.isOneLine(text),
                  let checked = row.3, checked == 0 || checked == 1,
                  let source = row.4, Self.isOneLine(source),
                  tasks[path]?[line] == nil else { throw Untrusted() }
            tasks[path, default: [:]][line] = (text, checked == 1, source)
            taskOrder[path, default: []].append(line)
        }

        var attributeRows: [String: Int] = [:]
        var fields: [String: [Int: [String: String]]] = [:]
        var values: [String: [String: (spelling: String, line: Int, value: WorkspaceAttributeValue?)]] = [:]
        var items: [String: [String: [Int: WorkspaceAttributeValue]]] = [:]
        for row in try Self.query(database, """
            SELECT path, task_line, key, spelling, line, item, type, text, num, destination, target
            FROM attributes ORDER BY rowid
            """, {
            (Self.text($0, 0), Self.optionalInt($0, 1), Self.text($0, 2), Self.text($0, 3), Self.int($0, 4),
             Self.optionalInt($0, 5), Self.text($0, 6), Self.optionalText($0, 7), Self.optionalDouble($0, 8),
             Self.optionalText($0, 9), Self.optionalText($0, 10))
        }) {
            let path = try check(row.0, &attributeRows)
            guard let taskLine = row.1, let key = row.2, Self.isAttributeKey(key), let spelling = row.3,
                  Self.isAttributeKey(spelling), let line = row.4, line > 0, let item = row.5,
                  let type = row.6, let text = row.7, let number = row.8, let destination = row.9,
                  let target = row.10 else { throw Untrusted() }
            if let taskLine {
                // A task's field, as the extractor reads it from the task line.
                guard tasks[path]?[taskLine] != nil, line == taskLine, item == nil, let text,
                      fields[path]?[taskLine]?[key] == nil else { throw Untrusted() }
                switch (key, type) {
                case ("due", "date"), ("scheduled", "date"):
                    guard JournalDay(string: text) != nil else { throw Untrusted() }
                case ("priority", "text"):
                    guard ["high", "medium", "low"].contains(text) else { throw Untrusted() }
                default:
                    throw Untrusted()
                }
                fields[path, default: [:]][taskLine, default: [:]][key] = text
                continue
            }
            guard let value = try Self.attributeValue(type: type, text: text, number: number,
                                                      destination: destination, target: target)
            else {
                // A list's own row; its items follow with `item` set.
                guard type == "list", item == nil, text == nil, values[path]?[key] == nil else { throw Untrusted() }
                values[path, default: [:]][key] = (spelling, line, nil)
                continue
            }
            if let item {
                guard item >= 0, values[path]?[key]?.value == nil, values[path]?[key] != nil,
                      items[path]?[key]?[item] == nil else { throw Untrusted() }
                items[path, default: [:]][key, default: [:]][item] = value
            } else {
                guard values[path]?[key] == nil else { throw Untrusted() }
                values[path, default: [:]][key] = (spelling, line, value)
            }
        }

        for (path, keys) in values {
            for (key, entry) in keys {
                let value: WorkspaceAttributeValue
                if let scalar = entry.value {
                    value = scalar
                } else {
                    let listed = items[path]?[key] ?? [:]
                    guard listed.keys.sorted() == Array(0..<listed.count) else { throw Untrusted() }
                    value = .list(listed.keys.sorted().compactMap { listed[$0] })
                }
                records[path]?.attributes[key] = WorkspaceMetadataAttribute(key: key, spelling: entry.spelling,
                                                                            line: entry.line, value: value)
            }
        }
        for (path, lines) in taskOrder {
            let tokens = records[path]?.tokens ?? []
            records[path]?.tasks = lines.map { line in
                let task = tasks[path]![line]!
                let field = fields[path]?[line] ?? [:]
                return WorkspaceTaskMetadata(line: line, due: field["due"], scheduled: field["scheduled"],
                                             priority: field["priority"], text: task.text, checked: task.checked,
                                             tokens: tokens.filter { $0.line == line }, source: task.source)
            }
        }
        var result: [String: Record] = [:]
        for (path, file) in files {
            result[path] = Record(modificationDate: file.modified.map(Date.init(timeIntervalSinceReferenceDate:)),
                                  size: file.size, hash: file.hash, record: records[path]!)
        }
        return result
    }

    /// A scalar value from a row, or nil for a list's own row.
    nonisolated private static func attributeValue(type: String, text: String?, number: Double?,
                                                   destination: String?, target: String?) throws
        -> WorkspaceAttributeValue? {
        if let text, !isOneLine(text) { throw Untrusted() }
        switch type {
        case "list":
            return nil
        case "text":
            guard let text, number == nil, destination == nil, target == nil else { throw Untrusted() }
            return .text(text)
        case "number":
            guard let text, let number, number.isFinite, destination == nil, target == nil else { throw Untrusted() }
            return .number(number, text: text)
        case "bool":
            guard let text, let number, number == 0 || number == 1, destination == nil,
                  target == nil else { throw Untrusted() }
            return .bool(number == 1, text: text)
        case "date":
            guard let text, let day = JournalDay(string: text), number == nil, destination == nil,
                  target == nil else { throw Untrusted() }
            return .date(day)
        case "link":
            guard let text, number == nil, let destination, !destination.isEmpty,
                  target.map(isSafeRelativePath) ?? true else { throw Untrusted() }
            return .link(destination: destination, target: target, text: text)
        default:
            throw Untrusted()
        }
    }

    /// Saves or, for nil, forgets each file, a bounded transaction at a time.
    func write(_ changes: [(path: String, record: Record?)]) throws {
        let database = try connection()
        var start = 0
        while start < changes.count {
            let chunk = changes[start..<min(start + Self.transactionSize, changes.count)]
            try Self.transaction(database) {
                for (path, record) in chunk where Self.isSafeRelativePath(path) {
                    try Self.run(database, "DELETE FROM files WHERE path = ?") { Self.bind($0, 1, path) }
                    guard let record else { continue }
                    try Self.insert(record, at: path, into: database)
                }
            }
            start += chunk.count
        }
    }

    nonisolated private static func insert(_ record: Record, at path: String, into database: OpaquePointer) throws {
        try run(database, "INSERT INTO files (path, modified, size, hash) VALUES (?, ?, ?, ?)") {
            bind($0, 1, path)
            bind($0, 2, record.modificationDate?.timeIntervalSinceReferenceDate)
            bind($0, 3, record.size)
            bind($0, 4, record.hash)
        }
        let file = record.record
        for token in file.tokens {
            try run(database, """
                INSERT INTO tokens (path, line, kind, key, spelling, excerpt, frontmatter)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """) {
                bind($0, 1, path)
                bind($0, 2, token.line)
                bind($0, 3, code(token.kind))
                bind($0, 4, token.key)
                bind($0, 5, token.spelling)
                bind($0, 6, token.excerpt)
                bind($0, 7, token.frontmatter ? 1 : 0)
            }
        }
        for link in file.links {
            try run(database, "INSERT INTO links (path, line, destination, target, excerpt) VALUES (?, ?, ?, ?, ?)") {
                bind($0, 1, path)
                bind($0, 2, link.line)
                bind($0, 3, link.destination)
                bind($0, 4, link.target)
                bind($0, 5, link.excerpt)
            }
        }
        for task in file.tasks {
            try run(database, "INSERT INTO tasks (path, line, text, checked, source) VALUES (?, ?, ?, ?, ?)") {
                bind($0, 1, path)
                bind($0, 2, task.line)
                bind($0, 3, task.text)
                bind($0, 4, task.checked ? 1 : 0)
                bind($0, 5, task.source)
            }
            for (key, value) in [("due", task.due), ("scheduled", task.scheduled), ("priority", task.priority)] {
                guard let value else { continue }
                try insertAttribute(path: path, taskLine: task.line, key: key, spelling: key, line: task.line,
                                    item: nil, value: .text(value),
                                    type: key == "priority" ? "text" : "date", into: database)
            }
        }
        for attribute in file.attributes.values.sorted(by: { $0.line < $1.line }) {
            if case let .list(values) = attribute.value {
                try insertAttribute(path: path, taskLine: nil, key: attribute.key, spelling: attribute.spelling,
                                    line: attribute.line, item: nil, value: nil, type: "list", into: database)
                for (item, value) in values.enumerated() {
                    try insertAttribute(path: path, taskLine: nil, key: attribute.key, spelling: attribute.spelling,
                                        line: attribute.line, item: item, value: value, type: nil, into: database)
                }
            } else {
                try insertAttribute(path: path, taskLine: nil, key: attribute.key, spelling: attribute.spelling,
                                    line: attribute.line, item: nil, value: attribute.value, type: nil,
                                    into: database)
            }
        }
    }

    /// One `attributes` row. `type` overrides the value's own, for task fields
    /// stored as text.
    nonisolated private static func insertAttribute(path: String, taskLine: Int?, key: String, spelling: String,
                                                    line: Int, item: Int?, value: WorkspaceAttributeValue?,
                                                    type: String?, into database: OpaquePointer) throws {
        var columns: (type: String, text: String?, number: Double?, destination: String?, target: String?)
        switch value {
        case nil: columns = ("list", nil, nil, nil, nil)
        case let .text(text)?: columns = ("text", text, nil, nil, nil)
        case let .number(number, text)?: columns = ("number", text, number, nil, nil)
        case let .bool(bool, text)?: columns = ("bool", text, bool ? 1 : 0, nil, nil)
        case let .date(day)?: columns = ("date", day.string, nil, nil, nil)
        case let .link(destination, target, text)?: columns = ("link", text, nil, destination, target)
        // The extractor never nests lists.
        case .list?: return
        }
        if let type { columns.type = type }
        try run(database, """
            INSERT INTO attributes (path, task_line, key, spelling, line, item, type, text, num, destination, target)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """) {
            bind($0, 1, path)
            bind($0, 2, taskLine)
            bind($0, 3, key)
            bind($0, 4, spelling)
            bind($0, 5, line)
            bind($0, 6, item)
            bind($0, 7, columns.type)
            bind($0, 8, columns.text)
            bind($0, 9, columns.number)
            bind($0, 10, columns.destination)
            bind($0, 11, columns.target)
        }
    }

    /// Deletes this workspace's file and starts an empty one in its place.
    func reset() throws {
        close()
        Self.deleteFiles(of: url)
        let database = try Self.connect(url)
        self.database = database
        try Self.createSchema(database, identity: identity, parserVersion: parserVersion)
    }

    func close() {
        if let database { sqlite3_close_v2(database) }
        database = nil
    }

    private func connection() throws -> OpaquePointer {
        guard let database else { throw StoreError.failed("closed") }
        return database
    }

    private func discardContents() throws -> [String: Record] {
        try reset()
        return [:]
    }

    /// Relative, normalized and inside the root: no empty, `.` or `..`
    /// component, no leading slash, no NUL.
    nonisolated static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\u{0}") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// A name after its marker, by the rules of `isMetadataName` in
    /// `scripts/editor-bundle/src/metadata-names.js`: it starts with a
    /// letter, number, `_` or `-`, goes on with those, marks and `/`, has a
    /// letter, and has no empty `/` segment.
    nonisolated static func isName(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first, isTokenStart(first),
              scalars.allSatisfy({ isTokenStart($0) || $0 == "/" || isMark($0) }),
              scalars.contains(where: isLetter),
              !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: \.isEmpty)
        else { return false }
        return true
    }

    /// No line break or other control character.
    nonisolated static func isOneLine(_ value: String) -> Bool {
        !value.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    /// A frontmatter key, as written or normalized: not empty, one line.
    nonisolated static func isAttributeKey(_ value: String) -> Bool {
        !value.isEmpty && isOneLine(value)
    }

    /// A lookup key: the extractor's NFKC lowercase form of a name, which
    /// Swift does not recompute. It is checked only for what no name's key
    /// can hold.
    nonisolated static func isKey(_ value: String) -> Bool {
        !value.isEmpty && !value.unicodeScalars.contains {
            $0.properties.isWhitespace || $0.properties.generalCategory == .control
        }
    }

    nonisolated private static func isTokenStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "-" || isLetter(scalar) || isNumber(scalar)
    }

    nonisolated private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    nonisolated private static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }

    nonisolated private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    nonisolated private static func code(_ kind: WorkspaceMetadataKind) -> Int {
        switch kind {
        case .tag: 0
        case .context: 1
        case .project: 2
        }
    }

    nonisolated private static func kind(_ code: Int) -> WorkspaceMetadataKind? {
        switch code {
        case 0: .tag
        case 1: .context
        case 2: .project
        default: nil
        }
    }

    // MARK: - SQLite

    nonisolated private static func failure(_ database: OpaquePointer, _ status: Int32) -> StoreError {
        if status == SQLITE_BUSY || status == SQLITE_LOCKED { return .busy }
        return .failed("\(status): \(String(cString: sqlite3_errmsg(database)))")
    }

    nonisolated private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        let status = sqlite3_exec(database, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw failure(database, status) }
    }

    nonisolated private static func transaction(_ database: OpaquePointer, _ body: () throws -> Void) throws {
        try execute(database, "BEGIN IMMEDIATE")
        do {
            try body()
            try execute(database, "COMMIT")
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    nonisolated private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else { throw failure(database, status) }
        return statement
    }

    nonisolated private static func run(_ database: OpaquePointer, _ sql: String,
                                        _ bindings: (OpaquePointer) -> Void) throws {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE else { throw failure(database, status) }
    }

    nonisolated private static func query<Row>(_ database: OpaquePointer, _ sql: String,
                                               _ row: (OpaquePointer) -> Row) throws -> [Row] {
        let statement = try prepare(database, sql)
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw failure(database, status) }
            rows.append(row(statement))
        }
    }

    /// SQLite copies the value before the call returns.
    nonisolated private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    nonisolated private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, transient)
    }

    nonisolated private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value { bind(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }

    nonisolated private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int?) {
        if let value { sqlite3_bind_int64(statement, index, Int64(value)) } else { sqlite3_bind_null(statement, index) }
    }

    nonisolated private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(statement, index, value) } else { sqlite3_bind_null(statement, index) }
    }

    nonisolated private static func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Data) {
        value.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
        }
    }

    nonisolated private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    /// Outer nil is a malformed column; inner nil is SQL NULL.
    nonisolated private static func optionalText(_ statement: OpaquePointer, _ column: Int32) -> String?? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return .some(nil) }
        return text(statement, column).map(Optional.some)
    }

    /// Outer nil is a malformed column; inner nil is SQL NULL.
    nonisolated private static func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int?? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return .some(nil) }
        return int(statement, column).map(Optional.some)
    }

    /// Outer nil is a malformed column; inner nil is SQL NULL.
    nonisolated private static func optionalDouble(_ statement: OpaquePointer, _ column: Int32) -> Double?? {
        if sqlite3_column_type(statement, column) == SQLITE_NULL { return .some(nil) }
        return double(statement, column).map(Optional.some)
    }

    nonisolated private static func int(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        guard sqlite3_column_type(statement, column) == SQLITE_INTEGER else { return nil }
        return Int(sqlite3_column_int64(statement, column))
    }

    nonisolated private static func double(_ statement: OpaquePointer, _ column: Int32) -> Double? {
        guard sqlite3_column_type(statement, column) == SQLITE_FLOAT else { return nil }
        return sqlite3_column_double(statement, column)
    }

    nonisolated private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: count)
    }
}
