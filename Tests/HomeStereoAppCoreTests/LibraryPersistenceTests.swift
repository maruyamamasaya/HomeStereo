import Foundation
import SQLite3
import XCTest
@testable import HomeStereoAppCore

final class LibraryPersistenceTests: XCTestCase {
    func testSchemaFolderAndTrackRoundTripKeepsStableID() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        try await repository.addFolder(folder, bookmarkData: Data([1, 2, 3]))

        let schemaVersion = try await repository.schemaVersion()
        XCTAssertEqual(schemaVersion, 6)
        let first = try await LibraryService().scan(folder: folder, resolvedURL: fixture.folder, existingTracks: []) { _ in }
        try await repository.applySuccessfulScan(folderID: folder.id, tracks: first.tracks, scannedAt: .now)
        let persisted = try await repository.loadTracks(folderID: folder.id)
        let second = try await LibraryService().scan(folder: folder, resolvedURL: fixture.folder, existingTracks: persisted) { _ in }

        XCTAssertEqual(first.tracks.first?.id, second.tracks.first?.id)
        XCTAssertEqual(second.progress.unchanged, 1)
        XCTAssertEqual(second.progress.added, 0)
    }

    func testChangedAndMissingFilesAreReportedOnlyBySuccessfulScan() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        let service = LibraryService()
        let first = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: []) { _ in }
        let id = try XCTUnwrap(first.tracks.first?.id)

        try Fixture.makeSilentWAV(duration: 2).write(to: fixture.audio)
        let updated = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: first.tracks) { _ in }
        XCTAssertEqual(updated.progress.updated, 1)
        XCTAssertEqual(updated.tracks.first?.id, id)

        try FileManager.default.removeItem(at: fixture.audio)
        let missing = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: updated.tracks) { _ in }
        XCTAssertEqual(missing.progress.missing, 1)
        XCTAssertEqual(missing.tracks.first?.scanState, .missing)
    }

    func testRecursiveScanSkipsHiddenFilesAndSymlinks() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let nested = fixture.folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Fixture.makeSilentWAV(duration: 1).write(to: nested.appendingPathComponent("second.AIF"))
        try Fixture.makeSilentWAV(duration: 1).write(to: fixture.folder.appendingPathComponent(".hidden.wav"))
        try FileManager.default.createSymbolicLink(
            at: fixture.folder.appendingPathComponent("linked.wav"),
            withDestinationURL: fixture.audio
        )
        let result = try await LibraryService().scan(
            folder: LibraryFolder(displayName: "Music", path: fixture.folder.path),
            resolvedURL: fixture.folder, existingTracks: []
        ) { _ in }
        XCTAssertEqual(result.progress.discovered, 2)
        XCTAssertTrue(result.tracks.contains { $0.relativePath == "Nested/second.AIF" })
    }

    func testCancelledScanDoesNotMutateRepository() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        try await repository.addFolder(folder, bookmarkData: Data([1]))
        let original = Track(libraryFolderID: folder.id, relativePath: "old.wav", url: fixture.audio, title: "Old")
        try await repository.applySuccessfulScan(folderID: folder.id, tracks: [original], scannedAt: .now)

        let task = Task {
            try Task.checkCancellation()
            return try await LibraryService().scan(folder: folder, resolvedURL: fixture.folder, existingTracks: [original]) { _ in }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("scan should be cancelled") } catch is CancellationError {}
        let retainedIDs = try await repository.loadTracks(folderID: folder.id).map(\.id)
        XCTAssertEqual(retainedIDs, [original.id])
    }

    func testTransactionRollsBackWhenOneTrackViolatesPrimaryKey() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        try await repository.addFolder(folder, bookmarkData: Data([1]))
        let sharedID = UUID()
        let one = Track(id: sharedID, libraryFolderID: folder.id, relativePath: "one.wav", url: fixture.audio, title: "One")
        let twoURL = fixture.folder.appendingPathComponent("two.wav")
        let two = Track(id: sharedID, libraryFolderID: folder.id, relativePath: "two.wav", url: twoURL, title: "Two")

        do { try await repository.applySuccessfulScan(folderID: folder.id, tracks: [one, two], scannedAt: .now); XCTFail("expected constraint failure") }
        catch {}
        let remaining = try await repository.loadTracks(folderID: folder.id)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRenameKeepsTrackIDAndAllStoredReferences() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        try await repository.addFolder(folder, bookmarkData: Data([1]))
        let service = LibraryService()
        let first = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: []) { _ in }
        let original = try XCTUnwrap(first.tracks.first)
        try await repository.applySuccessfulScan(folderID: folder.id, tracks: first.tracks, scannedAt: .now)
        try await repository.saveQueue(QueueSnapshot(items: [QueueItem(trackID: original.id)], currentIndex: 0))
        try await repository.savePlaylist(Playlist(name: "Keep", items: [PlaylistItem(trackID: original.id)]))
        try await repository.saveFavorite(Favorite(trackID: original.id))
        try await repository.savePlaybackEvent(PlaybackEvent(trackID: original.id, startedAt: .now, playedSeconds: 3, outcome: .stopped))

        let renamed = fixture.folder.appendingPathComponent("renamed.wav")
        try FileManager.default.moveItem(at: fixture.audio, to: renamed)
        let existing = try await repository.loadTracks(folderID: folder.id)
        let result = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: existing) { _ in }
        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks[0].id, original.id)
        XCTAssertEqual(result.tracks[0].relativePath, "renamed.wav")
        XCTAssertTrue(result.notices.contains { $0.message.contains("fileResourceIdentifier") })
        try await repository.applySuccessfulScan(folderID: folder.id, tracks: result.tracks, scannedAt: .now)

        let retainedTracks = try await repository.loadTracks(folderID: folder.id)
        let retainedQueue = try await repository.loadQueue()
        let retainedPlaylists = try await repository.loadPlaylists()
        let retainedFavorites = try await repository.loadFavorites()
        let retainedEvents = try await repository.loadPlaybackEvents()
        XCTAssertEqual(retainedTracks.first?.id, original.id)
        XCTAssertEqual(retainedQueue.items.first?.trackID, original.id)
        XCTAssertEqual(retainedPlaylists.first?.items.first?.trackID, original.id)
        XCTAssertEqual(retainedFavorites.first?.trackID, original.id)
        XCTAssertEqual(retainedEvents.first?.trackID, original.id)
    }

    func testMoveWithinFolderAndMissingReturnKeepTrackID() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        let service = LibraryService()
        let first = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: []) { _ in }
        let original = try XCTUnwrap(first.tracks.first)
        let nested = fixture.folder.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let moved = nested.appendingPathComponent("tone.wav")
        try FileManager.default.moveItem(at: fixture.audio, to: moved)
        let movedScan = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: first.tracks) { _ in }
        XCTAssertEqual(movedScan.tracks.first?.id, original.id)
        XCTAssertEqual(movedScan.tracks.first?.relativePath, "Album/tone.wav")

        try FileManager.default.removeItem(at: moved)
        let missing = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: movedScan.tracks) { _ in }
        XCTAssertEqual(missing.tracks.first?.scanState, .missing)
        try Fixture.makeSilentWAV(duration: 1).write(to: moved)
        let returned = try await service.scan(folder: folder, resolvedURL: fixture.folder, existingTracks: missing.tracks) { _ in }
        XCTAssertEqual(returned.tracks.first?.id, original.id)
        XCTAssertEqual(returned.tracks.first?.scanState, .available)
    }

    func testFailedMoveTransactionRollsBackPathAndTrackID() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        try await repository.addFolder(folder, bookmarkData: Data([1]))
        let original = Track(libraryFolderID: folder.id, relativePath: "old.wav", url: fixture.audio, title: "Old")
        try await repository.applySuccessfulScan(folderID: folder.id, tracks: [original], scannedAt: .now)
        let moved = original.replacingIdentity(id: original.id, relativePath: "new.wav", url: fixture.folder.appendingPathComponent("new.wav"), scannedAt: .now)
        let duplicate = Track(id: original.id, libraryFolderID: folder.id, relativePath: "other.wav", url: fixture.folder.appendingPathComponent("other.wav"), title: "Other")
        do {
            try await repository.applySuccessfulScan(folderID: folder.id, tracks: [moved, duplicate], scannedAt: .now)
            XCTFail("duplicate Track ID must reject the whole scan")
        } catch {}
        let retainedTracks = try await repository.loadTracks(folderID: folder.id)
        let retained = try XCTUnwrap(retainedTracks.first)
        XCTAssertEqual(retained.id, original.id)
        XCTAssertEqual(retained.relativePath, "old.wav")
    }

    func testSchemaFiveMigratesToSixWithoutDroppingTracks() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let folder = LibraryFolder(displayName: "Music", path: fixture.folder.path)
        let track = Track(libraryFolderID: folder.id, relativePath: "tone.wav", url: fixture.audio, title: "Tone")
        do {
            let initial = try SQLiteLibraryRepository(databaseURL: fixture.database)
            try await initial.addFolder(folder, bookmarkData: Data([1]))
            try await initial.applySuccessfulScan(folderID: folder.id, tracks: [track], scannedAt: .now)
        }

        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.database.path, &database), SQLITE_OK)
        XCTAssertEqual(
            sqlite3_exec(database, "ALTER TABLE tracks DROP COLUMN file_resource_identifier; PRAGMA user_version = 5;", nil, nil, nil),
            SQLITE_OK
        )
        sqlite3_close(database)

        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let version = try await repository.schemaVersion()
        XCTAssertEqual(version, 6)
        let tracks = try await repository.loadTracks(folderID: folder.id)
        XCTAssertEqual(tracks.first?.id, track.id)
        XCTAssertNil(tracks.first?.fileResourceIdentifier)
    }
}

private struct Fixture {
    let root: URL
    let folder: URL
    let audio: URL
    let database: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        folder = root.appendingPathComponent("Music", isDirectory: true)
        audio = folder.appendingPathComponent("tone.wav")
        database = root.appendingPathComponent("Library.sqlite3")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.makeSilentWAV(duration: 1).write(to: audio)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    static func makeSilentWAV(duration: Int) -> Data {
        let sampleRate: UInt32 = 8_000
        let dataSize = sampleRate * UInt32(duration) * 2
        var data = Data()
        data.appendASCII("RIFF"); data.appendLE(UInt32(36) + dataSize); data.appendASCII("WAVEfmt ")
        data.appendLE(UInt32(16)); data.appendLE(UInt16(1)); data.appendLE(UInt16(1)); data.appendLE(sampleRate)
        data.appendLE(sampleRate * 2); data.appendLE(UInt16(2)); data.appendLE(UInt16(16)); data.appendASCII("data")
        data.appendLE(dataSize); data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) { append(value.data(using: .ascii)!) }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
