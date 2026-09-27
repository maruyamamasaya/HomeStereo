import Foundation
import XCTest
@testable import HomeStereoAppCore

final class PlaylistPersistenceTests: XCTestCase {
    func testPlaylistRoundTripKeepsOrderAndMissingTrackReferences() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        let ids = [UUID(), UUID(), UUID()]
        let playlist = Playlist(name: "Test", items: ids.map { PlaylistItem(trackID: $0) })
        try await repository.savePlaylist(playlist)

        let loaded = try await repository.loadPlaylists()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].items.map(\.trackID), ids)
    }

    func testNewerPlaylistSaveWinsDuringRapidSequentialEdits() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        var playlist = Playlist(name: "First")
        try await repository.savePlaylist(playlist)
        playlist.name = "Latest"; playlist.updatedAt = .now
        try await repository.savePlaylist(playlist)
        let loaded = try await repository.loadPlaylists()
        XCTAssertEqual(loaded.first?.name, "Latest")
    }

    func testPlaylistKindsAndWorkGenreClassificationArePreserved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        try await repository.savePlaylist(Playlist(name: "Regular", kind: PlaylistKind.regular.rawValue))
        try await repository.savePlaylist(Playlist(name: "Work", kind: PlaylistKind.work.rawValue))

        let loaded = try await repository.loadPlaylists()
        XCTAssertEqual(Set(loaded.map(\.playlistKind)), [.regular, .work])

        let work = Track(
            relativePath: "work.mp3", url: root.appendingPathComponent("work.mp3"),
            title: "Work", genre: "Ambient; 作業用BGM"
        )
        let regular = Track(
            relativePath: "regular.mp3", url: root.appendingPathComponent("regular.mp3"),
            title: "Regular", genre: "Ambient"
        )
        XCTAssertTrue(PlaylistKind.work.accepts(work))
        XCTAssertFalse(PlaylistKind.regular.accepts(work))
        XCTAssertTrue(PlaylistKind.regular.accepts(regular))
        XCTAssertFalse(PlaylistKind.work.accepts(regular))
    }
}
