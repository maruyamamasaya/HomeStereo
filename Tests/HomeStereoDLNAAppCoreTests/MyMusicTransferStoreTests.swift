import Foundation
import XCTest
@testable import HomeStereoAppCore
@testable import HomeStereoDLNAAppCore

@MainActor
final class MyMusicTransferStoreTests: XCTestCase {
    func testAllDocumentKindsCreatePreviewWithoutWriting() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let track = try await fixture.insertTrack(repository: repository)
        let externalID = UUID()
        let service = MyMusicTransferService(repository: repository)

        let library = try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: externalID, title: track.title, artist: track.artist ?? "",
                album: track.album, duration: track.duration
            )
        ])
        let libraryPreview = try await service.preview(library, as: .library)
        XCTAssertEqual(libraryPreview.total, 1)
        XCTAssertEqual(libraryPreview.newlyLinked, 1)
        let linksBeforeApply = try await repository.loadMyMusicTrackLinks()
        XCTAssertTrue(linksBeforeApply.isEmpty)

        try await repository.saveMyMusicTrackLinks([fixture.link(track, externalID: externalID)])
        let preferences = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: externalID, playbackPreference: 4, favorite: true)
        ], exportedAt: fixture.now)
        let preferencesPreview = try await service.preview(preferences, as: .preferences)
        XCTAssertEqual(preferencesPreview.total, 1)
        XCTAssertEqual(preferencesPreview.pendingUpdates, 1)
        let preferencesBeforeApply = try await repository.loadMyMusicPreferences()
        XCTAssertTrue(preferencesBeforeApply.isEmpty)

        let events = try MyMusicJSONExportService().exportPlaybackEvents([
            fixture.event(trackID: externalID, eventID: "event-1")
        ], exportedAt: fixture.now)
        let eventsPreview = try await service.preview(events, as: .playbackEvents)
        XCTAssertEqual(eventsPreview.total, 1)
        XCTAssertEqual(eventsPreview.pendingInserts, 1)
        let eventsBeforeApply = try await repository.loadMyMusicPlaybackEvents()
        XCTAssertTrue(eventsBeforeApply.isEmpty)
    }

    func testWrongDocumentTypeAndUnsupportedVersionAreRejected() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let service = MyMusicTransferService(repository: repository)
        let preferences = try MyMusicJSONExportService().exportPreferences([], exportedAt: fixture.now)
        do {
            _ = try await service.preview(preferences, as: .library)
            XCTFail("wrong document type must fail")
        } catch let error as MyMusicTransferServiceError {
            XCTAssertEqual(error, .wrongDocumentType(expected: .library))
        }
        let unsupported = Data(#"{"version":99,"tracks":[]}"#.utf8)
        do {
            _ = try await service.preview(unsupported, as: .library)
            XCTFail("unsupported version must fail")
        } catch let error as MyMusicJSONContractError {
            XCTAssertEqual(error, .unsupportedVersion(99))
        }
    }

    func testCancelDoesNotWriteAndConfirmationDoes() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let track = try await fixture.insertTrack(repository: repository)
        let externalID = UUID()
        let data = try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: externalID, title: track.title, artist: track.artist ?? "",
                album: track.album, duration: track.duration
            )
        ])
        let files = FakeMyMusicFiles()
        let store = MyMusicTransferStore(repository: repository, files: files)

        await store.prepareImport(.library, data: data)
        XCTAssertEqual(store.state, .preview)
        store.cancelImport()
        let linksAfterCancel = try await repository.loadMyMusicTrackLinks()
        XCTAssertTrue(linksAfterCancel.isEmpty)

        await store.prepareImport(.library, data: data)
        // A second operation is ignored while a preview awaits confirmation.
        await store.prepareImport(.preferences, data: Data())
        XCTAssertEqual(store.preview?.kind, .library)
        await store.applyImport()
        XCTAssertEqual(store.state, .completed)
        let linksAfterApply = try await repository.loadMyMusicTrackLinks()
        XCTAssertEqual(linksAfterApply.first?.myMusicTrackID, externalID)
    }

    func testPlaybackExportReportsResolvedAndUnresolvedAndEmptyIsValid() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let linked = try await fixture.insertTrack(repository: repository, name: "linked.mp3", title: "Linked")
        let unlinked = try await fixture.insertTrack(repository: repository, name: "unlinked.mp3", title: "Unlinked")
        let externalID = UUID()
        try await repository.saveMyMusicTrackLinks([fixture.link(linked, externalID: externalID)])
        _ = try await repository.appendLocalMyMusicPlaybackEvent(fixture.localEvent(trackID: linked.id, id: "mac-linked"))
        _ = try await repository.appendLocalMyMusicPlaybackEvent(fixture.localEvent(trackID: unlinked.id, id: "mac-unlinked"))
        let files = FakeMyMusicFiles()
        let store = MyMusicTransferStore(repository: repository, files: files)

        await store.export(.playbackEvents)
        XCTAssertEqual(store.state, .completed)
        XCTAssertEqual(store.exportResult?.exportedEvents, 1)
        XCTAssertEqual(store.exportResult?.unresolvedEvents, 1)
        XCTAssertEqual(store.exportResult?.hasUnresolvedEventWarning, true)
        XCTAssertEqual(files.requestedFileName, MyMusicJSONCodec.playbackEventsFileName)
        let written = try XCTUnwrap(files.writtenData)
        XCTAssertEqual(try MyMusicJSONCodec.decodePlaybackEvents(written).events.count, 1)

        let emptyFixture = try TransferFixture()
        defer { emptyFixture.cleanup() }
        let emptyRepository = try SQLiteLibraryRepository(databaseURL: emptyFixture.database)
        let emptyFiles = FakeMyMusicFiles()
        let emptyStore = MyMusicTransferStore(repository: emptyRepository, files: emptyFiles)
        await emptyStore.export(.playbackEvents)
        let emptyData = try XCTUnwrap(emptyFiles.writtenData)
        XCTAssertTrue(try MyMusicJSONCodec.decodePlaybackEvents(emptyData).events.isEmpty)
    }

    func testInvalidServiceInputMovesStoreToFailedAndFileNamesAreStable() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let store = MyMusicTransferStore(repository: repository, files: FakeMyMusicFiles())
        await store.prepareImport(.library, data: Data("not-json".utf8))
        XCTAssertEqual(store.state, .failed)
        XCTAssertTrue(store.errorMessage?.contains("JSONの構文") == true)

        store.dismissResult()
        let utf16 = #"{"version":1,"tracks":[]}"#.data(using: .utf16)!
        await store.prepareImport(.library, data: utf16)
        XCTAssertEqual(store.state, .failed)
        XCTAssertTrue(store.errorMessage?.contains("UTF-8") == true)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(MyMusicDocumentKind.library.fileName, "MyMusic-Library.json")
        XCTAssertEqual(MyMusicDocumentKind.preferences.fileName, "MyMusic-Playback-Preferences.json")
        XCTAssertEqual(MyMusicDocumentKind.playbackEvents.fileName, "MyMusic-Playback-Events.json")
    }
}

@MainActor
private final class FakeMyMusicFiles: MyMusicFileServicing {
    var requestedFileName: String?
    var writtenData: Data?
    let output = URL(fileURLWithPath: "/tmp/MyMusic-Test.json")

    func chooseImportURL() -> URL? { nil }
    func chooseExportURL(defaultFileName: String) -> URL? {
        requestedFileName = defaultFileName; return output
    }
    func read(from url: URL) throws -> Data { Data() }
    func write(_ data: Data, to url: URL) throws { writtenData = data }
}

private final class TransferFixture {
    let root: URL
    let database: URL
    let folderID = UUID()
    let now = Date(timeIntervalSince1970: 1_000)

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        database = root.appendingPathComponent("Library.sqlite3")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func insertTrack(
        repository: SQLiteLibraryRepository, name: String = "song.mp3", title: String = "Song"
    ) async throws -> Track {
        if try await repository.loadFolder(id: folderID) == nil {
            try await repository.addFolder(
                LibraryFolder(id: folderID, displayName: "Fixture", path: root.path),
                bookmarkData: Data("fixture".utf8)
            )
        }
        let file = root.appendingPathComponent(name)
        try Data().write(to: file)
        let track = Track(
            libraryFolderID: folderID, relativePath: name, url: file,
            title: title, artist: "Artist", album: "Album", duration: 60
        )
        var tracks = try await repository.loadTracks(folderID: folderID)
        tracks.append(track)
        try await repository.applySuccessfulScan(folderID: folderID, tracks: tracks, scannedAt: now)
        return track
    }

    func link(_ track: Track, externalID: UUID) -> MyMusicTrackLink {
        MyMusicTrackLink(
            homeStereoTrackID: track.id, myMusicTrackID: externalID,
            relativePath: track.relativePath, fileSize: track.fileSize, duration: track.duration,
            matchedAt: now, matchMethod: .manual, source: .manual
        )
    }

    func event(trackID: UUID, eventID: String) -> MyMusicPlaybackEventRecord {
        MyMusicPlaybackEventRecord(
            eventID: eventID, trackID: trackID, trackTitle: "Song", artist: "Artist",
            playedAt: now, playDuration: 10, trackDuration: 60,
            completed: false, skipped: true, playSource: "library",
            selectionType: "manual", platform: "iOS"
        )
    }

    func localEvent(trackID: UUID, id: String) -> LocalMyMusicPlaybackEvent {
        LocalMyMusicPlaybackEvent(
            eventID: id, homeStereoTrackID: trackID, playedAt: now,
            playDuration: 10, trackDuration: 60, completed: false, skipped: false,
            playSource: .library, selectionType: .manual
        )
    }
}
