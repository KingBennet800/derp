import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A small SQLite database: bind, step, read.
final class Database {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(path: String) {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            NSLog("Derp: couldn't open the database")
        }
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    func run(_ sql: String, _ args: [Any?] = []) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let statement = prepare(sql, args) else { return false }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        return result == SQLITE_DONE || result == SQLITE_ROW
    }

    func rows(_ sql: String, _ args: [Any?] = []) -> [[Any?]] {
        lock.lock(); defer { lock.unlock() }
        guard let statement = prepare(sql, args) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [Any?] = []
            for i in 0..<sqlite3_column_count(statement) {
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: row.append(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT: row.append(sqlite3_column_double(statement, i))
                case SQLITE_NULL: row.append(nil)
                default: row.append(sqlite3_column_text(statement, i).map { String(cString: $0) })
                }
            }
            rows.append(row)
        }
        return rows
    }

    var changes: Int { Int(sqlite3_changes(db)) }

    func transaction(_ body: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        run("BEGIN")
        body()
        run("COMMIT")
    }

    private func prepare(_ sql: String, _ args: [Any?]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            NSLog("Derp: SQL error: %@", String(cString: sqlite3_errmsg(db)))
            return nil
        }
        for (i, arg) in args.enumerated() {
            let index = Int32(i + 1)
            switch arg {
            case let value as Int64: sqlite3_bind_int64(statement, index, value)
            case let value as Int: sqlite3_bind_int64(statement, index, Int64(value))
            case let value as Double: sqlite3_bind_double(statement, index, value)
            case let value as String: sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            default: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }
}

func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

/// Your bookmarks and history (and the passwords list Logins keeps), in one
/// database on this device. Nothing here leaves it. The same tables as Derp
/// for Android's (Library.kt).
final class Library {
    let db: Database
    private var visits = 0

    init(directory: URL) {
        db = Database(path: directory.appendingPathComponent("derp.db").path)
        db.run("CREATE TABLE IF NOT EXISTS bookmarks (url TEXT PRIMARY KEY, title TEXT NOT NULL DEFAULT '', added INTEGER NOT NULL)")
        db.run("CREATE TABLE IF NOT EXISTS history (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL, title TEXT NOT NULL DEFAULT '', visited INTEGER NOT NULL)")
        db.run("CREATE INDEX IF NOT EXISTS history_url ON history (url)")
        db.run("CREATE INDEX IF NOT EXISTS history_visited ON history (visited)")
        db.run("CREATE TABLE IF NOT EXISTS logins (guid TEXT PRIMARY KEY, origin TEXT NOT NULL, form_action TEXT, realm TEXT, username TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, used INTEGER NOT NULL)")
    }

    // ── Bookmarks ──────────────────────────────────────────────────────────

    func isBookmarked(_ url: String) -> Bool {
        !db.rows("SELECT 1 FROM bookmarks WHERE url = ?", [url]).isEmpty
    }

    func bookmark(_ url: String, title: String) {
        db.run("INSERT OR REPLACE INTO bookmarks (url, title, added) VALUES (?, ?, ?)", [url, title, now()])
    }

    func unbookmark(_ url: String) {
        db.run("DELETE FROM bookmarks WHERE url = ?", [url])
    }

    func retitle(_ url: String, title: String) {
        db.run("UPDATE bookmarks SET title = ? WHERE url = ?", [title, url])
    }

    /// Every bookmark, address to title, oldest first (for syncing).
    func allBookmarks() -> [(String, String)] {
        db.rows("SELECT url, title FROM bookmarks ORDER BY added").map { ($0[0] as? String ?? "", $0[1] as? String ?? "") }
    }

    /// Newest first, optionally only those matching [query].
    func bookmarks(query: String = "", limit: Int = 500) -> [[String: Any]] {
        let (clause, args) = matching(query)
        return db.rows("SELECT url, title, added FROM bookmarks \(clause) ORDER BY added DESC LIMIT \(limit)", args).map {
            ["url": $0[0] as? String ?? "", "title": $0[1] as? String ?? "", "added": $0[2] as? Int64 ?? 0]
        }
    }

    /// Adds the ones you don't have yet; returns how many that was.
    func importBookmarks(_ marks: [Imports.Bookmark]) -> Int {
        var added = 0
        let start = now()
        db.transaction {
            // Oldest first, so the file's first bookmark ends up on top.
            for (i, mark) in marks.reversed().enumerated() {
                db.run("INSERT OR IGNORE INTO bookmarks (url, title, added) VALUES (?, ?, ?)", [mark.url, mark.title, start + Int64(i)])
                added += db.changes
            }
        }
        return added
    }

    // ── History ────────────────────────────────────────────────────────────

    /// A page you went to. Coming back to the same page within half an hour
    /// (a reload, say) moves its visit instead of adding another.
    func visit(_ url: String) {
        let time = now()
        if let recent = db.rows("SELECT id FROM history WHERE url = ? AND visited > ? ORDER BY visited DESC LIMIT 1", [url, time - 30 * 60_000]).first?[0] as? Int64 {
            db.run("UPDATE history SET visited = ? WHERE id = ?", [time, recent])
        } else {
            db.run("INSERT INTO history (url, visited) VALUES (?, ?)", [url, time])
            visits += 1
            if visits % 100 == 0 {
                // Keeps the last 180 days, at most 20,000 visits.
                db.run("DELETE FROM history WHERE visited < ?", [time - 180 * 86_400_000])
                db.run("DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited DESC LIMIT 20000)")
            }
        }
    }

    /// The page's title, once it has one, for its latest visit.
    func title(_ url: String, title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        db.run("UPDATE history SET title = ? WHERE id = (SELECT id FROM history WHERE url = ? ORDER BY visited DESC LIMIT 1)", [title, url])
    }

    /// Newest first, older than [before] (for paging), optionally matching [query].
    func history(query: String = "", before: Int64 = Int64.max, limit: Int = 200) -> [[String: Any]] {
        let (clause, args) = matching(query)
        let where_ = clause.isEmpty ? "WHERE visited < ?" : "\(clause) AND visited < ?"
        return db.rows("SELECT url, title, visited FROM history \(where_) ORDER BY visited DESC LIMIT \(limit)", args + [before as Any?]).map {
            ["url": $0[0] as? String ?? "", "title": $0[1] as? String ?? "", "visited": $0[2] as? Int64 ?? 0]
        }
    }

    func forget(_ url: String) {
        db.run("DELETE FROM history WHERE url = ?", [url])
    }

    func clearHistory() {
        db.run("DELETE FROM history")
    }

    /// Recent pages and bookmarks matching what you type in the address bar.
    func suggestions(_ text: String, limit: Int = 6) -> [(url: String, title: String)] {
        let (clause, args) = matching(text)
        guard !clause.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [(url: String, title: String)] = []
        let marks = db.rows("SELECT url, title FROM bookmarks \(clause) ORDER BY added DESC LIMIT \(limit)", args)
        let pages = db.rows("SELECT url, MAX(title), MAX(visited) AS last FROM history \(clause) GROUP BY url ORDER BY COUNT(*) DESC, last DESC LIMIT \(limit * 2)", args)
        for row in marks + pages {
            guard let url = row[0] as? String, !seen.contains(url) else { continue }
            seen.insert(url)
            out.append((url: url, title: row[1] as? String ?? ""))
            if out.count == limit { break }
        }
        return out
    }

    func count(_ table: String) -> Int {
        (db.rows("SELECT COUNT(*) FROM \(table)").first?[0] as? Int64).map { Int($0) } ?? 0
    }

    /// A WHERE clause matching [query] in the title or address.
    private func matching(_ query: String) -> (String, [Any?]) {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ("", []) }
        let like = "%" + q.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        return ("WHERE (title LIKE ? ESCAPE '\\' OR url LIKE ? ESCAPE '\\')", [like, like])
    }
}
