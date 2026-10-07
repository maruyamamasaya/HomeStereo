import Foundation
import CryptoKit
import SQLite3

/// Versioned JSON payload retaining the existing SQLite schema and all its IDs.
public struct StateBackupPayload: Codable, Equatable, Sendable {
    public struct File: Codable, Equatable, Sendable {
        public let path: String
        public let data: Data
        public let sha256: String
        public init(path: String, data: Data) {
            self.path = path; self.data = data
            sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
    public let databaseSchemaVersion: Int
    public let files: [File]
    public let settings: Data
}

public final class StateBackupService: @unchecked Sendable {
    private let root: URL
    private let defaults: UserDefaults
    private let manager = FileManager.default
    private let keys = ["LibraryAutoUpdateEnabled", "audio.normalization.enabled", "analysis.concurrency", "appearance.theme"]
    private let folders = ["PlaylistImportArchive", "AnalysisRuns"]
    public static func defaultRoot() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true).appendingPathComponent("HomeStereo")
    }
    public init(root: URL, defaults: UserDefaults = .standard) { self.root = root.standardizedFileURL.resolvingSymlinksInPath(); self.defaults = defaults }
    private var pending: URL { root.deletingLastPathComponent().appendingPathComponent(".HomeStereo-pending-restore") }

    public func snapshot() throws -> StateBackupPayload {
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let database = temporary.appendingPathComponent("Library.sqlite3")
        try snapshotDatabase(from: root.appendingPathComponent("Library.sqlite3"), to: database)
        var files = [StateBackupPayload.File(path: "Library.sqlite3", data: try Data(contentsOf: database))]
        let feature = root.appendingPathComponent("track-features.json")
        if manager.fileExists(atPath: feature.path) {
            guard try feature.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
            files.append(.init(path: "track-features.json", data: try Data(contentsOf: feature)))
        }
        for folder in folders {
            let directory = root.appendingPathComponent(folder)
            guard manager.fileExists(atPath: directory.path) else { continue }
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
            var enumerationError: Error?
            guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in
                enumerationError = error; return false
            }) else {
                throw CocoaError(.fileReadUnknown)
            }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
                if values.isRegularFile == true {
                    files.append(.init(path: String(url.standardizedFileURL.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1)), data: try Data(contentsOf: url)))
                }
            }
            if let enumerationError { throw enumerationError }
        }
        var settings: [String: Any] = [:]
        for key in keys { if let value = defaults.object(forKey: key) { settings[key] = value } }
        let payload = StateBackupPayload(databaseSchemaVersion: SQLiteLibraryRepository.currentSchemaVersion,
                                        files: files.sorted { $0.path < $1.path },
                                        settings: try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0))
        try validate(payload)
        return payload
    }

    public func validate(_ payload: StateBackupPayload) throws {
        guard payload.databaseSchemaVersion == SQLiteLibraryRepository.currentSchemaVersion,
              Set(payload.files.map(\.path)).count == payload.files.count,
              payload.files.contains(where: { $0.path == "Library.sqlite3" }) else {
            throw BackupContractError.invalidStructure("保存状態のschemaまたはファイル一覧が不正です")
        }
        for file in payload.files {
            _ = try safeURL(file.path, in: root)
            guard file.sha256 == SHA256.hash(data: file.data).map({ String(format: "%02x", $0) }).joined() else {
                throw BackupContractError.invalidStructure("ファイルのchecksumが一致しません")
            }
        }
        guard let settings = try PropertyListSerialization.propertyList(from: payload.settings, format: nil) as? [String: Any],
              Set(settings.keys).isSubset(of: Set(keys)) else { throw CocoaError(.propertyListReadCorrupt) }
        let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        for file in payload.files where file.path == "Library.sqlite3" || file.path == "track-features.json" {
            try file.data.write(to: temporary.appendingPathComponent(file.path))
        }
        try checkDatabase(temporary.appendingPathComponent("Library.sqlite3"))
        if payload.files.contains(where: { $0.path == "track-features.json" }) {
            // Full model/version validation, in addition to the checksum.
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: temporary.appendingPathComponent("track-features.json"))) as? [String: Any]
            guard object?["version"] as? Int == 1, let records = object?["records"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            for record in records {
                let data = try JSONSerialization.data(withJSONObject: record)
                try FeatureCodec.validate(FeatureCodec.decoder().decode(FeatureRecord.self, from: data))
            }
        }
    }

    /// Only stages data. The live database is never replaced while stores are open.
    public func stageRestore(_ payload: StateBackupPayload) throws {
        try validate(payload)
        guard !manager.fileExists(atPath: pending.path) else {
            throw BackupContractError.invalidStructure("復元が準備済みです。アプリを再起動してください")
        }
        let staging = root.deletingLastPathComponent().appendingPathComponent(".HomeStereo-restore-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }
        for file in payload.files {
            let url = try safeURL(file.path, in: staging)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: url, options: .atomic)
        }
        try JSONEncoder().encode(payload).write(to: staging.appendingPathComponent("restore-payload.json"), options: .atomic)
        try manager.moveItem(at: staging, to: pending)
    }

    /// Must run before SQLiteLibraryRepository opens. Keeps the previous root for recovery.
    @discardableResult public func applyPendingRestore() throws -> Bool {
        guard manager.fileExists(atPath: pending.path) else { return false }
        let payload = try JSONDecoder().decode(StateBackupPayload.self, from: Data(contentsOf: pending.appendingPathComponent("restore-payload.json")))
        try validate(payload)
        for file in payload.files {
            guard try Data(contentsOf: safeURL(file.path, in: pending)) == file.data else { throw CocoaError(.fileReadCorruptFile) }
        }
        let previous = root.deletingLastPathComponent().appendingPathComponent("HomeStereo-before-restore-\(UUID().uuidString)")
        let hadRoot = manager.fileExists(atPath: root.path)
        if hadRoot { try manager.moveItem(at: root, to: previous) }
        do { try manager.moveItem(at: pending, to: root) }
        catch {
            if hadRoot { try manager.moveItem(at: previous, to: root) }
            throw error
        }
        let settings = try PropertyListSerialization.propertyList(from: payload.settings, format: nil) as! [String: Any]
        for key in keys { defaults.removeObject(forKey: key) }
        for (key, value) in settings { defaults.set(value, forKey: key) }
        try? manager.removeItem(at: root.appendingPathComponent("restore-payload.json"))
        return true
    }

    private func safeURL(_ path: String, in directory: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              path == "Library.sqlite3" || path == "track-features.json" || folders.contains(String(parts[0])) && parts.count > 1 else {
            throw BackupContractError.invalidStructure("不正なbackup内path: \(path)")
        }
        return directory.appendingPathComponent(path)
    }
    private func snapshotDatabase(from source: URL, to destination: URL) throws {
        var input: OpaquePointer?, output: OpaquePointer?
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(input); throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(input) }
        guard sqlite3_open(destination.path, &output) == SQLITE_OK else { sqlite3_close(output); throw CocoaError(.fileWriteUnknown) }
        defer { sqlite3_close(output) }
        guard let backup = sqlite3_backup_init(output, "main", input, "main") else { throw CocoaError(.fileReadUnknown) }
        let result = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finished == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
    }
    private func checkDatabase(_ url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(database); throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_close(database) }
        for sql in ["PRAGMA integrity_check", "PRAGMA user_version", "PRAGMA foreign_key_check"] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
            defer { sqlite3_finalize(statement) }
            let result = sqlite3_step(statement)
            if sql.contains("integrity") {
                guard result == SQLITE_ROW, let value = sqlite3_column_text(statement, 0), String(cString: value) == "ok" else { throw CocoaError(.fileReadCorruptFile) }
            } else if sql.contains("user_version") {
                guard result == SQLITE_ROW, sqlite3_column_int(statement, 0) == SQLiteLibraryRepository.currentSchemaVersion else { throw CocoaError(.fileReadCorruptFile) }
            } else { guard result == SQLITE_DONE else { throw CocoaError(.fileReadCorruptFile) } }
        }
    }
}
