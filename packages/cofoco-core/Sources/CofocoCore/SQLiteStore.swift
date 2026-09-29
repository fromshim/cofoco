import Foundation
import SQLite3
import Darwin

enum SQLValue: Sendable, Equatable {
    case text(String)
    case integer(Int64)
    case double(Double)
    case blob(Data)
    case null
}

struct SQLRow: Sendable {
    private let values: [String: SQLValue]
    let firstValue: SQLValue

    init(_ values: [String: SQLValue], firstValue: SQLValue) {
        self.values = values
        self.firstValue = firstValue
    }

    subscript(_ name: String) -> SQLValue? { values[name] }
    func string(_ name: String) -> String {
        if case .text(let value) = values[name] { return value }
        return ""
    }
    func optionalString(_ name: String) -> String? {
        if case .text(let value) = values[name] { return value }
        return nil
    }
    func int64(_ name: String) -> Int64 {
        if case .integer(let value) = values[name] { return value }
        return 0
    }
    func bool(_ name: String) -> Bool { int64(name) != 0 }
}

/// Owns one connection. The recursive lock covers a complete transaction, including
/// calls made from its closure, so callers cannot interleave operations on that connection.
final class SQLiteStore: @unchecked Sendable {
    static let schemaVersion = 2
    let path: URL
    private(set) var preMigrationBackup: URL?

    private let mutex = NSRecursiveLock()
    private var db: OpaquePointer?
    private let lockFD: Int32
    private var inTransaction = false

    init(path: URL) throws {
        guard path.isFileURL else { throw CoreError.invalidInput }
        self.path = path.standardizedFileURL
        try FileManager.default.createDirectory(at: self.path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = self.path.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw CoreError.storage("Cannot open store lock") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw CoreError.storeLocked
        }
        lockFD = descriptor
        do {
            var connection: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(self.path.path, &connection, flags, nil) == SQLITE_OK, let connection else {
                let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open SQLite store"
                if let connection { sqlite3_close(connection) }
                throw CoreError.storage(message)
            }
            db = connection
            try executeDirect("PRAGMA busy_timeout = 5000")
            try executeDirect("PRAGMA journal_mode = WAL")
            try executeDirect("PRAGMA synchronous = FULL")
            try executeDirect("PRAGMA foreign_keys = ON")
            try migrate()
        } catch {
            if let db { sqlite3_close(db) }
            self.db = nil
            flock(descriptor, LOCK_UN)
            close(descriptor)
            throw error
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
        flock(lockFD, LOCK_UN)
        close(lockFD)
    }

    func isOwner(_ principal: Principal) -> Bool {
        if case .owner = principal { return true }
        return false
    }

    /// The owner capability is never inferred from a provider identifier or cwd.
    func authorize(_ principal: Principal, scope: Scope, write: Bool) throws -> Bool {
        if isOwner(principal) { return true }
        guard case .integration(let id) = principal, !id.isEmpty else { return false }
        let rows = try query(
            """
            SELECT 1 FROM integration_grants AS g
            JOIN grant_scopes AS s ON s.integration_id = g.integration_id
            WHERE g.integration_id = ? AND s.scope_key = ? AND g.revoked_at IS NULL
              AND g.can_read = 1 AND (? = 0 OR g.can_write = 1)
            LIMIT 1
            """,
            [.text(id), .text(scope.key), .integer(write ? 1 : 0)]
        )
        return !rows.isEmpty
    }

    @discardableResult
    func execute(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int {
        mutex.lock()
        defer { mutex.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw databaseError() }
        return Int(sqlite3_changes(db))
    }

    func query(_ sql: String, _ bindings: [SQLValue] = []) throws -> [SQLRow] {
        mutex.lock()
        defer { mutex.unlock() }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw databaseError() }
            var values: [String: SQLValue] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: values[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: values[name] = .double(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    values[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, index))
                    if let bytes = sqlite3_column_blob(statement, index) {
                        values[name] = .blob(Data(bytes: bytes, count: count))
                    } else { values[name] = .blob(Data()) }
                default: values[name] = .null
                }
            }
            let first = values[String(cString: sqlite3_column_name(statement, 0))] ?? .null
            rows.append(SQLRow(values, firstValue: first))
        }
    }

    func scalarInt(_ sql: String, _ bindings: [SQLValue] = []) throws -> Int64? {
        let row = try query(sql, bindings).first
        guard let row else { return nil }
        if case .integer(let value) = row.firstValue { return value }
        return nil
    }

    func transaction<T>(_ body: (SQLiteStore) throws -> T) throws -> T {
        mutex.lock()
        defer { mutex.unlock() }
        guard !inTransaction else { throw CoreError.storage("Nested transaction") }
        try executeDirect("BEGIN IMMEDIATE")
        inTransaction = true
        do {
            let result = try body(self)
            try executeDirect("COMMIT")
            inTransaction = false
            return result
        } catch {
            _ = try? executeDirect("ROLLBACK")
            inTransaction = false
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw databaseError()
        }
        return statement
    }

    private func bind(_ values: [SQLValue], to statement: OpaquePointer) throws {
        guard values.count == sqlite3_bind_parameter_count(statement) else { throw CoreError.invalidInput }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                result = text.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
            case .integer(let integer): result = sqlite3_bind_int64(statement, index, integer)
            case .double(let number): result = sqlite3_bind_double(statement, index, number)
            case .blob(let data):
                result = data.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient)
                }
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw databaseError() }
        }
    }

    @discardableResult
    private func executeDirect(_ sql: String) throws -> Int32 {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw databaseError() }
        return sqlite3_changes(db)
    }

    private func databaseError() -> CoreError {
        CoreError.storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite unavailable")
    }

    private func migrate() throws {
        let version = Int(try query("PRAGMA user_version").first?.int64("user_version") ?? 0)
        guard version <= Self.schemaVersion else { throw CoreError.newerSchema }
        guard version < Self.schemaVersion else { return }
        if version > 0 { preMigrationBackup = try makeConsistentBackup() }
        try transaction { store in
            if version == 0 {
                for sql in Self.initialSchema { try store.executeDirect(sql) }
            }
            if version <= 1 {
                for sql in Self.secondMigration { try store.executeDirect(sql) }
            }
            try store.executeDirect("PRAGMA user_version = 2")
        }
    }

    /// SQLite's online backup includes committed WAL pages in one snapshot.
    private func makeConsistentBackup() throws -> URL {
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = URL(fileURLWithPath: path.path + ".pre-v\(Self.schemaVersion)-\(date)-\(UUID().uuidString).sqlite")
        var target: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let target else {
            if let target { sqlite3_close(target) }
            throw CoreError.storage("Cannot open migration backup")
        }
        defer { sqlite3_close(target) }
        guard let backup = sqlite3_backup_init(target, "main", db, "main") else { throw databaseError() }
        let stepResult = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard stepResult == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw CoreError.storage("Migration backup failed")
        }
        return destination
    }

    private static let initialSchema: [String] = [
        "CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT NOT NULL, revision INTEGER NOT NULL CHECK(revision >= 1), created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
        "CREATE TABLE folder_bindings (canonical_root TEXT PRIMARY KEY, project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE RESTRICT, created_at TEXT NOT NULL)",
        "CREATE INDEX folder_bindings_project ON folder_bindings(project_id)",
        "CREATE TABLE integration_grants (integration_id TEXT PRIMARY KEY, credential_ref TEXT NOT NULL, can_read INTEGER NOT NULL CHECK(can_read IN (0,1)), can_write INTEGER NOT NULL CHECK(can_write IN (0,1)), revoked_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
        "CREATE TABLE grant_scopes (integration_id TEXT NOT NULL REFERENCES integration_grants(integration_id) ON DELETE CASCADE, scope_key TEXT NOT NULL, PRIMARY KEY(integration_id,scope_key))",
        "CREATE TABLE todos (id TEXT PRIMARY KEY, project_id TEXT REFERENCES projects(id), title TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','in_progress','done')), status_authority TEXT NOT NULL CHECK(status_authority IN ('default','agent','owner')), revision INTEGER NOT NULL CHECK(revision >= 1), order_key INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, source_json TEXT NOT NULL)",
        "CREATE INDEX todos_project ON todos(project_id, deleted_at, order_key)",
        "CREATE TABLE steps (id TEXT PRIMARY KEY, todo_id TEXT NOT NULL REFERENCES todos(id), title TEXT NOT NULL, is_done INTEGER NOT NULL CHECK(is_done IN (0,1)), order_key INTEGER NOT NULL, deleted_at TEXT, source_json TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
        "CREATE INDEX steps_todo ON steps(todo_id, order_key)",
        "CREATE TABLE notes (id TEXT PRIMARY KEY, todo_id TEXT NOT NULL REFERENCES todos(id), text TEXT NOT NULL, author_id TEXT NOT NULL, last_editor_id TEXT NOT NULL, deleted_at TEXT, source_json TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
        "CREATE INDEX notes_todo ON notes(todo_id, created_at)",
        "CREATE TABLE change_events (cursor INTEGER PRIMARY KEY AUTOINCREMENT, aggregate_type TEXT NOT NULL, aggregate_id TEXT NOT NULL, actor_id TEXT NOT NULL, source TEXT NOT NULL, operation TEXT NOT NULL, before_json TEXT, after_json TEXT, reason TEXT NOT NULL, resulting_revision INTEGER NOT NULL, feedback TEXT NOT NULL, created_at TEXT NOT NULL)",
        "CREATE INDEX change_events_aggregate ON change_events(aggregate_type, aggregate_id, cursor)",
        "CREATE TABLE operation_receipts (actor_id TEXT NOT NULL, key TEXT NOT NULL, fingerprint TEXT NOT NULL, result_json TEXT NOT NULL, access_json TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(actor_id,key))",
        "CREATE TABLE change_proposals (id TEXT PRIMARY KEY, actor_id TEXT NOT NULL, payload_json TEXT NOT NULL, preview_json TEXT NOT NULL, reason TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('pending','accepted','rejected','stale')), created_at TEXT NOT NULL, reviewed_at TEXT, reviewer_id TEXT, result_json TEXT)",
        "CREATE TABLE proposal_targets (proposal_id TEXT NOT NULL REFERENCES change_proposals(id), todo_id TEXT NOT NULL, expected_revision INTEGER NOT NULL, PRIMARY KEY(proposal_id,todo_id))",
    ]

    private static let secondMigration: [String] = [
        "CREATE TABLE notification_deliveries (event_cursor INTEGER NOT NULL REFERENCES change_events(cursor), channel TEXT NOT NULL, delivery_state TEXT NOT NULL, coalescing_ref TEXT, updated_at TEXT NOT NULL, PRIMARY KEY(event_cursor,channel))",
    ]
}
