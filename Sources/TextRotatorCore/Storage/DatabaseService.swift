import Foundation
import SQLite3

public enum DatabaseError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case notFound(String)
    case invalidData(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Database connection failed: \(msg)"
        case .executionFailed(let msg): return "Database execution failed: \(msg)"
        case .prepareFailed(let msg): return "Database prepare failed: \(msg)"
        case .stepFailed(let msg): return "Database step failed: \(msg)"
        case .notFound(let msg): return "Not found: \(msg)"
        case .invalidData(let msg): return "Invalid data: \(msg)"
        }
    }
}

public protocol DatabaseServiceProtocol: Sendable {
    // Folders
    func listFolders() throws -> [FolderSummary]
    func listFoldersWithSnippets() throws -> [FolderWithSnippets]
    func createFolder(name: String) throws -> FolderSummary
    func updateFolder(id: Int64, name: String) throws
    func deleteFolder(id: Int64) throws
    func reorderFolders(order: [Int64]) throws

    // Snippets
    func listSnippets(folderId: Int64) throws -> [SnippetItem]
    func createSnippet(folderId: Int64, content: String) throws -> SnippetItem
    func updateSnippet(id: Int64, content: String) throws
    func deleteSnippet(id: Int64) throws
    func moveSnippet(id: Int64, targetFolderId: Int64) throws
    func reorderSnippets(folderId: Int64, order: [Int64]) throws
    func searchSnippets(query: String, limit: Int) throws -> [SnippetSearchResult]

    // Settings
    func getSetting(key: String) throws -> String?
    func setSetting(key: String, value: String) throws
}

public final class DatabaseService: DatabaseServiceProtocol, @unchecked Sendable {
    private let db: OpaquePointer
    private let lock = NSLock()

    public init(path: String = DatabaseService.defaultDatabasePath()) throws {
        var dbPointer: OpaquePointer?

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX

        if path != ":memory:" {
            let directory = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        }

        let rc = sqlite3_open_v2(path, &dbPointer, flags, nil)
        guard rc == SQLITE_OK, let validDb = dbPointer else {
            let errMsg = dbPointer != nil ? String(cString: sqlite3_errmsg(dbPointer)) : "Unknown SQLite error"
            if let dbPointer {
                sqlite3_close(dbPointer)
            }
            throw DatabaseError.connectionFailed(errMsg)
        }

        self.db = validDb

        try initializeDatabase()
    }

    deinit {
        sqlite3_close(db)
    }

    public static func inMemory() throws -> DatabaseService {
        try DatabaseService(path: ":memory:")
    }

    public static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("TextRotator", isDirectory: true)
        return directory.appendingPathComponent("text_rotator.sqlite3").path
    }

    // MARK: - Schema Initialization

    private func initializeDatabase() throws {
        lock.lock()
        defer { lock.unlock() }

        let schemaSQL = """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;

        CREATE TABLE IF NOT EXISTS folders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            position INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS snippets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
            content TEXT NOT NULL,
            position INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS snippets_fts USING fts5(
            content,
            content='snippets',
            content_rowid='id'
        );

        CREATE TRIGGER IF NOT EXISTS snippets_ai AFTER INSERT ON snippets BEGIN
            INSERT INTO snippets_fts(rowid, content) VALUES(new.id, new.content);
        END;

        CREATE TRIGGER IF NOT EXISTS snippets_ad AFTER DELETE ON snippets BEGIN
            INSERT INTO snippets_fts(snippets_fts, rowid, content) VALUES('delete', old.id, old.content);
        END;

        CREATE TRIGGER IF NOT EXISTS snippets_au AFTER UPDATE ON snippets BEGIN
            INSERT INTO snippets_fts(snippets_fts, rowid, content) VALUES('delete', old.id, old.content);
            INSERT INTO snippets_fts(rowid, content) VALUES(new.id, new.content);
        END;

        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_folders_position ON folders(position);
        CREATE INDEX IF NOT EXISTS idx_snippets_folder_position ON snippets(folder_id, position);
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, schemaSQL, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.flatMap { String(cString: $0) } ?? "Unknown error during schema migration"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(error)
        }
    }

    // MARK: - Folders CRUD

    public func listFolders() throws -> [FolderSummary] {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        SELECT f.id, f.name, f.position, COUNT(s.id) AS snippet_count
        FROM folders f
        LEFT JOIN snippets s ON f.id = s.folder_id
        GROUP BY f.id
        ORDER BY f.position ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(statement) }

        var result: [FolderSummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let name = String(cString: sqlite3_column_text(statement, 1))
            let position = sqlite3_column_int64(statement, 2)
            let count = sqlite3_column_int64(statement, 3)
            result.append(FolderSummary(id: id, name: name, position: position, snippetCount: count))
        }
        return result
    }

    public func listFoldersWithSnippets() throws -> [FolderWithSnippets] {
        lock.lock()
        defer { lock.unlock() }

        let foldersSQL = "SELECT id, name, position FROM folders ORDER BY position ASC;"
        var folderStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, foldersSQL, -1, &folderStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(folderStmt) }

        var folders: [FolderWithSnippets] = []
        while sqlite3_step(folderStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(folderStmt, 0)
            let name = String(cString: sqlite3_column_text(folderStmt, 1))
            let position = sqlite3_column_int64(folderStmt, 2)
            folders.append(FolderWithSnippets(id: id, name: name, position: position, snippets: []))
        }

        let snippetsSQL = "SELECT id, folder_id, content, position, created_at FROM snippets ORDER BY position ASC;"
        var snippetStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, snippetsSQL, -1, &snippetStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(snippetStmt) }

        var snippetsByFolder: [Int64: [SnippetItem]] = [:]
        while sqlite3_step(snippetStmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(snippetStmt, 0)
            let folderId = sqlite3_column_int64(snippetStmt, 1)
            let content = String(cString: sqlite3_column_text(snippetStmt, 2))
            let position = sqlite3_column_int64(snippetStmt, 3)
            let createdAtStr: String?
            if let text = sqlite3_column_text(snippetStmt, 4) {
                createdAtStr = String(cString: text)
            } else {
                createdAtStr = nil
            }
            let snippet = SnippetItem(id: id, folderId: folderId, content: content, position: position, createdAt: createdAtStr)
            snippetsByFolder[folderId, default: []].append(snippet)
        }

        return folders.map { folder in
            FolderWithSnippets(
                id: folder.id,
                name: folder.name,
                position: folder.position,
                snippets: snippetsByFolder[folder.id] ?? []
            )
        }
    }

    public func createFolder(name: String) throws -> FolderSummary {
        lock.lock()
        defer { lock.unlock() }

        let posSQL = "SELECT COALESCE(MAX(position), -1) + 1 FROM folders;"
        var posStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, posSQL, -1, &posStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(posStmt) }

        var nextPosition: Int64 = 0
        if sqlite3_step(posStmt) == SQLITE_ROW {
            nextPosition = sqlite3_column_int64(posStmt, 0)
        }

        let insertSQL = "INSERT INTO folders (name, position) VALUES (?, ?);"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(insertStmt) }

        sqlite3_bind_text(insertStmt, 1, NSString(string: name).utf8String, -1, nil)
        sqlite3_bind_int64(insertStmt, 2, nextPosition)

        guard sqlite3_step(insertStmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        let newId = sqlite3_last_insert_rowid(db)
        return FolderSummary(id: newId, name: name, position: nextPosition, snippetCount: 0)
    }

    public func updateFolder(id: Int64, name: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "UPDATE folders SET name = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, NSString(string: name).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        if sqlite3_changes(db) == 0 {
            throw DatabaseError.notFound("Folder with id \(id) not found")
        }
    }

    public func deleteFolder(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM folders WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        if sqlite3_changes(db) == 0 {
            throw DatabaseError.notFound("Folder with id \(id) not found")
        }
    }

    public func reorderFolders(order: [Int64]) throws {
        lock.lock()
        defer { lock.unlock() }

        try executeRaw("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let sql = "UPDATE folders SET position = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            for (index, id) in order.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(index))
                sqlite3_bind_int64(stmt, 2, id)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(lastErrorMessage())
                }
            }

            try executeRaw("COMMIT;")
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Snippets CRUD

    public func listSnippets(folderId: Int64) throws -> [SnippetItem] {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT id, folder_id, content, position, created_at FROM snippets WHERE folder_id = ? ORDER BY position ASC;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, folderId)

        var result: [SnippetItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let folderId = sqlite3_column_int64(stmt, 1)
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let position = sqlite3_column_int64(stmt, 3)
            let createdAtStr: String?
            if let text = sqlite3_column_text(stmt, 4) {
                createdAtStr = String(cString: text)
            } else {
                createdAtStr = nil
            }
            result.append(SnippetItem(id: id, folderId: folderId, content: content, position: position, createdAt: createdAtStr))
        }
        return result
    }

    public func createSnippet(folderId: Int64, content: String) throws -> SnippetItem {
        lock.lock()
        defer { lock.unlock() }

        // Verify folder exists
        let checkSQL = "SELECT id FROM folders WHERE id = ?;"
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        sqlite3_bind_int64(checkStmt, 1, folderId)
        let folderExists = (sqlite3_step(checkStmt) == SQLITE_ROW)
        sqlite3_finalize(checkStmt)
        guard folderExists else {
            throw DatabaseError.notFound("Folder with id \(folderId) not found")
        }

        let posSQL = "SELECT COALESCE(MAX(position), -1) + 1 FROM snippets WHERE folder_id = ?;"
        var posStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, posSQL, -1, &posStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(posStmt) }
        sqlite3_bind_int64(posStmt, 1, folderId)

        var nextPosition: Int64 = 0
        if sqlite3_step(posStmt) == SQLITE_ROW {
            nextPosition = sqlite3_column_int64(posStmt, 0)
        }

        let insertSQL = "INSERT INTO snippets (folder_id, content, position) VALUES (?, ?, ?);"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(insertStmt) }

        sqlite3_bind_int64(insertStmt, 1, folderId)
        sqlite3_bind_text(insertStmt, 2, NSString(string: content).utf8String, -1, nil)
        sqlite3_bind_int64(insertStmt, 3, nextPosition)

        guard sqlite3_step(insertStmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        let newId = sqlite3_last_insert_rowid(db)

        // Fetch created_at timestamp
        var createdAtStr: String?
        let fetchSQL = "SELECT created_at FROM snippets WHERE id = ?;"
        var fetchStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, fetchSQL, -1, &fetchStmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(fetchStmt, 1, newId)
            if sqlite3_step(fetchStmt) == SQLITE_ROW, let text = sqlite3_column_text(fetchStmt, 0) {
                createdAtStr = String(cString: text)
            }
            sqlite3_finalize(fetchStmt)
        }

        return SnippetItem(id: newId, folderId: folderId, content: content, position: nextPosition, createdAt: createdAtStr)
    }

    public func updateSnippet(id: Int64, content: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "UPDATE snippets SET content = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, NSString(string: content).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 2, id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        if sqlite3_changes(db) == 0 {
            throw DatabaseError.notFound("Snippet with id \(id) not found")
        }
    }

    public func deleteSnippet(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "DELETE FROM snippets WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, id)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }

        if sqlite3_changes(db) == 0 {
            throw DatabaseError.notFound("Snippet with id \(id) not found")
        }
    }

    public func moveSnippet(id: Int64, targetFolderId: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        try executeRaw("BEGIN IMMEDIATE TRANSACTION;")
        do {
            // Check target folder exists
            let checkSQL = "SELECT id FROM folders WHERE id = ?;"
            var checkStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, checkSQL, -1, &checkStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage())
            }
            sqlite3_bind_int64(checkStmt, 1, targetFolderId)
            let folderExists = (sqlite3_step(checkStmt) == SQLITE_ROW)
            sqlite3_finalize(checkStmt)
            guard folderExists else {
                throw DatabaseError.notFound("Target folder with id \(targetFolderId) not found")
            }

            // Get next position in target folder
            let posSQL = "SELECT COALESCE(MAX(position), -1) + 1 FROM snippets WHERE folder_id = ?;"
            var posStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, posSQL, -1, &posStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage())
            }
            sqlite3_bind_int64(posStmt, 1, targetFolderId)
            var nextPosition: Int64 = 0
            if sqlite3_step(posStmt) == SQLITE_ROW {
                nextPosition = sqlite3_column_int64(posStmt, 0)
            }
            sqlite3_finalize(posStmt)

            // Update snippet
            let updateSQL = "UPDATE snippets SET folder_id = ?, position = ? WHERE id = ?;"
            var updateStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(updateStmt) }

            sqlite3_bind_int64(updateStmt, 1, targetFolderId)
            sqlite3_bind_int64(updateStmt, 2, nextPosition)
            sqlite3_bind_int64(updateStmt, 3, id)

            guard sqlite3_step(updateStmt) == SQLITE_DONE else {
                throw DatabaseError.stepFailed(lastErrorMessage())
            }

            if sqlite3_changes(db) == 0 {
                throw DatabaseError.notFound("Snippet with id \(id) not found")
            }

            try executeRaw("COMMIT;")
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    public func reorderSnippets(folderId: Int64, order: [Int64]) throws {
        lock.lock()
        defer { lock.unlock() }

        try executeRaw("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let sql = "UPDATE snippets SET position = ? WHERE id = ? AND folder_id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw DatabaseError.prepareFailed(lastErrorMessage())
            }
            defer { sqlite3_finalize(stmt) }

            for (index, id) in order.enumerated() {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                sqlite3_bind_int64(stmt, 1, Int64(index))
                sqlite3_bind_int64(stmt, 2, id)
                sqlite3_bind_int64(stmt, 3, folderId)

                guard sqlite3_step(stmt) == SQLITE_DONE else {
                    throw DatabaseError.stepFailed(lastErrorMessage())
                }
            }

            try executeRaw("COMMIT;")
        } catch {
            try? executeRaw("ROLLBACK;")
            throw error
        }
    }

    public func searchSnippets(query: String, limit: Int = 50) throws -> [SnippetSearchResult] {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        var results: [SnippetSearchResult] = []
        var seenIds = Set<Int64>()

        // 1. Try FTS5 MATCH first
        let sanitizedFTSQuery = sanitizeFTS5Query(trimmed)
        if !sanitizedFTSQuery.isEmpty {
            if let ftsResults = try? performFTSSearch(query: sanitizedFTSQuery, limit: limit) {
                for item in ftsResults {
                    if seenIds.insert(item.id).inserted {
                        results.append(item)
                    }
                }
            }
        }

        // 2. Supplement with LIKE search for substring matching (e.g. camelCase like sendReport)
        if results.count < limit {
            if let likeResults = try? performLikeSearch(query: trimmed, limit: limit - results.count) {
                for item in likeResults {
                    if seenIds.insert(item.id).inserted {
                        results.append(item)
                    }
                }
            }
        }

        return results
    }

    private func sanitizeFTS5Query(_ query: String) -> String {
        // Break into alphanumeric/cjk tokens and wrap each in double quotes with prefix match
        let components = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if components.isEmpty {
            return ""
        }

        return components.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    private func performFTSSearch(query: String, limit: Int) throws -> [SnippetSearchResult] {
        let sql = """
        SELECT s.id, s.folder_id, f.name AS folder_name, s.content, s.position
        FROM snippets_fts fts
        JOIN snippets s ON fts.rowid = s.id
        JOIN folders f ON s.folder_id = f.id
        WHERE snippets_fts MATCH ?
        ORDER BY bm25(snippets_fts) ASC, s.position ASC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, NSString(string: query).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [SnippetSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let folderId = sqlite3_column_int64(stmt, 1)
            let folderName = String(cString: sqlite3_column_text(stmt, 2))
            let content = String(cString: sqlite3_column_text(stmt, 3))
            let position = sqlite3_column_int64(stmt, 4)

            results.append(SnippetSearchResult(
                id: id,
                folderId: folderId,
                folderName: folderName,
                content: content,
                position: position
            ))
        }

        return results
    }

    private func performLikeSearch(query: String, limit: Int) throws -> [SnippetSearchResult] {
        let sql = """
        SELECT s.id, s.folder_id, f.name AS folder_name, s.content, s.position
        FROM snippets s
        JOIN folders f ON s.folder_id = f.id
        WHERE s.content LIKE ?
        ORDER BY s.position ASC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, NSString(string: pattern).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var results: [SnippetSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let folderId = sqlite3_column_int64(stmt, 1)
            let folderName = String(cString: sqlite3_column_text(stmt, 2))
            let content = String(cString: sqlite3_column_text(stmt, 3))
            let position = sqlite3_column_int64(stmt, 4)

            results.append(SnippetSearchResult(
                id: id,
                folderId: folderId,
                folderName: folderName,
                content: content,
                position: position
            ))
        }

        return results
    }

    // MARK: - Settings

    public func getSetting(key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        let sql = "SELECT value FROM settings WHERE key = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, NSString(string: key).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return String(cString: sqlite3_column_text(stmt, 0))
        }
        return nil
    }

    public func setSetting(key: String, value: String) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, NSString(string: key).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, NSString(string: value).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.stepFailed(lastErrorMessage())
        }
    }

    // MARK: - Helpers

    private func executeRaw(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let error = errMsg.flatMap { String(cString: $0) } ?? "Execution failed"
            sqlite3_free(errMsg)
            throw DatabaseError.executionFailed(error)
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }
}
