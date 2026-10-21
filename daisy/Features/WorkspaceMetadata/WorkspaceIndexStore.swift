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
        let contribution: WorkspaceMetadataContribution
    }

    /// The file cannot be used; the index carries on in memory.
    nonisolated enum StoreError: Error {
        /// Another connection held the file past `busyTimeoutMilliseconds`.
        case busy
        /// It cannot be created, opened, read or written.
        case failed(String)
    }

    /// Bump when the tables change; an older file is rebuilt.
    nonisolated static let schemaVersion = 2
    /// Files saved per transaction, so a write never holds the file long.
    nonisolated static let transactionSize = 256
    /// How long a write waits for another connection before giving up.
    nonisolated static let busyTimeoutMilliseconds: Int32 = 200
    /// The most occurrences one file's rows may add up to. The index reads
    /// files of at most 1 MiB, and each occurrence takes a marker and a
    /// character, so a real file stays far below this; capped, no sum of
    /// counts across files can overflow.
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
        guard Set(tables.compactMap { $0 }) == ["meta", "files", "tokens", "tasks"] else { return false }
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
            CREATE TABLE IF NOT EXISTS tokens (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                kind INTEGER NOT NULL,
                key TEXT NOT NULL,
                spelling TEXT NOT NULL,
                count INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS tokens_by_path ON tokens(path);
            CREATE TABLE IF NOT EXISTS tasks (
                path TEXT NOT NULL REFERENCES files(path) ON DELETE CASCADE,
                line INTEGER NOT NULL,
                text TEXT NOT NULL,
                checked INTEGER NOT NULL,
                due TEXT,
                scheduled TEXT,
                priority TEXT
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
    /// have come from the index (a path leaving the root, an unknown kind,
    /// a spelling that is not a name, a key with spaces or control
    /// characters, a token twice, a count below one or over
    /// `maximumOccurrencesPerFile` in all, a malformed hash) means the file
    /// cannot be trusted: the cache is emptied and nothing is returned.
    func load() throws -> [String: Record] {
        let database = try connection()
        let rows = try Self.query(database, "SELECT path, modified, size, hash FROM files") { statement in
            (Self.text(statement, 0), Self.double(statement, 1), Self.int(statement, 2), Self.blob(statement, 3))
        }
        let tokens = try Self.query(database, "SELECT path, kind, key, spelling, count FROM tokens") { statement in
            (Self.text(statement, 0), Self.int(statement, 1), Self.text(statement, 2),
             Self.text(statement, 3), Self.int(statement, 4))
        }
        let taskRows = try Self.query(database, """
            SELECT path, line, text, checked, due, scheduled, priority FROM tasks ORDER BY path, line, rowid
            """) { statement in
            (Self.text(statement, 0), Self.int(statement, 1), Self.text(statement, 2), Self.int(statement, 3),
             Self.optionalText(statement, 4), Self.optionalText(statement, 5), Self.optionalText(statement, 6))
        }
        var contributions: [String: WorkspaceMetadataContribution] = [:]
        var occurrences: [String: Int] = [:]
        var tasks: [String: [WorkspaceTaskMetadata]] = [:]
        for (path, line, text, checked, due, scheduled, priority) in taskRows {
            guard let path, let line, line > 0, let text, !text.contains("\n"), !text.contains("\r"),
                  let checked, checked == 0 || checked == 1,
                  let due, let scheduled, let priority,
                  due.map(Self.isTaskDate) ?? true, scheduled.map(Self.isTaskDate) ?? true,
                  priority.map(["high", "medium", "low"].contains) ?? true,
                  tasks[path, default: []].count < Self.maximumOccurrencesPerFile
            else { return try discardContents() }
            tasks[path, default: []].append(WorkspaceTaskMetadata(line: line, due: due, scheduled: scheduled,
                                                                  priority: priority, text: text,
                                                                  checked: checked == 1))
        }
        var seen: Set<[String]> = []
        for (path, kind, key, spelling, count) in tokens {
            guard let path, let kind = kind.flatMap(Self.kind(_:)), let key, Self.isKey(key),
                  let spelling, Self.isName(spelling), let count, count > 0,
                  count <= Self.maximumOccurrencesPerFile - occurrences[path, default: 0],
                  seen.insert([path, String(Self.code(kind)), key, spelling]).inserted
            else { return try discardContents() }
            occurrences[path, default: 0] += count
            contributions[path, default: WorkspaceMetadataContribution()]
                .add(kind: kind, key: key, spelling: spelling, count: count)
        }
        var records: [String: Record] = [:]
        for (path, modified, size, hash) in rows {
            guard let path, Self.isSafeRelativePath(path), let hash, hash.count == SHA256.byteCount,
                  size.map({ $0 >= 0 }) ?? true else { return try discardContents() }
            var contribution = contributions.removeValue(forKey: path) ?? WorkspaceMetadataContribution()
            contribution.tasks = tasks.removeValue(forKey: path) ?? []
            records[path] = Record(modificationDate: modified.map(Date.init(timeIntervalSinceReferenceDate:)),
                                   size: size, hash: hash, contribution: contribution)
        }
        // Tokens or tasks for a file that is not there.
        guard contributions.isEmpty, tasks.isEmpty else { return try discardContents() }
        return records
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
                    try Self.run(database, "INSERT INTO files (path, modified, size, hash) VALUES (?, ?, ?, ?)") {
                        Self.bind($0, 1, path)
                        Self.bind($0, 2, record.modificationDate?.timeIntervalSinceReferenceDate)
                        Self.bind($0, 3, record.size)
                        Self.bind($0, 4, record.hash)
                    }
                    for (kind, keys) in record.contribution.names {
                        for (key, spellings) in keys {
                            for (spelling, count) in spellings {
                                try Self.run(database, """
                                    INSERT INTO tokens (path, kind, key, spelling, count) VALUES (?, ?, ?, ?, ?)
                                    """) {
                                    Self.bind($0, 1, path)
                                    Self.bind($0, 2, Self.code(kind))
                                    Self.bind($0, 3, key)
                                    Self.bind($0, 4, spelling)
                                    Self.bind($0, 5, count)
                                }
                            }
                        }
                    }
                    for task in record.contribution.tasks {
                        try Self.run(database, """
                            INSERT INTO tasks (path, line, text, checked, due, scheduled, priority)
                            VALUES (?, ?, ?, ?, ?, ?, ?)
                            """) {
                            Self.bind($0, 1, path)
                            Self.bind($0, 2, task.line)
                            Self.bind($0, 3, task.text)
                            Self.bind($0, 4, task.checked ? 1 : 0)
                            Self.bind($0, 5, task.due)
                            Self.bind($0, 6, task.scheduled)
                            Self.bind($0, 7, task.priority)
                        }
                    }
                }
            }
            start += chunk.count
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

    nonisolated private static func isTaskDate(_ value: String) -> Bool {
        JournalDay(string: value) != nil
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
