import Foundation
import XCTest
@testable import HomeStereoAppCore

final class BackupContractTests: XCTestCase {
    func testVersionOneFixtureRoundTripAndStableOrdering() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/home-stereo-backup-v1.json")
        let decoded = try BackupCodec.decode(Data(contentsOf: fixture))
        let first = try BackupCodec.encode(decoded)
        let second = try BackupCodec.encode(try BackupCodec.decode(first))
        XCTAssertEqual(first, second)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.playlists.first?.kind, PlaylistKind.regular.rawValue)
    }

    func testBackupPlaylistKindRoundTripsAndLegacyDefaultsToRegular() throws {
        let work = BackupPlaylist(
            id: UUID(), name: "Work", createdAt: .distantPast, updatedAt: .distantPast,
            kind: PlaylistKind.work.rawValue, tracks: []
        )
        let document = HomeStereoBackup(
            exportedAt: .distantPast, appVersion: "1", playlists: [work], favorites: [],
            playbackEvents: [], settings: BackupSettings(automaticLibraryUpdates: true)
        )
        let decoded = try BackupCodec.decode(BackupCodec.encode(document))
        XCTAssertEqual(decoded.playlists.first?.kind, PlaylistKind.work.rawValue)
    }

    func testInvalidDocumentAndUnsupportedVersionAreRejectedWhole() throws {
        let invalidDate = Data("{\"kind\":\"home-stereo-backup\",\"schemaVersion\":1,\"exportedAt\":\"bad\",\"appVersion\":\"1\",\"playlists\":[],\"favorites\":[],\"playbackEvents\":[],\"settings\":{\"automaticLibraryUpdates\":true}}".utf8)
        XCTAssertThrowsError(try BackupCodec.decode(invalidDate))
        let unsupported = HomeStereoBackup(exportedAt: .now, appVersion: "1", playlists: [], favorites: [], playbackEvents: [], settings: BackupSettings(automaticLibraryUpdates: true))
        var object = try JSONSerialization.jsonObject(with: BackupCodec.encode(unsupported)) as! [String: Any]
        object["schemaVersion"] = 99
        XCTAssertThrowsError(try BackupCodec.decode(try JSONSerialization.data(withJSONObject: object))) { error in
            XCTAssertEqual(error as? BackupContractError, .unsupportedVersion(99))
        }
    }

    func testTrackMatchingPriorityAndAmbiguousMetadataRejection() {
        let folder = UUID(), exactID = UUID()
        let exact = Track(id: exactID, libraryFolderID: folder, relativePath: "renamed.mp3", url: URL(fileURLWithPath: "/tmp/renamed.mp3"), fileSize: 20, title: "Other", duration: 5)
        let path = Track(libraryFolderID: folder, relativePath: "a/song.mp3", url: URL(fileURLWithPath: "/tmp/a/song.mp3"), fileSize: 10, title: "Song", artist: "A", album: "B", duration: 10)
        let duplicate = Track(libraryFolderID: folder, relativePath: "b/song.mp3", url: URL(fileURLWithPath: "/tmp/b/song.mp3"), fileSize: 10, title: "Song", artist: "A", album: "B", duration: 10)
        let idReference = BackupTrackReference(trackID: exactID, relativePath: "a/song.mp3", fileSize: 10, duration: 10, title: "Song")
        XCTAssertEqual(BackupTrackMatcher.match(idReference, tracks: [exact, path]), .matched(exactID))
        let ambiguous = BackupTrackReference(trackID: UUID(), relativePath: "missing.mp3", fileSize: 10, duration: 10, title: "Song", artist: "A", album: "B")
        XCTAssertEqual(BackupTrackMatcher.match(ambiguous, tracks: [path, duplicate]), .ambiguous)
    }

    func testBackupMergeDoesNotDeleteAndRollsBackOnFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        let existing = Favorite(trackID: UUID())
        try await repository.saveFavorite(existing)
        let sharedItemID = UUID()
        let one = Playlist(name: "One", items: [PlaylistItem(id: sharedItemID, trackID: UUID())])
        let two = Playlist(name: "Two", items: [PlaylistItem(id: sharedItemID, trackID: UUID())])
        do {
            try await repository.mergeBackup(playlists: [one, two], favorites: [Favorite(trackID: UUID())], events: [])
            XCTFail("Expected transaction failure")
        } catch {}
        let playlistsAfterRollback = try await repository.loadPlaylists()
        XCTAssertTrue(playlistsAfterRollback.isEmpty)
        let favoritesAfterRollback = try await repository.loadFavorites()
        XCTAssertEqual(favoritesAfterRollback.map(\.trackID), [existing.trackID])

        let event = PlaybackEvent(id: UUID(), trackID: UUID(), playedSeconds: 3)
        try await repository.mergeBackup(playlists: [], favorites: [], events: [event])
        try await repository.mergeBackup(playlists: [], favorites: [], events: [event])
        let events = try await repository.loadPlaybackEvents()
        let favorites = try await repository.loadFavorites()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(favorites.map(\.trackID), [existing.trackID])
    }
}
