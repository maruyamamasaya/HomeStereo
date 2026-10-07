import Foundation
import SQLite3
import XCTest
@testable import HomeStereoAppCore

final class StateBackupTests: XCTestCase {
    func testJSONRoundTripRestoresExactIDsOrderTagsEventsLinksAndSettingsAfterStartup() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("HomeStereo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let suite = "StateBackupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "audio.normalization.enabled")
        defaults.set("dark", forKey: "appearance.theme")
        let database = root.appendingPathComponent("Library.sqlite3")
        let id = UUID(), external = UUID()
        let playlist = Playlist(myMusicPlaylistID: UUID(), name: "夜", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 200), tags: ["集中"],
                                items: [PlaylistItem(trackID: id), PlaylistItem(trackID: UUID()), PlaylistItem(trackID: id)])
        do {
            let repository = try SQLiteLibraryRepository(databaseURL: database)
            try await repository.savePlaylist(playlist)
            try await repository.saveFavorite(Favorite(trackID: id, addedAt: Date(timeIntervalSince1970: 100)))
            try await repository.savePlaybackEvent(PlaybackEvent(id: id, trackID: id, startedAt: Date(timeIntervalSince1970: 200), playedSeconds: 45))
        }
        // Populate representative current-schema rows without requiring personal audio/bookmarks.
        try sql(database, """
        INSERT INTO library_folders(id,display_name,path,normalized_path,bookmark,access_state)
        VALUES('folder','Fixture','/tmp/fixture','/tmp/fixture',X'01','available');
        INSERT INTO tracks(id,folder_id,relative_path,normalized_path,file_size,modification_date,title,duration,file_extension,has_artwork,scan_state,metadata_version,last_scanned_at,audio_fingerprint)
        VALUES('\(id)','folder','song.flac','song.flac',42,10,'Song',60,'flac',0,'ready',1,10,'fingerprint-fixture');
        INSERT INTO track_preferences(home_track_id,playback_preference,updated_at) VALUES('\(id)',7,123);
        INSERT INTO mymusic_track_links(home_track_id,mymusic_track_id,relative_path,file_size,duration,matched_at,match_method,source)
        VALUES('\(id)','\(external)','song.flac',42,60,10,'manual','manual');
        INSERT INTO mymusic_playback_events(event_id,home_track_id,mymusic_track_id,played_at,play_duration,track_duration,completed,skipped,play_source,selection_type,platform,schema_version,ended_at,end_kind)
        VALUES('stable-event','\(id)','\(external)',100,45,60,0,1,'playlist','manual','macOS',1,145,'userSkip');
        INSERT INTO playback_track_summaries(home_track_id,play_count,total_playback_duration) VALUES('\(id)',4,182);
        INSERT INTO mymusic_library_play_counts(mymusic_track_id,play_count,imported_at) VALUES('\(external)',12,100);
        """)
        let analyzerData = Data("""
        {"schemaVersion":1,"analysisVersion":2,"generatedAt":"2026-09-01T12:00:00Z","tracks":[{"relativePath":"song.flac","fileSize":42,"duration":60,"features":{"calm":0.7,"integratedLUFS":-15,"truePeakDBTP":-2,"normalizationGainDB":0}}]}
        """.utf8)
        var record = try XCTUnwrap(FeatureCodec.decode(analyzerData, fileName: "fixture.json").first)
        record.trackID = external; record.homeStereoTrackID = id
        let encodedRecord = try JSONSerialization.jsonObject(with: FeatureCodec.encoder().encode(record))
        let featureData = try JSONSerialization.data(withJSONObject: ["version": 1, "records": [encodedRecord]])
        try featureData.write(to: root.appendingPathComponent("track-features.json"))
        let archive = root.appendingPathComponent("PlaylistImportArchive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try Data("original bytes".utf8).write(to: archive.appendingPathComponent("received-fixture.json"))
        let service = StateBackupService(root: root, defaults: defaults)
        let snapshot = try service.snapshot()
        let document = HomeStereoBackup(exportedAt: .now, appVersion: "test", playlists: [], favorites: [], playbackEvents: [],
                                       settings: .init(automaticLibraryUpdates: false), state: snapshot, schemaVersion: 2)
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        let payload = try XCTUnwrap(decoded.state)
        let before = try rows(database)
        try sql(database, "DELETE FROM playlists; DELETE FROM track_preferences; DELETE FROM mymusic_playback_events;")
        defaults.set(false, forKey: "audio.normalization.enabled")
        try service.stageRestore(payload)
        // Staging must not touch the live state.
        XCTAssertNotEqual(try rows(database), before)
        XCTAssertTrue(try service.applyPendingRestore())
        XCTAssertFalse(try service.applyPendingRestore())
        XCTAssertEqual(try rows(database), before)
        let reopened = try SQLiteLibraryRepository(databaseURL: database)
        let restored = try await reopened.loadPlaylists()
        XCTAssertEqual(restored, [playlist])
        XCTAssertEqual(defaults.bool(forKey: "audio.normalization.enabled"), true)
        XCTAssertEqual(defaults.string(forKey: "appearance.theme"), "dark")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("track-features.json")), featureData)
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("received-fixture.json")), Data("original bytes".utf8))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: base.path).contains { $0.hasPrefix("HomeStereo-before-restore-") })
    }

    func testCorruptPayloadAndTraversalCannotStageRestore() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let service = StateBackupService(root: base.appendingPathComponent("HomeStereo"))
        let settings = try PropertyListSerialization.data(fromPropertyList: [:], format: .binary, options: 0)
        let corrupt = StateBackupPayload(databaseSchemaVersion: 14, files: [.init(path: "Library.sqlite3", data: Data("bad".utf8))], settings: settings)
        XCTAssertThrowsError(try service.stageRestore(corrupt))
        let unsafe = StateBackupPayload(databaseSchemaVersion: 14, files: [.init(path: "Library.sqlite3", data: Data()), .init(path: "PlaylistImportArchive/../escape", data: Data())], settings: settings)
        XCTAssertThrowsError(try service.stageRestore(unsafe))
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.appendingPathComponent(".HomeStereo-pending-restore").path))
    }

    private func sql(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "FixtureSQL", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }
    private func rows(_ url: URL) throws -> [[String]] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
        defer { sqlite3_close(db) }
        var result: [[String]] = []
        for table in ["tracks", "playlists", "playlist_items", "favorites", "playback_events", "track_preferences", "mymusic_track_links", "mymusic_playback_events", "playback_track_summaries", "mymusic_library_play_counts"] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT * FROM \(table) ORDER BY 1,2", -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
            defer { sqlite3_finalize(statement) }
            result.append([table])
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "<NULL>"
                })
            }
        }
        return result
    }
}
