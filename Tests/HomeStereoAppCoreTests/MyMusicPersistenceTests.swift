import Foundation
import SQLite3
import XCTest
@testable import HomeStereoAppCore

final class MyMusicPersistenceTests: XCTestCase {
    func testTrackLinkPersistsAcrossRepositoryRestartAndRepeatImportIsUnchanged() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let externalID = UUID()
        let fingerprint = String(repeating: "a", count: 64)
        let track = fixture.track(title: "Night", artist: "Artist", album: "Album", fingerprint: fingerprint)
        do {
            let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
            try await fixture.insert([track], into: repository)
            let service = MyMusicPersistenceService(repository: repository, clock: { Date(timeIntervalSince1970: 10) })
            let data = try libraryJSON(id: externalID, title: "Night", artist: "Artist", album: "Album", fingerprint: fingerprint)
            let first = try await service.importLibrary(data)
            let second = try await service.importLibrary(data)
            XCTAssertEqual(first.newlyLinked, 1)
            XCTAssertEqual(second.unchanged, 1)
        }

        let reopened = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let reopenedLinks = try await reopened.loadMyMusicTrackLinks()
        let link = try XCTUnwrap(reopenedLinks.first)
        XCTAssertEqual(link.homeStereoTrackID, track.id)
        XCTAssertEqual(link.myMusicTrackID, externalID)
        XCTAssertEqual(link.matchMethod, .fingerprint)
    }

    func testFingerprintMatchAndAmbiguousMetadataDoesNotAutoLink() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let fingerprint = String(repeating: "b", count: 64)
        let fingerprintTrack = fixture.track(relativePath: "fingerprint.flac", title: "Unique", artist: "A", album: "One", fingerprint: fingerprint)
        let duplicateOne = fixture.track(relativePath: "one.flac", title: "Same", artist: "B", album: "Two")
        let duplicateTwo = fixture.track(relativePath: "two.flac", title: "Same", artist: "B", album: "Two")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([fingerprintTrack, duplicateOne, duplicateTwo], into: repository)
        let service = MyMusicPersistenceService(repository: repository)

        let fingerprintResult = try await service.importLibrary(try libraryJSON(
            id: UUID(), title: "Different Metadata", artist: "X", album: "Y", fingerprint: fingerprint
        ))
        XCTAssertEqual(fingerprintResult.newlyLinked, 1)
        XCTAssertEqual(fingerprintResult.items.first?.homeStereoTrackID, fingerprintTrack.id)

        let ambiguousResult = try await service.importLibrary(try libraryJSON(
            id: UUID(), title: "Same", artist: "B", album: "Two"
        ))
        XCTAssertEqual(ambiguousResult.ambiguous, 1)
        let links = try await repository.loadMyMusicTrackLinks()
        XCTAssertEqual(links.count, 1)
    }

    func testOneHomeTrackIsNotLinkedToTwoImportedTrackIDsInSameBatch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let fingerprint = String(repeating: "c", count: 64)
        let track = fixture.track(title: "Song", artist: "A", album: "Album", fingerprint: fingerprint)
        let records = [UUID(), UUID()].map {
            MyMusicTrackRecord(
                trackID: $0, title: "Song", artist: "A", album: "Album", duration: 60,
                audioFingerprint: fingerprint
            )
        }
        let match = MyMusicLibraryMatcher.match(records, tracks: [track], links: [], matchedAt: .now)
        XCTAssertEqual(match.result.newlyLinked, 1)
        XCTAssertEqual(match.result.ambiguous, 1)
        XCTAssertEqual(match.linksToSave.count, 1)
    }

    func testPreferencesMergeKeepsOmittedValuesAndReportsUnknownTrack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let oneID = UUID(), twoID = UUID(), unknownID = UUID()
        let one = fixture.track(relativePath: "one.flac", title: "One", artist: "A", album: "Album")
        let two = fixture.track(relativePath: "two.flac", title: "Two", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([one, two], into: repository)
        try await repository.saveMyMusicTrackLinks([
            fixture.link(home: one, externalID: oneID), fixture.link(home: two, externalID: twoID)
        ])
        let service = MyMusicPersistenceService(repository: repository)
        let exportedAt = Date(timeIntervalSince1970: 100)
        let initial = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: oneID, playbackPreference: 4, favorite: true),
            MyMusicPreferenceRecord(trackID: twoID, playbackPreference: -2, favorite: false)
        ], exportedAt: exportedAt)
        let initialResult = try await service.importPreferences(initial)
        XCTAssertEqual(initialResult.updated, 2)

        let second = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: oneID, playbackPreference: 4, favorite: true),
            MyMusicPreferenceRecord(trackID: unknownID, playbackPreference: 1, favorite: false)
        ], exportedAt: exportedAt.addingTimeInterval(10))
        let result = try await service.importPreferences(second)
        XCTAssertEqual(result.unchanged, 1)
        XCTAssertEqual(result.unresolvedTrackIDs, [unknownID])
        let persistedPreferences = try await repository.loadMyMusicPreferences()
        let favorites = try await repository.loadFavorites()
        XCTAssertEqual(persistedPreferences.count, 2)
        XCTAssertEqual(favorites.map(\.trackID), [one.id])
    }

    func testPlaybackEventPersistsPlatformDeduplicatesAndReportsUnknownTrack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let externalID = UUID(), unknownID = UUID()
        let track = fixture.track(title: "Song", artist: "Artist", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([track], into: repository)
        try await repository.saveMyMusicTrackLinks([fixture.link(home: track, externalID: externalID)])
        let event = MyMusicPlaybackEventRecord(
            eventID: "ios-event-1", trackID: externalID, trackTitle: "Song", artist: "Artist",
            playedAt: Date(timeIntervalSince1970: 200), playDuration: 10, trackDuration: 20,
            completed: false, skipped: true, playSource: "library", selectionType: "manual", platform: "iOS"
        )
        let unknown = MyMusicPlaybackEventRecord(
            eventID: "ios-event-2", trackID: unknownID, trackTitle: "Missing", artist: "Artist",
            playedAt: Date(timeIntervalSince1970: 201), playDuration: 1, trackDuration: 2,
            completed: false, skipped: true, playSource: "library", selectionType: "manual", platform: "iOS"
        )
        let data = try MyMusicJSONExportService().exportPlaybackEvents([event, unknown], exportedAt: .now)
        let service = MyMusicPersistenceService(repository: repository)
        let first = try await service.importPlaybackEvents(data)
        let second = try await service.importPlaybackEvents(data)
        XCTAssertEqual(first.inserted, 1)
        XCTAssertEqual(first.unresolvedTrackIDs, [unknownID])
        XCTAssertEqual(second.duplicates, 1)
        XCTAssertEqual(second.unresolvedTrackIDs, [unknownID])
        let persistedEvents = try await repository.loadMyMusicPlaybackEvents()
        let persisted = try XCTUnwrap(persistedEvents.first)
        XCTAssertEqual(persisted.platform, "iOS")
        XCTAssertEqual(persisted.eventID, "ios-event-1")
    }

    func testUnlinkedLocalPlaybackIsKeptAndBecomesExportableAfterLinking() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let track = fixture.track(title: "Local Song", artist: "Artist", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([track], into: repository)
        let local = LocalMyMusicPlaybackEvent(
            eventID: "mac-550e8400-e29b-41d4-a716-446655440000",
            homeStereoTrackID: track.id, playedAt: Date(timeIntervalSince1970: 300),
            playDuration: 12, trackDuration: 60, completed: false, skipped: true,
            playSource: .library, selectionType: .manual
        )

        let firstInsert = try await repository.appendLocalMyMusicPlaybackEvent(local)
        let duplicateInsert = try await repository.appendLocalMyMusicPlaybackEvent(local)
        XCTAssertTrue(firstInsert)
        XCTAssertFalse(duplicateInsert)
        let storedEvents = try await repository.loadMyMusicPlaybackEvents()
        let stored = try XCTUnwrap(storedEvents.first)
        XCTAssertNil(stored.myMusicTrackID)
        XCTAssertEqual(stored.platform, "macOS")

        let service = MyMusicPersistenceService(repository: repository)
        let unresolved = try await service.exportPlaybackEventsWithReport(exportedAt: .now)
        XCTAssertEqual(unresolved.exported, 0)
        XCTAssertEqual(unresolved.unresolved, 1)

        let externalID = UUID()
        try await repository.saveMyMusicTrackLinks([fixture.link(home: track, externalID: externalID)])
        let resolved = try await service.exportPlaybackEventsWithReport(exportedAt: .now)
        XCTAssertEqual(resolved.exported, 1)
        XCTAssertEqual(resolved.unresolved, 0)
        let document = try MyMusicJSONCodec.decodePlaybackEvents(resolved.data)
        XCTAssertEqual(document.events.first?.trackId, externalID)
        XCTAssertEqual(document.events.first?.eventId, local.eventID)
    }

    func testTrackLinkTransactionRollsBackOnUniqueConstraintFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let one = fixture.track(relativePath: "one.flac", title: "One", artist: "A", album: "Album")
        let two = fixture.track(relativePath: "two.flac", title: "Two", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([one, two], into: repository)
        let duplicatedExternalID = UUID()
        do {
            try await repository.saveMyMusicTrackLinks([
                fixture.link(home: one, externalID: duplicatedExternalID),
                fixture.link(home: two, externalID: duplicatedExternalID)
            ])
            XCTFail("expected unique constraint failure")
        } catch {}
        let links = try await repository.loadMyMusicTrackLinks()
        XCTAssertTrue(links.isEmpty)
    }

    func testPreferenceTransactionDoesNotPartiallyApplyOnConstraintFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let oneID = UUID(), twoID = UUID()
        let one = fixture.track(relativePath: "one.flac", title: "One", artist: "A", album: "Album")
        let two = fixture.track(relativePath: "two.flac", title: "Two", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([one, two], into: repository)
        try await repository.saveMyMusicTrackLinks([
            fixture.link(home: one, externalID: oneID), fixture.link(home: two, externalID: twoID)
        ])
        do {
            _ = try await repository.mergeMyMusicPreferences([
                MyMusicPreferenceRecord(trackID: oneID, playbackPreference: 2, favorite: true),
                MyMusicPreferenceRecord(trackID: twoID, playbackPreference: 99, favorite: true)
            ], exportedAt: .now)
            XCTFail("expected CHECK constraint failure")
        } catch {}
        let preferences = try await repository.loadMyMusicPreferences()
        let favorites = try await repository.loadFavorites()
        XCTAssertTrue(preferences.isEmpty)
        XCTAssertTrue(favorites.isEmpty)
    }

    func testInvalidPreferencesDocumentDoesNotStartPersistence() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let externalID = UUID()
        let track = fixture.track(title: "One", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([track], into: repository)
        try await repository.saveMyMusicTrackLinks([fixture.link(home: track, externalID: externalID)])
        let invalid = Data("""
            {"schemaVersion":2,"exportedAt":"2026-09-25T12:34:56Z","tracks":[
              {"trackId":"\(externalID.uuidString)","playbackPreference":11,"favorite":true}
            ]}
            """.utf8)
        do {
            _ = try await MyMusicPersistenceService(repository: repository).importPreferences(invalid)
            XCTFail("invalid document must be rejected")
        } catch {}
        let preferences = try await repository.loadMyMusicPreferences()
        let favorites = try await repository.loadFavorites()
        XCTAssertTrue(preferences.isEmpty)
        XCTAssertTrue(favorites.isEmpty)
    }

    func testSchemaSixMigratesToCurrentWithoutDroppingExistingTrack() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let track = fixture.track(title: "Keep", artist: "A", album: "Album")
        do {
            let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
            try await fixture.insert([track], into: repository)
        }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.database.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, """
            DROP TABLE mymusic_playback_events;
            DROP TABLE mymusic_preferences;
            DROP TABLE mymusic_track_links;
            DROP INDEX idx_tracks_audio_fingerprint;
            ALTER TABLE tracks DROP COLUMN audio_fingerprint;
            ALTER TABLE tracks DROP COLUMN bit_rate;
            PRAGMA user_version = 6;
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let migrated = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let version = try await migrated.schemaVersion()
        let tracks = try await migrated.loadTracks(folderID: fixture.folderID)
        let links = try await migrated.loadMyMusicTrackLinks()
        XCTAssertEqual(version, SQLiteLibraryRepository.currentSchemaVersion)
        XCTAssertEqual(tracks.first?.id, track.id)
        XCTAssertTrue(links.isEmpty)
    }

    private func libraryJSON(
        id: UUID, title: String, artist: String, album: String, fingerprint: String? = nil
    ) throws -> Data {
        try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: id, title: title, artist: artist, album: album,
                duration: 60, format: "FLAC", audioFingerprint: fingerprint
            )
        ])
    }
}

private final class Fixture {
    let root: URL
    let folderURL: URL
    let database: URL
    let folderID = UUID()

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        folderURL = root.appendingPathComponent("Music", isDirectory: true)
        database = root.appendingPathComponent("Library.sqlite3")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func track(
        relativePath: String = "song.flac", title: String, artist: String, album: String,
        fingerprint: String? = nil
    ) -> Track {
        Track(
            libraryFolderID: folderID, relativePath: relativePath,
            url: folderURL.appendingPathComponent(relativePath), fileSize: 1_000,
            audioFingerprint: fingerprint, title: title, artist: artist, album: album,
            duration: 60, codec: "FLAC"
        )
    }

    func insert(_ tracks: [Track], into repository: SQLiteLibraryRepository) async throws {
        try await repository.addFolder(
            LibraryFolder(id: folderID, displayName: "Music", path: folderURL.path), bookmarkData: Data([1])
        )
        try await repository.applySuccessfulScan(folderID: folderID, tracks: tracks, scannedAt: .now)
    }

    func link(home: Track, externalID: UUID) -> MyMusicTrackLink {
        MyMusicTrackLink(
            homeStereoTrackID: home.id, myMusicTrackID: externalID, relativePath: home.relativePath,
            fileSize: home.fileSize, duration: home.duration, audioFingerprint: home.audioFingerprint,
            matchedAt: Date(timeIntervalSince1970: 1), matchMethod: .manual, source: .manual
        )
    }
}
