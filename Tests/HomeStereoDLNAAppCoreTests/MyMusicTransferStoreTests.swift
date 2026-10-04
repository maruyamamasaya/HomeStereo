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

        let playlists = try MyMusicJSONExportService().exportPlaylists([
            MyMusicPlaylistRecord(
                playlistID: UUID(), name: "Fixture", createdAt: fixture.now, updatedAt: fixture.now,
                tracks: [MyMusicPlaylistTrackRecord(trackID: externalID, title: track.title)]
            )
        ])
        let playlistsPreview = try await service.preview(playlists, as: .playlists)
        XCTAssertEqual(playlistsPreview.addedPlaylists, 1)
        XCTAssertEqual(playlistsPreview.importedTracks, 1)
        let playlistsBeforeApply = try await repository.loadPlaylists()
        XCTAssertTrue(playlistsBeforeApply.isEmpty)
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

    func testPlaybackExportFiltersByPlayedAtAndCountsOnlyUnresolvedEventsInRange() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let linked = try await fixture.insertTrack(repository: repository, name: "linked.mp3", title: "Linked")
        let unlinked = try await fixture.insertTrack(repository: repository, name: "unlinked.mp3", title: "Unlinked")
        try await repository.saveMyMusicTrackLinks([fixture.link(linked, externalID: UUID())])
        let january = Date(timeIntervalSince1970: 1_704_110_400)
        let february = Date(timeIntervalSince1970: 1_706_788_800)
        _ = try await repository.appendLocalMyMusicPlaybackEvent(
            fixture.localEvent(trackID: linked.id, id: "january-linked", playedAt: january)
        )
        _ = try await repository.appendLocalMyMusicPlaybackEvent(
            fixture.localEvent(trackID: unlinked.id, id: "january-unlinked", playedAt: january)
        )
        _ = try await repository.appendLocalMyMusicPlaybackEvent(
            fixture.localEvent(trackID: linked.id, id: "february-linked", playedAt: february)
        )
        let files = FakeMyMusicFiles()
        let store = MyMusicTransferStore(repository: repository, files: files)

        await store.export(.playbackEvents, playbackEventsRange: january..<february)

        let document = try MyMusicJSONCodec.decodePlaybackEvents(XCTUnwrap(files.writtenData))
        XCTAssertEqual(document.events.map(\.eventId), ["january-linked"])
        XCTAssertEqual(store.exportResult?.exportedEvents, 1)
        XCTAssertEqual(store.exportResult?.unresolvedEvents, 1)
        XCTAssertEqual(store.exportResult?.playbackEventsRange, january..<february)
    }

    func testExportCanReplacePendingImportPreview() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let files = FakeMyMusicFiles()
        let store = MyMusicTransferStore(repository: repository, files: files)
        let previewData = try MyMusicJSONExportService().exportPreferences([], exportedAt: fixture.now)
        await store.prepareImport(.preferences, data: previewData)
        XCTAssertEqual(store.state, .preview)

        await store.export(.playbackEvents)

        XCTAssertEqual(store.state, .completed)
        XCTAssertNil(store.preview)
        XCTAssertEqual(store.exportResult?.kind, .playbackEvents)
        XCTAssertNotNil(files.writtenData)
    }

    func testPreferencesExportPreviewsMacChangesAndClearsThemOnlyAfterWriting() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let track = try await fixture.insertTrack(repository: repository)
        let externalID = UUID()
        try await repository.saveMyMusicTrackLinks([fixture.link(track, externalID: externalID)])
        let imported = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: externalID, playbackPreference: 0, favorite: false)
        ], exportedAt: fixture.now)
        _ = try await MyMusicPersistenceService(repository: repository).importPreferences(imported)
        try await repository.saveFavorite(Favorite(trackID: track.id, addedAt: fixture.now))
        let files = FakeMyMusicFiles()
        let store = MyMusicTransferStore(repository: repository, files: files)

        await store.preparePreferencesExport()

        XCTAssertEqual(store.state, .exportPreview)
        XCTAssertEqual(store.preferencesExportPreview?.pendingChanges.count, 1)
        XCTAssertEqual(store.preferencesExportPreview?.items.first?.title, track.title)
        XCTAssertEqual(store.preferencesExportPreview?.items.first?.favorite, true)
        XCTAssertNil(files.writtenData)

        store.cancelPreferencesExport()
        XCTAssertEqual(store.state, .idle)
        let pendingAfterCancel = try await repository.loadPendingMyMusicPreferenceExports()
        XCTAssertEqual(pendingAfterCancel.count, 1)

        await store.preparePreferencesExport()
        await store.confirmPreferencesExport()

        XCTAssertEqual(store.state, .completed)
        let document = try MyMusicJSONCodec.decodePreferences(XCTUnwrap(files.writtenData))
        XCTAssertEqual(document.tracks.map(\.trackId), [externalID])
        let pendingAfterWrite = try await repository.loadPendingMyMusicPreferenceExports()
        XCTAssertTrue(pendingAfterWrite.isEmpty)
    }

    func testPlaylistApplyRunsRefreshHookAfterDatabaseCommit() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let track = try await fixture.insertTrack(repository: repository)
        let externalID = UUID()
        try await repository.saveMyMusicTrackLinks([fixture.link(track, externalID: externalID)])
        let recorder = AppliedKindsRecorder()
        let store = MyMusicTransferStore(
            repository: repository, files: FakeMyMusicFiles()
        ) { kind in
            recorder.kinds.append(kind)
        }
        let data = try MyMusicJSONExportService().exportPlaylists([
            MyMusicPlaylistRecord(
                playlistID: UUID(), name: "Imported", createdAt: fixture.now, updatedAt: fixture.now,
                tracks: [MyMusicPlaylistTrackRecord(trackID: externalID, title: track.title)]
            )
        ])

        await store.prepareImport(.playlists, data: data)
        await store.applyImport()

        XCTAssertEqual(recorder.kinds, [.playlists])
        let playlists = try await repository.loadPlaylists()
        XCTAssertEqual(playlists.first?.name, "Imported")
    }

    func testStatusStoreShowsBothTrackIDsSnapshotAndUnlinkedRows() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let linked = try await fixture.insertTrack(repository: repository, name: "linked.mp3", title: "Linked")
        let unlinked = try await fixture.insertTrack(repository: repository, name: "unlinked.mp3", title: "Unlinked")
        let externalID = UUID()
        let library = try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: externalID, title: linked.title, artist: linked.artist ?? "",
                album: linked.album, duration: linked.duration, playCount: 7,
                relativePath: linked.relativePath, fileSize: linked.fileSize
            )
        ])
        _ = try await MyMusicPersistenceService(repository: repository).importLibrary(library)
        let store = MyMusicStatusStore(repository: repository)

        await store.load()

        XCTAssertEqual(store.rows.count, 2)
        XCTAssertEqual(store.linkedCount, 1)
        XCTAssertEqual(store.unlinkedCount, 1)
        let linkedRow = try XCTUnwrap(store.rows.first { $0.id == linked.id })
        XCTAssertEqual(linkedRow.myMusicTrackID, externalID)
        XCTAssertEqual(linkedRow.id, linked.id)
        XCTAssertEqual(linkedRow.myMusicPlayCount, 7)
        XCTAssertTrue(linkedRow.isLibraryJSONExportable)
        store.filter = .unlinked
        XCTAssertEqual(store.visibleRows.map(\.id), [unlinked.id])
        store.filter = .all
        store.query = externalID.uuidString
        XCTAssertEqual(store.visibleRows.map(\.id), [linked.id])
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
        XCTAssertEqual(MyMusicDocumentKind.playlists.fileName, "MyMusic-Playlists.json")
    }

    func testDeveloperEditorChangesIndividualFieldsAndWritesValidatedJSON() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let externalID = UUID()
        let input = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: externalID, playbackPreference: 4, favorite: false)
        ], exportedAt: fixture.now)
        let files = FakeMyMusicFiles(inputData: input)
        let store = MyMusicJSONEditorStore(repository: repository, files: files)
        store.changeKind(to: .preferences)

        await store.openExistingFile()

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.selectedRecordID, 0)
        let preference = try XCTUnwrap(store.selectedFields.first { $0.path == "playbackPreference" })
        let favorite = try XCTUnwrap(store.selectedFields.first { $0.path == "favorite" })
        store.update(preference, text: "8")
        store.update(favorite, boolean: true)
        await store.save()

        let output = try XCTUnwrap(files.writtenData)
        let decoded = try MyMusicJSONCodec.decodePreferences(output)
        XCTAssertEqual(decoded.tracks.first?.playbackPreference, 8)
        XCTAssertEqual(decoded.tracks.first?.favorite, true)
        XCTAssertEqual(files.requestedFileName, MyMusicJSONCodec.preferencesFileName)
    }

    func testFeatureEditorValidatesEditsAndNeverWritesLibrary() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let record = FeatureRecord(id: UUID(), trackID: UUID(), title: "Feature song", artist: "Artist",
            sourceIdentity: FeatureSourceIdentity(relativePath: "song.flac", fileSize: 100, duration: 120),
            analysisVersion: 1, analyzedAt: fixture.now, importedAt: fixture.now,
            features: FeatureValues(values: ["vocal": 0.8, "instrumental": 0.2]),
            sourceFormat: "test", sourceFileName: "test.json")
        let files = FakeMyMusicFiles()
        let store = MyMusicJSONEditorStore(repository: repository, files: files)
        store.changeFeatureMode(true)
        await store.createFeatures([record])
        XCTAssertEqual(store.records.count, 1)
        let vocal = try XCTUnwrap(store.selectedFields.first { $0.path == "features.vocal" })
        store.update(vocal, text: "0.6")
        await store.save()
        let decoded = try FeatureCodec.decode(XCTUnwrap(files.writtenData), fileName: "test.json")
        XCTAssertEqual(decoded.first?.features.values["vocal"], 0.6)
        XCTAssertEqual(decoded.first?.trackID, record.trackID)
        XCTAssertEqual(files.requestedFileName, "track_features.json")
        let context = try await repository.loadMyMusicMatchContext()
        XCTAssertTrue(context.tracks.isEmpty)
        files.writtenData = nil
        store.update(vocal, text: "9")
        await store.save()
        XCTAssertNil(files.writtenData)
        XCTAssertNotNil(store.errorMessage)
        store.changeFeatureMode(false)
        XCTAssertFalse(store.hasDocument)
    }

    func testDeveloperEditorRejectsInvalidNumberBeforeWriting() async throws {
        let fixture = try TransferFixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let input = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: UUID(), playbackPreference: 4, favorite: false)
        ], exportedAt: fixture.now)
        let files = FakeMyMusicFiles(inputData: input)
        let store = MyMusicJSONEditorStore(repository: repository, files: files)
        store.changeKind(to: .preferences)
        await store.openExistingFile()
        let preference = try XCTUnwrap(store.selectedFields.first { $0.path == "playbackPreference" })

        store.update(preference, text: "not-a-number")
        await store.save()

        XCTAssertNil(files.writtenData)
        XCTAssertTrue(store.errorMessage?.contains("有効な数値") == true)
    }
}

@MainActor
private final class AppliedKindsRecorder {
    var kinds: [MyMusicDocumentKind] = []
}

@MainActor
private final class FakeMyMusicFiles: MyMusicFileServicing {
    var requestedFileName: String?
    var writtenData: Data?
    var inputData: Data?
    let output = URL(fileURLWithPath: "/tmp/MyMusic-Test.json")

    init(inputData: Data? = nil) { self.inputData = inputData }

    func chooseImportURL() -> URL? { inputData == nil ? nil : output }
    func chooseExportURL(defaultFileName: String) -> URL? {
        requestedFileName = defaultFileName; return output
    }
    func read(from url: URL) throws -> Data { inputData ?? Data() }
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

    func localEvent(trackID: UUID, id: String, playedAt: Date? = nil) -> LocalMyMusicPlaybackEvent {
        LocalMyMusicPlaybackEvent(
            eventID: id, homeStereoTrackID: trackID, playedAt: playedAt ?? now,
            playDuration: 10, trackDuration: 60, completed: false, skipped: false,
            playSource: .library, selectionType: .manual
        )
    }
}
