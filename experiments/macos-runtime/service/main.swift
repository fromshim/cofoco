import Darwin
import Foundation
import SQLite3

// A disposable runtime spike, deliberately not the Cofoco application service.
private let protocolVersion = 1
private let schemaVersion = 2
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private var shouldStop: sig_atomic_t = 0

private func stopSignal(_ signal: Int32) -> Void { shouldStop = 1 }

private enum SpikeError: Error, CustomStringConvertible {
    case message(String)
    var description: String { if case .message(let value) = self { return value }; return "unknown" }
}

private func fail(_ message: String) -> Never {
    fputs("service spike: \(message)\n", stderr)
    exit(1)
}

private func jsonLine(_ value: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(data: data, encoding: .utf8)!
}

private final class Store {
    private var db: OpaquePointer?
    private let path: String

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("cofoco-spike.sqlite").path
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            throw SpikeError.message("sqlite open failed")
        }
        do {
            try exec("PRAGMA foreign_keys=ON")
            try exec("PRAGMA busy_timeout=2000")
            try exec("PRAGMA journal_mode=WAL")
            try exec("PRAGMA synchronous=FULL")
            try exec("PRAGMA trusted_schema=OFF")
            try migrate(directory: directory)
        } catch {
            sqlite3_close(db)
            db = nil
            throw error
        }
    }

    deinit { if db != nil { sqlite3_close(db) } }

    private func exec(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw SpikeError.message("sqlite \(result): \(String(cString: sqlite3_errmsg(db)))") }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SpikeError.message("prepare: \(String(cString: sqlite3_errmsg(db)))")
        }
        return stmt
    }

    private func scalar(_ sql: String) throws -> Int64 {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw SpikeError.message("scalar query failed") }
        return sqlite3_column_int64(stmt, 0)
    }

    private func backup(to destination: URL) throws {
        var target: OpaquePointer?
        guard sqlite3_open_v2(destination.path, &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw SpikeError.message("backup destination open failed")
        }
        defer { sqlite3_close(target) }
        guard let job = sqlite3_backup_init(target, "main", db, "main") else {
            throw SpikeError.message("backup init failed")
        }
        let result = sqlite3_backup_step(job, -1)
        let finish = sqlite3_backup_finish(job)
        guard result == SQLITE_DONE && finish == SQLITE_OK else { throw SpikeError.message("backup failed") }
    }

    private func migrate(directory: URL) throws {
        let current = Int(try scalar("PRAGMA user_version"))
        guard current <= schemaVersion else { throw SpikeError.message("newer schema \(current) refused") }
        if current == 1 {
            // Online backup includes committed WAL content; a plain DB-file copy would not.
            try backup(to: directory.appendingPathComponent("pre-v2.sqlite"))
        }
        if current < 1 {
            try exec("BEGIN IMMEDIATE")
            do {
                try exec("CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN ('open','in_progress','done')), revision INTEGER NOT NULL)")
                try exec("CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, todo_id TEXT NOT NULL, kind TEXT NOT NULL, actor TEXT NOT NULL, reason TEXT NOT NULL, revision INTEGER NOT NULL)")
                try exec("CREATE TABLE receipts (actor TEXT NOT NULL, request_key TEXT NOT NULL, fingerprint TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(actor, request_key))")
                try exec("PRAGMA user_version=1")
                try exec("COMMIT")
            } catch { try? exec("ROLLBACK"); throw error }
        }
        if current < 2 {
            try exec("BEGIN IMMEDIATE")
            do {
                try exec("CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                try exec("INSERT INTO schema_meta(key,value) VALUES('spike','2')")
                try exec("PRAGMA user_version=2")
                try exec("COMMIT")
            } catch { try? exec("ROLLBACK"); throw error }
        }
    }

    private func bind(_ values: [String], to stmt: OpaquePointer) {
        for (index, value) in values.enumerated() {
            _ = value.withCString { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, transient) }
        }
    }

    private func run(_ sql: String, _ values: [String] = []) throws {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        bind(values, to: stmt)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw SpikeError.message("write: \(String(cString: sqlite3_errmsg(db)))") }
    }

    private func textValue(_ sql: String, _ values: [String] = []) throws -> String? {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        bind(values, to: stmt)
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else { throw SpikeError.message("read failed") }
        return String(cString: value)
    }

    func createFixture() throws {
        try run("INSERT INTO todos(id,title,status,revision) VALUES('todo-1','fixture','open',1)")
    }

    func mutate(actor: String, key: String, status: String, expected: Int, injectFailure: Bool = false) throws -> String {
        let fingerprint = "todo-1|\(status)|\(expected)"
        try exec("BEGIN IMMEDIATE")
        do {
            if let stored = try textValue("SELECT fingerprint FROM receipts WHERE actor=? AND request_key=?", [actor, key]) {
                guard stored == fingerprint else { throw SpikeError.message("idempotency_mismatch") }
                let result = try textValue("SELECT result FROM receipts WHERE actor=? AND request_key=?", [actor, key])!
                try exec("COMMIT")
                return result
            }
            guard let revisionText = try textValue("SELECT CAST(revision AS TEXT) FROM todos WHERE id='todo-1'"),
                  let revision = Int(revisionText) else { throw SpikeError.message("not_found") }
            guard revision == expected else { throw SpikeError.message("conflict") }
            let old = try textValue("SELECT status FROM todos WHERE id='todo-1'")!
            let outcome: String
            if old == status {
                outcome = "noop|\(revision)"
            } else {
                try run("UPDATE todos SET status=?, revision=revision+1 WHERE id='todo-1' AND revision=?", [status, String(expected)])
                guard sqlite3_changes(db) == 1 else { throw SpikeError.message("conflict") }
                if injectFailure { throw SpikeError.message("injected_after_state") }
                try run("INSERT INTO events(todo_id,kind,actor,reason,revision) VALUES('todo-1','status',?,'self-test',?)", [actor, String(revision + 1)])
                outcome = "updated|\(revision + 1)"
            }
            try run("INSERT INTO receipts(actor,request_key,fingerprint,result) VALUES(?,?,?,?)", [actor, key, fingerprint, outcome])
            try exec("COMMIT")
            return outcome
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    func counts() throws -> (revision: Int, events: Int, receipts: Int, status: String) {
        (Int(try scalar("SELECT revision FROM todos WHERE id='todo-1'")),
         Int(try scalar("SELECT count(*) FROM events")),
         Int(try scalar("SELECT count(*) FROM receipts")),
         try textValue("SELECT status FROM todos WHERE id='todo-1'")!)
    }

    func version() throws -> Int { Int(try scalar("PRAGMA user_version")) }
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ label: String) throws {
    if try !condition() { throw SpikeError.message("assertion failed: \(label)") }
}

private func rawDatabase(at path: String, statements: String) throws -> OpaquePointer {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
        throw SpikeError.message("raw database open failed")
    }
    guard sqlite3_exec(db, statements, nil, nil, nil) == SQLITE_OK else {
        let message = String(cString: sqlite3_errmsg(db))
        sqlite3_close(db)
        throw SpikeError.message("raw database setup: \(message)")
    }
    return db!
}

private func rawScalar(_ db: OpaquePointer, _ sql: String) throws -> Int {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw SpikeError.message("raw prepare failed") }
    defer { sqlite3_finalize(stmt) }
    guard sqlite3_step(stmt) == SQLITE_ROW else { throw SpikeError.message("raw query failed \(sql): \(String(cString: sqlite3_errmsg(db)))") }
    return Int(sqlite3_column_int(stmt, 0))
}

private func selfTest() throws {
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("cofoco-service-spike-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixture) }
    do {
        let store = try Store(directory: fixture)
        try expect(try store.version() == 2, "schema version")
        try store.createFixture()
        try expect(try store.mutate(actor: "agent", key: "one", status: "in_progress", expected: 1) == "updated|2", "initial mutation")
        try expect(try store.mutate(actor: "agent", key: "one", status: "in_progress", expected: 1) == "updated|2", "retry receipt")
        do { _ = try store.mutate(actor: "agent", key: "one", status: "done", expected: 2); throw SpikeError.message("mismatch unexpectedly succeeded") }
        catch let error as SpikeError { try expect(error.description == "idempotency_mismatch", "key mismatch") }
        do { _ = try store.mutate(actor: "other", key: "stale", status: "done", expected: 1); throw SpikeError.message("stale unexpectedly succeeded") }
        catch let error as SpikeError { try expect(error.description == "conflict", "stale revision") }
        do { _ = try store.mutate(actor: "agent", key: "rollback", status: "done", expected: 2, injectFailure: true); throw SpikeError.message("injection unexpectedly succeeded") }
        catch let error as SpikeError { try expect(error.description == "injected_after_state", "injected failure") }
        let afterRollback = try store.counts()
        try expect(afterRollback.revision == 2 && afterRollback.events == 1 && afterRollback.receipts == 1 && afterRollback.status == "in_progress", "atomic rollback")
        try expect(try store.mutate(actor: "agent", key: "noop", status: "in_progress", expected: 2) == "noop|2", "noop")
        let afterNoop = try store.counts()
        try expect(afterNoop.revision == 2 && afterNoop.events == 1 && afterNoop.receipts == 2, "noop event count")
    }
    let reopened = try Store(directory: fixture)
    let state = try reopened.counts()
    try expect(state.revision == 2 && state.events == 1 && state.receipts == 2 && state.status == "in_progress", "restart durability")
    try expect(try reopened.mutate(actor: "agent", key: "one", status: "in_progress", expected: 1) == "updated|2", "restart receipt replay")

    let legacyDirectory = fixture.appendingPathComponent("legacy")
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    let legacyPath = legacyDirectory.appendingPathComponent("cofoco-spike.sqlite").path
    let legacy = try rawDatabase(at: legacyPath, statements: """
        PRAGMA journal_mode=WAL;
        CREATE TABLE todos (id TEXT PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL, revision INTEGER NOT NULL);
        CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, todo_id TEXT NOT NULL, kind TEXT NOT NULL, actor TEXT NOT NULL, reason TEXT NOT NULL, revision INTEGER NOT NULL);
        CREATE TABLE receipts (actor TEXT NOT NULL, request_key TEXT NOT NULL, fingerprint TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(actor,request_key));
        PRAGMA user_version=1;
        INSERT INTO todos VALUES('todo-1','legacy','open',1);
        """)
    defer { sqlite3_close(legacy) }
    let migrated = try Store(directory: legacyDirectory)
    try expect(try migrated.version() == 2, "v1 migration")
    try expect(try migrated.counts().revision == 1, "migrated content")
    let backupPath = legacyDirectory.appendingPathComponent("pre-v2.sqlite").path
    var backup: OpaquePointer?
    guard sqlite3_open_v2(backupPath, &backup, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let backup else { throw SpikeError.message("backup absent") }
    defer { sqlite3_close(backup) }
    try expect(try rawScalar(backup, "PRAGMA user_version") == 1, "pre-migration backup version")
    try expect(try rawScalar(backup, "SELECT count(*) FROM todos WHERE id='todo-1'") == 1, "WAL backup content")

    let futureDirectory = fixture.appendingPathComponent("future")
    try FileManager.default.createDirectory(at: futureDirectory, withIntermediateDirectories: true)
    let future = try rawDatabase(at: futureDirectory.appendingPathComponent("cofoco-spike.sqlite").path, statements: "PRAGMA user_version=99;")
    sqlite3_close(future)
    do { _ = try Store(directory: futureDirectory); throw SpikeError.message("future schema unexpectedly opened") }
    catch let error as SpikeError { try expect(error.description == "newer schema 99 refused", "future schema refusal") }

    print(jsonLine(["status": "passed", "schema_version": schemaVersion, "revision": state.revision, "events": state.events, "receipts": state.receipts, "migration_backup": "passed", "future_schema_refused": true, "sqlite_version": String(cString: sqlite3_libversion())]))
}

private final class Lock {
    private let fd: Int32
    init(directory: URL) throws {
        let path = directory.appendingPathComponent("service.lock").path
        fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SpikeError.message("lock file open failed") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw SpikeError.message("already_running")
        }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}

private func serve(dataDirectory: URL, parentPID: Int32?) throws {
    try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    let lock = try Lock(directory: dataDirectory)
    let store = try Store(directory: dataDirectory)
    defer { withExtendedLifetime(lock) {}; withExtendedLifetime(store) {} }
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    guard listener >= 0 else { throw SpikeError.message("socket failed") }
    defer { close(listener) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard bindResult == 0 else { throw SpikeError.message("bind failed errno=\(errno)") }
    guard listen(listener, 8) == 0 else { throw SpikeError.message("listen failed errno=\(errno)") }
    var bound = sockaddr_in()
    var boundSize = socklen_t(MemoryLayout<sockaddr_in>.size)
    let boundResult = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &boundSize) }
    }
    guard boundResult == 0 else { throw SpikeError.message("getsockname failed") }
    let port = Int(UInt16(bigEndian: bound.sin_port))
    let token = UUID().uuidString
    signal(SIGTERM, stopSignal)
    signal(SIGINT, stopSignal)
    signal(SIGPIPE, SIG_IGN)
    print(jsonLine(["status": "ready", "protocol_version": protocolVersion, "port": port, "token": token, "pid": Int(getpid())]))
    fflush(stdout)
    while shouldStop == 0 {
        if let parentPID, (kill(parentPID, 0) != 0 && errno == ESRCH) || getppid() != parentPID { break }
        var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, 1000)
        if ready <= 0 { continue }
        let client = accept(listener, nil, nil)
        if client < 0 { continue }
        var noSigPipe: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var readTimeout = timeval(tv_sec: 2, tv_usec: 0)
        _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
        var bytes = [UInt8](repeating: 0, count: 4097)
        let count = recv(client, &bytes, 4097, 0)
        let request = count > 0 && count <= 4096 ? String(bytes: bytes[0..<Int(count)], encoding: .utf8) : nil
        let lines = request?.components(separatedBy: "\r\n") ?? []
        let host = lines.first { $0.lowercased().hasPrefix("host:") }?.dropFirst(5).trimmingCharacters(in: .whitespaces)
        let origin = lines.first { $0.lowercased().hasPrefix("origin:") }?.dropFirst(7).trimmingCharacters(in: .whitespaces)
        let authorization = lines.first { $0.lowercased().hasPrefix("authorization:") }?.dropFirst(14).trimmingCharacters(in: .whitespaces)
        let permitted = lines.first == "GET /health HTTP/1.1" && host == "127.0.0.1:\(port)" && (origin == nil || origin == "http://127.0.0.1:\(port)") && authorization == "Bearer \(token)" && request?.contains("\r\n\r\n") == true
        let body = permitted ? jsonLine(["status": "ok", "protocol_version": protocolVersion]) : jsonLine(["error": "forbidden"])
        let response = "HTTP/1.1 \(permitted ? "200 OK" : "403 Forbidden")\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { send(client, $0, response.utf8.count, 0) }
        close(client)
    }
}

@main private struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--self-test") {
            do { try selfTest() } catch { fail("self-test: \(error)") }
            return
        }
        guard let index = args.firstIndex(of: "--data-dir"), index + 1 < args.count else { fail("usage: --self-test OR --data-dir PATH [--parent-pid PID]") }
        let parent: Int32?
        if let p = args.firstIndex(of: "--parent-pid") {
            guard p + 1 < args.count, let parsed = Int32(args[p + 1]), parsed > 1 else { fail("invalid parent pid") }
            parent = parsed
        } else { parent = nil }
        do { try serve(dataDirectory: URL(fileURLWithPath: args[index + 1], isDirectory: true), parentPID: parent) }
        catch { fail("\(error)") }
    }
}
