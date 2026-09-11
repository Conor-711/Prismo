import Foundation
import SQLite3

// This is a separate device-only database, never the research or production server database.
final class FundingJournalDatabase {
    static let maximumEvents: UInt64 = 10_000
    private var connection: OpaquePointer?

    init(url: URL, mayInitialize: Bool) throws {
        let path = try FundingJournalFiles.databasePath(url)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
            | (mayInitialize ? SQLITE_OPEN_CREATE : 0)
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            connection = nil
            throw FundingJournalError.unavailable
        }
        do {
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=EXTRA")
            try execute("PRAGMA fullfsync=ON")
            try execute("PRAGMA temp_store=MEMORY")
            try execute("PRAGMA trusted_schema=OFF")
            guard try scalar("PRAGMA journal_mode") == "delete", try scalar("PRAGMA synchronous") == "3",
                  try scalar("PRAGMA fullfsync") == "1", try scalar("PRAGMA temp_store") == "2",
                  try scalar("PRAGMA trusted_schema") == "0", try scalar("PRAGMA quick_check") == "ok" else {
                throw FundingJournalError.integrity
            }
            let version = try scalar("PRAGMA user_version")
            let tables = try scalar("SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'")
            if mayInitialize && version == "0" && tables == "0" {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("CREATE TABLE journal_events(sequence INTEGER PRIMARY KEY CHECK(sequence > 0), sealed BLOB NOT NULL, digest BLOB NOT NULL CHECK(length(digest) = 32))")
                    try execute("PRAGMA user_version=1")
                    try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
            guard try scalar("PRAGMA user_version") == "1",
                  try scalar("SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'") == "1",
                  try scalar("SELECT name FROM sqlite_schema WHERE type='table'") == "journal_events" else {
                throw FundingJournalError.integrity
            }
        } catch {
            sqlite3_close(connection)
            connection = nil
            throw error
        }
    }

    deinit { if let connection { sqlite3_close(connection) } }

    func replay(anchor: FundingJournalAnchor) throws -> (FundingJournalCheckpoint, FundingJournalSnapshot) {
        let statement = try prepare("SELECT sequence, sealed, digest FROM journal_events ORDER BY sequence")
        defer { sqlite3_finalize(statement) }
        var cursor = anchor
        cursor.committed = .empty
        cursor.pending = nil
        var records = FundingJournalSnapshot()
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { throw FundingJournalError.integrity }
            let sequence = sqlite3_column_int64(statement, 0)
            guard sequence > 0, UInt64(sequence) <= Self.maximumEvents else { throw FundingJournalError.capacity }
            let checkpoint = FundingJournalCheckpoint(sequence: UInt64(sequence), digest: try blob(statement, column: 2, limit: 32))
            let sealed = try blob(statement, column: 1, limit: 16_412)
            let event = try FundingJournalCryptography.openEvent(sealed, checkpoint: checkpoint, anchor: cursor)
            try records.apply(event)
            cursor.committed = checkpoint
        }
        return (cursor.committed, records)
    }

    func append(_ sealed: Data, checkpoint: FundingJournalCheckpoint) throws {
        let statement = try prepare("INSERT INTO journal_events(sequence,sealed,digest) VALUES (?,?,?)")
        defer { sqlite3_finalize(statement) }
        guard checkpoint.sequence <= Self.maximumEvents else { throw FundingJournalError.capacity }
        guard sqlite3_bind_int64(statement, 1, Int64(checkpoint.sequence)) == SQLITE_OK else { throw FundingJournalError.unavailable }
        try bind(sealed, statement: statement, column: 2)
        try bind(checkpoint.digest, statement: statement, column: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FundingJournalError.unavailable }
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw FundingJournalError.unavailable }
    }

    private func scalar(_ sql: String) throws -> String {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { throw FundingJournalError.integrity }
        let result = String(cString: text)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw FundingJournalError.integrity }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw FundingJournalError.integrity
        }
        return statement
    }

    private func bind(_ data: Data, statement: OpaquePointer, column: Int32) throws {
        let status = data.withUnsafeBytes {
            sqlite3_bind_blob(statement, column, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard status == SQLITE_OK else { throw FundingJournalError.unavailable }
    }

    private func blob(_ statement: OpaquePointer, column: Int32, limit: Int) throws -> Data {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard sqlite3_column_type(statement, column) == SQLITE_BLOB, length > 0, length <= limit,
              let pointer = sqlite3_column_blob(statement, column) else { throw FundingJournalError.integrity }
        return Data(bytes: pointer, count: length)
    }
}
