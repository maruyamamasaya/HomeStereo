import Foundation
import XCTest
import SQLite3
@testable import HomeStereoAppCore

final class PlaylistTagTests: XCTestCase {
    func testNormalizationMatchesMyMusicAndLimitsNeverTruncate() throws {
        XCTAssertEqual(try PlaylistTagRules.validatedTags([" 夜 ", "集中\n用", "NIGHT", "night", "夜"]),
            ["夜", "集中 用", "NIGHT"])
        XCTAssertThrowsError(try PlaylistTagRules.validatedTags([String(repeating: "あ", count: 41)]))
        XCTAssertThrowsError(try PlaylistTagRules.validatedTags((0...20).map { "tag\($0)" }))
    }

    func testTagEditsPersistWithoutChangingIdentityOrOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        var playlist = Playlist(myMusicPlaylistID: UUID(), name: "Tagged",
            items: [PlaylistItem(trackID: UUID()), PlaylistItem(trackID: UUID())])
        try await repository.savePlaylist(playlist)
        let identity = playlist.id, externalID = playlist.myMusicPlaylistID, items = playlist.items
        playlist.tags = try PlaylistTagRules.validatedTags(["夜", "集中"])
        playlist.updatedAt = .now
        try await repository.savePlaylist(playlist)
        let restored = try await repository.loadPlaylists()
        XCTAssertEqual(restored.first?.id, identity)
        XCTAssertEqual(restored.first?.myMusicPlaylistID, externalID)
        XCTAssertEqual(restored.first?.items, items)
        XCTAssertEqual(restored.first?.tags, ["夜", "集中"])
    }
    func testMergePreservesOrderTagsAndCreatesNewIdentity() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let first = Playlist(myMusicPlaylistID: UUID(), name: "A", tags: ["夜"], items: [PlaylistItem(trackID: a), PlaylistItem(trackID: b)])
        let second = Playlist(name: "B", tags: ["夜", "集中"], items: [PlaylistItem(trackID: b), PlaylistItem(trackID: c)])
        let merged = try PlaylistMerge.make(first: first, second: second, name: " C ")
        XCTAssertEqual(merged.name, "C")
        XCTAssertEqual(merged.items.map(\.trackID), [a, b, c])
        XCTAssertEqual(merged.tags, ["夜", "集中"])
        XCTAssertNil(merged.myMusicPlaylistID)
        XCTAssertNotEqual(merged.id, first.id)
        XCTAssertTrue(Set(merged.items.map(\.id)).isDisjoint(with: first.items.map(\.id)))
        XCTAssertEqual(try PlaylistMerge.make(first: first, second: second, name: "C", deduplicate: false).items.map(\.trackID), [a, b, b, c])
        XCTAssertThrowsError(try PlaylistMerge.make(first: first, second: first, name: "C"))
        XCTAssertThrowsError(try PlaylistMerge.make(first: first, second: Playlist(name: "Work", kind: "work"), name: "C"))
        XCTAssertThrowsError(try PlaylistMerge.make(first: first, second: second, name: " "))
    }

    func testMergeRetainsOrDeletesSourcesAndRejectsStaleSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        try await repository.savePlaylist(Playlist(name: "A", items: [PlaylistItem(trackID: UUID())]))
        try await repository.savePlaylist(Playlist(name: "B", items: [PlaylistItem(trackID: UUID())]))
        let initial = try await repository.loadPlaylists()
        let first = initial[0], second = initial[1]
        let retained = try await repository.mergePlaylists(first: first, second: second, name: "Retained", deduplicate: true, removeSources: false)
        let afterRetain = try await repository.loadPlaylists()
        XCTAssertEqual(afterRetain.count, 3)
        XCTAssertEqual(afterRetain.first { $0.id == first.id }, first)
        _ = try await repository.mergePlaylists(first: first, second: second, name: "Replaced", deduplicate: true, removeSources: true)
        let afterDelete = try await repository.loadPlaylists()
        XCTAssertEqual(afterDelete.count, 2)
        XCTAssertNotNil(afterDelete.first { $0.id == retained.id })
        XCTAssertFalse(afterDelete.contains { $0.id == first.id || $0.id == second.id })
        do {
            _ = try await repository.mergePlaylists(first: first, second: second, name: "Stale", deduplicate: true, removeSources: true)
            XCTFail("Stale sources must be rejected")
        } catch {}
        let unchanged = try await repository.loadPlaylists()
        XCTAssertEqual(unchanged, afterDelete)
        let archived = try FileManager.default.subpathsOfDirectory(atPath: root.path)
        XCTAssertTrue(archived.contains { $0.contains("merge-before-") })
    }

    func testMergeRollsBackCreationAndBothDeletionsOnSecondDeleteFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite3")
        let repository = try SQLiteLibraryRepository(databaseURL: url)
        try await repository.savePlaylist(Playlist(name: "A"))
        try await repository.savePlaylist(Playlist(name: "B"))
        let initial = try await repository.loadPlaylists()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = "CREATE TRIGGER fail_second_delete BEFORE DELETE ON playlists WHEN OLD.id = '\(initial[1].id.uuidString)' BEGIN SELECT RAISE(ABORT, 'injected failure'); END;"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        do {
            _ = try await repository.mergePlaylists(first: initial[0], second: initial[1], name: "Merged", deduplicate: true, removeSources: true)
            XCTFail("Injected deletion failure must propagate")
        } catch {}
        let restored = try await repository.loadPlaylists()
        XCTAssertEqual(restored, initial)
    }

    func testUniqueBatchAdditionPreservesExistingItemsAndSkipsRepeatedTracks() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
        let a = UUID(), b = UUID(), c = UUID()
        let first = Playlist(name: "A", tags: ["夜"], items: [PlaylistItem(trackID: a), PlaylistItem(trackID: a)])
        let second = Playlist(name: "B", kind: "work", items: [PlaylistItem(trackID: b)])
        try await repository.savePlaylist(first)
        try await repository.savePlaylist(second)
        let count = try await repository.appendUniqueTracks([a, b, b, c], to: [first.id, second.id, first.id])
        XCTAssertEqual(count, 4)
        let saved = try await repository.loadPlaylists()
        XCTAssertEqual(saved.first { $0.id == first.id }?.items.map(\.trackID), [a, a, b, c])
        XCTAssertEqual(saved.first { $0.id == first.id }?.items.prefix(2), first.items[...])
        XCTAssertEqual(saved.first { $0.id == first.id }?.tags, ["夜"])
        XCTAssertEqual(saved.first { $0.id == second.id }?.items.map(\.trackID), [b, a, c])
        let repeated = try await repository.appendUniqueTracks([a, b, c], to: [first.id, second.id])
        XCTAssertEqual(repeated, 0)
        let unchanged = try await repository.loadPlaylists()
        XCTAssertEqual(unchanged, saved)
        do {
            _ = try await repository.appendUniqueTracks([UUID()], to: [first.id, UUID()])
            XCTFail("Deleted destination must reject entire batch")
        } catch {}
        let afterFailure = try await repository.loadPlaylists()
        XCTAssertEqual(afterFailure, saved)
    }

    func testUniqueBatchAdditionRollsBackAllDestinationsOnSaveFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite3")
        let repository = try SQLiteLibraryRepository(databaseURL: url)
        try await repository.savePlaylist(Playlist(name: "A"))
        try await repository.savePlaylist(Playlist(name: "B"))
        let initial = try await repository.loadPlaylists()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let sql = "CREATE TRIGGER fail_second_update BEFORE UPDATE ON playlists WHEN OLD.id = '\(initial[1].id.uuidString)' BEGIN SELECT RAISE(ABORT, 'injected failure'); END;"
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        do {
            _ = try await repository.appendUniqueTracks([UUID()], to: initial.map(\.id))
            XCTFail("Injected failure must propagate")
        } catch {}
        let restored = try await repository.loadPlaylists()
        XCTAssertEqual(restored, initial)
    }

}
