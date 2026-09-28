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

    func testLibraryImportPersistsAuthoritativePlayCountsForMatchedAndUnmatchedTracks() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let matchedID = UUID(), unmatchedID = UUID()
        let track = fixture.track(title: "Matched", artist: "Artist", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([track], into: repository)
        let importedAt = Date(timeIntervalSince1970: 500)
        let lastPlayedAt = Date(timeIntervalSince1970: 400)
        let data = try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: matchedID, title: "Matched", artist: "Artist", album: "Album",
                duration: 60, playCount: 12, lastPlayedAt: lastPlayedAt
            ),
            MyMusicTrackRecord(
                trackID: unmatchedID, title: "Missing", artist: "Other", album: "Elsewhere",
                duration: 60, playCount: 3, lastPlayedAt: lastPlayedAt
            ),
        ])

        _ = try await MyMusicPersistenceService(
            repository: repository, clock: { importedAt }
        ).importLibrary(data)
        let context = try await repository.loadAnalyticsContext()

        XCTAssertEqual(context.myMusicPlayCounts.count, 2)
        XCTAssertEqual(context.myMusicPlayCounts.reduce(0) { $0 + $1.playCount }, 15)
        XCTAssertEqual(
            context.myMusicPlayCounts.first(where: { $0.myMusicTrackID == matchedID })?.homeStereoTrackID,
            track.id
        )
        XCTAssertNil(context.myMusicPlayCounts.first(where: { $0.myMusicTrackID == unmatchedID })?.homeStereoTrackID)
        XCTAssertEqual(context.myMusicPlayCounts.first?.importedAt, importedAt)
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

    func testRelativePathMatchPrecedesFingerprintAndUsesMyMusicTrackIDAsExternalIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let externalID = UUID()
        let fingerprint = String(repeating: "d", count: 64)
        let pathTrack = fixture.track(
            relativePath: "Artist/Café/Song.flac", title: "Path", artist: "A", album: "One"
        )
        let fingerprintTrack = fixture.track(
            relativePath: "Elsewhere/Song.flac", title: "Fingerprint", artist: "B", album: "Two",
            fingerprint: fingerprint
        )
        let record = MyMusicTrackRecord(
            trackID: externalID, title: "Different", artist: "X", album: "Y", duration: 60,
            audioFingerprint: fingerprint, relativePath: "Artist/Cafe\u{301}/Song.flac", fileSize: 1_000
        )

        let match = MyMusicLibraryMatcher.match(
            [record], tracks: [fingerprintTrack, pathTrack], links: [], matchedAt: .now
        )

        XCTAssertEqual(match.result.newlyLinked, 1)
        XCTAssertEqual(match.result.items.first?.homeStereoTrackID, pathTrack.id)
        XCTAssertEqual(match.result.items.first?.matchMethod, .relativePath)
        XCTAssertEqual(match.linksToSave.first?.myMusicTrackID, externalID)
        XCTAssertEqual(match.linksToSave.first?.homeStereoTrackID, pathTrack.id)
    }

    func testRelativePathConflictDoesNotFallBackToFingerprintOrMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let fingerprint = String(repeating: "e", count: 64)
        let pathTrack = fixture.track(
            relativePath: "Artist/Album/Song.flac", title: "Song", artist: "A", album: "Album"
        )
        let fingerprintTrack = fixture.track(
            relativePath: "Moved/Song.flac", title: "Song", artist: "A", album: "Album",
            fingerprint: fingerprint
        )
        let record = MyMusicTrackRecord(
            trackID: UUID(), title: "Song", artist: "A", album: "Album", duration: 60,
            audioFingerprint: fingerprint, relativePath: pathTrack.relativePath, fileSize: 999
        )

        let match = MyMusicLibraryMatcher.match(
            [record], tracks: [pathTrack, fingerprintTrack], links: [], matchedAt: .now
        )

        XCTAssertEqual(match.result.unmatched, 1)
        XCTAssertTrue(match.linksToSave.isEmpty)
        XCTAssertEqual(match.result.items.first?.matchMethod, .relativePath)
    }

    func testMissingRelativePathCandidateFallsBackToUniqueFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let fingerprint = String(repeating: "f", count: 64)
        let movedTrack = fixture.track(
            relativePath: "New/Location/Song.flac", title: "Song", artist: "A", album: "Album",
            fingerprint: fingerprint
        )
        let record = MyMusicTrackRecord(
            trackID: UUID(), title: "Old", artist: "X", album: "Y", duration: 60,
            audioFingerprint: fingerprint, relativePath: "Old/Location/Song.flac", fileSize: 1_000
        )

        let match = MyMusicLibraryMatcher.match([record], tracks: [movedTrack], links: [], matchedAt: .now)

        XCTAssertEqual(match.result.newlyLinked, 1)
        XCTAssertEqual(match.result.items.first?.homeStereoTrackID, movedTrack.id)
        XCTAssertEqual(match.result.items.first?.matchMethod, .fingerprint)
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
        XCTAssertEqual(match.result.conflicts, 1)
        XCTAssertEqual(match.linksToSave.count, 1)
    }

    func testDuplicateRelativePathIsAmbiguousAndSavedCanonicalIDHasPriority() throws {
        let externalID = UUID()
        let first = Track(
            libraryFolderID: UUID(), relativePath: "Artist/Album/Song.flac",
            url: URL(fileURLWithPath: "/Mac-A/Music/Artist/Album/Song.flac"),
            fileSize: 1_000, title: "Song", artist: "A", album: "Album", duration: 60
        )
        let second = Track(
            libraryFolderID: UUID(), relativePath: "Artist/Album/Song.flac",
            url: URL(fileURLWithPath: "/Mac-B/Music/Artist/Album/Song.flac"),
            fileSize: 1_000, title: "Song", artist: "A", album: "Album", duration: 60
        )
        let record = MyMusicTrackRecord(
            trackID: externalID, title: "Song", artist: "A", album: "Album", duration: 60,
            relativePath: "Artist/Album/Song.flac", fileSize: 1_000
        )
        let ambiguous = MyMusicLibraryMatcher.match([record], tracks: [first, second], links: [], matchedAt: .now)
        XCTAssertEqual(ambiguous.result.ambiguous, 1)
        XCTAssertTrue(ambiguous.linksToSave.isEmpty)

        let saved = MyMusicTrackLink(
            homeStereoTrackID: second.id, myMusicTrackID: externalID,
            relativePath: second.relativePath, fileSize: second.fileSize, duration: second.duration,
            matchedAt: .distantPast, matchMethod: .manual, source: .manual
        )
        let exact = MyMusicLibraryMatcher.match([record], tracks: [first, second], links: [saved], matchedAt: .now)
        XCTAssertEqual(exact.result.exactTrackID, 1)
        XCTAssertEqual(exact.result.items.first?.homeStereoTrackID, second.id)
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

    func testPreferencesExportUsesCurrentMacFavoritesAndGoodBadWithCanonicalIDs() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let now = Date(timeIntervalSince1970: 1_000)
        let firstID = UUID(), secondID = UUID()
        let first = fixture.track(relativePath: "first.flac", title: "First", artist: "A", album: "Album")
        let second = fixture.track(relativePath: "second.flac", title: "Second", artist: "A", album: "Album")
        let unlinked = fixture.track(relativePath: "unlinked.flac", title: "Unlinked", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([first, second, unlinked], into: repository)
        try await repository.saveMyMusicTrackLinks([
            fixture.link(home: first, externalID: firstID),
            fixture.link(home: second, externalID: secondID),
        ])
        let imported = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: firstID, playbackPreference: 4, favorite: true)
        ], exportedAt: now)
        _ = try await MyMusicPersistenceService(repository: repository).importPreferences(imported)

        try await repository.deleteFavorite(trackID: first.id)
        try await repository.saveTrackPreference(
            TrackPreference(trackID: first.id, playbackPreference: -3, updatedAt: now)
        )
        try await repository.saveFavorite(Favorite(trackID: second.id, addedAt: now))
        try await repository.saveTrackPreference(
            TrackPreference(trackID: second.id, playbackPreference: 2, updatedAt: now)
        )
        try await repository.saveFavorite(Favorite(trackID: unlinked.id, addedAt: now))

        let data = try await MyMusicPersistenceService(repository: repository)
            .exportPreferences(exportedAt: now)
        let document = try MyMusicJSONCodec.decodePreferences(data)
        let values = Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.trackId, $0) })

        XCTAssertEqual(Set(values.keys), [firstID, secondID])
        XCTAssertEqual(values[firstID]?.favorite, false)
        XCTAssertEqual(values[firstID]?.playbackPreference, -3)
        XCTAssertEqual(values[secondID]?.favorite, true)
        XCTAssertEqual(values[secondID]?.playbackPreference, 2)
    }

    func testPreferencesExportIncludesOnlyMacChangesAndAcknowledgesExactPreviewVersion() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let now = Date(timeIntervalSince1970: 1_000)
        let appOnlyID = UUID(), macID = UUID()
        let appOnly = fixture.track(relativePath: "app.flac", title: "App", artist: "A", album: "Album")
        let mac = fixture.track(relativePath: "mac.flac", title: "Mac", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([appOnly, mac], into: repository)
        try await repository.saveMyMusicTrackLinks([
            fixture.link(home: appOnly, externalID: appOnlyID),
            fixture.link(home: mac, externalID: macID),
        ])
        let service = MyMusicPersistenceService(repository: repository)
        let fromApp = try MyMusicJSONExportService().exportPreferences([
            MyMusicPreferenceRecord(trackID: appOnlyID, playbackPreference: 5, favorite: true),
            MyMusicPreferenceRecord(trackID: macID, playbackPreference: 0, favorite: false),
        ], exportedAt: now)
        _ = try await service.importPreferences(fromApp)
        let pendingAfterImport = try await repository.loadPendingMyMusicPreferenceExports()
        XCTAssertTrue(pendingAfterImport.isEmpty)

        try await repository.saveTrackPreference(
            TrackPreference(trackID: mac.id, playbackPreference: 2, updatedAt: now)
        )
        let first = try await service.preparePreferencesExport(exportedAt: now)
        let firstDocument = try MyMusicJSONCodec.decodePreferences(first.data)
        XCTAssertEqual(firstDocument.tracks.map(\.trackId), [macID])
        XCTAssertEqual(firstDocument.tracks.first?.playbackPreference, 2)

        try await repository.saveTrackPreference(
            TrackPreference(trackID: mac.id, playbackPreference: 3, updatedAt: now.addingTimeInterval(1))
        )
        try await service.acknowledgePreferencesExport(first.pendingChanges)
        let second = try await service.preparePreferencesExport(exportedAt: now.addingTimeInterval(1))
        let secondDocument = try MyMusicJSONCodec.decodePreferences(second.data)
        XCTAssertEqual(secondDocument.tracks.map(\.trackId), [macID])
        XCTAssertEqual(secondDocument.tracks.first?.playbackPreference, 3)

        _ = try await service.importPreferences(fromApp)
        let pendingAfterSecondImport = try await repository.loadPendingMyMusicPreferenceExports()
        XCTAssertTrue(pendingAfterSecondImport.isEmpty)
        let current = Dictionary(uniqueKeysWithValues: try await repository.loadCurrentMyMusicPreferenceRecords().map {
            ($0.trackID, $0)
        })
        XCTAssertEqual(current[appOnlyID]?.playbackPreference, 5)
        XCTAssertEqual(current[macID]?.playbackPreference, 0)
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

    func testPlaylistImportIsIdempotentPartialAndExportNeverUsesLocalTrackID() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let linked = fixture.track(relativePath: "linked.flac", title: "Linked", artist: "A", album: "Album")
        let localOnly = fixture.track(relativePath: "local.flac", title: "Local", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([linked, localOnly], into: repository)
        let canonicalID = UUID(), unresolvedID = UUID(), playlistID = UUID()
        try await repository.saveMyMusicTrackLinks([fixture.link(home: linked, externalID: canonicalID)])
        let record = MyMusicPlaylistRecord(
            playlistID: playlistID, name: "MyMusic", createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20), kind: "work", tags: ["tag"], tracks: [
                MyMusicPlaylistTrackRecord(trackID: canonicalID),
                MyMusicPlaylistTrackRecord(trackID: unresolvedID)
            ]
        )
        let data = try MyMusicJSONExportService().exportPlaylists([record])
        let service = MyMusicPersistenceService(repository: repository)
        let first = try await service.importPlaylists(data)
        let second = try await service.importPlaylists(data)
        XCTAssertEqual(first.addedPlaylists, 1)
        XCTAssertEqual(first.importedTracks, 1)
        XCTAssertEqual(first.unresolvedTrackIDs, [unresolvedID])
        XCTAssertEqual(second.unchangedPlaylists, 1)
        let imported = try await repository.loadPlaylists()
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.myMusicPlaylistID, playlistID)
        XCTAssertEqual(imported.first?.playlistKind, .work)
        XCTAssertEqual(imported.first?.items.map(\.trackID), [linked.id])

        try await repository.savePlaylist(Playlist(
            name: "Local export", items: [PlaylistItem(trackID: linked.id), PlaylistItem(trackID: localOnly.id)]
        ))
        let exported = try await service.exportPlaylists()
        XCTAssertEqual(exported.totalTracks, 3)
        XCTAssertEqual(exported.exportedTracks, 2)
        XCTAssertEqual(exported.missingMyMusicID, 1)
        let output = try MyMusicJSONCodec.decodePlaylists(exported.data)
        XCTAssertEqual(output.playlists.first(where: { $0.playlistID == playlistID })?.kind, "work")
        XCTAssertTrue(output.playlists.flatMap(\.tracks).allSatisfy { $0.trackID == canonicalID })
        XCTAssertFalse(output.playlists.flatMap(\.tracks).contains { $0.trackID == linked.id || $0.trackID == localOnly.id })
    }

    func testSnapshotRemovalMarksLinkInactiveAndKeepsHistoryAndPlaylistReferences() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let one = fixture.track(relativePath: "one.flac", title: "One", artist: "A", album: "Album")
        let two = fixture.track(relativePath: "two.flac", title: "Two", artist: "A", album: "Album")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([one, two], into: repository)
        let oneID = UUID(), twoID = UUID()
        try await repository.saveMyMusicTrackLinks([
            fixture.link(home: one, externalID: oneID), fixture.link(home: two, externalID: twoID)
        ])
        let playlist = Playlist(name: "Keep", items: [PlaylistItem(trackID: two.id)])
        try await repository.savePlaylist(playlist)
        let event = PlaybackEvent(trackID: two.id, startedAt: .now, playedSeconds: 12, outcome: .stopped)
        try await repository.savePlaybackEvent(event)
        let snapshot = try libraryJSON(
            id: oneID, title: one.title, artist: one.artist ?? "", album: one.album ?? "",
            relativePath: one.relativePath, fileSize: one.fileSize
        )
        let result = try await MyMusicPersistenceService(repository: repository).importLibrary(snapshot)
        XCTAssertEqual(result.missingFromSnapshot, 1)
        let links = try await repository.loadMyMusicTrackLinks()
        XCTAssertEqual(links.first { $0.myMusicTrackID == twoID }?.isInCurrentSnapshot, false)
        let playlists = try await repository.loadPlaylists()
        let events = try await repository.loadPlaybackEvents()
        XCTAssertEqual(playlists.first?.items.first?.trackID, two.id)
        XCTAssertEqual(events.first?.id, event.id)
    }

    func testPlaylistTransactionRollsBackAfterDuplicateCanonicalPlaylistID() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let playlistID = UUID()
        let values = ["First", "Duplicate"].map {
            MyMusicPlaylistRecord(
                playlistID: playlistID, name: $0, createdAt: .now, updatedAt: .now, tracks: []
            )
        }
        do {
            _ = try await repository.mergeMyMusicPlaylists(values)
            XCTFail("duplicate playlistID must fail")
        } catch {}
        let playlists = try await repository.loadPlaylists()
        XCTAssertTrue(playlists.isEmpty)
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

    func testSchemaNineMigratesPlaylistAndSnapshotColumnsWithoutDroppingPlaylist() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let playlistID = UUID()
        do {
            let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
            try await repository.savePlaylist(Playlist(id: playlistID, name: "Keep"))
        }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(fixture.database.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, """
            PRAGMA legacy_alter_table = ON;
            ALTER TABLE playlists RENAME TO playlists_v10;
            CREATE TABLE playlists(
                id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL
            );
            INSERT INTO playlists(id, name, created_at, updated_at)
                SELECT id, name, created_at, updated_at FROM playlists_v10;
            DROP TABLE playlists_v10;
            ALTER TABLE mymusic_track_links DROP COLUMN first_seen_at;
            ALTER TABLE mymusic_track_links DROP COLUMN last_seen_at;
            ALTER TABLE mymusic_track_links DROP COLUMN in_current_snapshot;
            PRAGMA user_version = 9;
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let migrated = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let version = try await migrated.schemaVersion()
        XCTAssertEqual(version, SQLiteLibraryRepository.currentSchemaVersion)
        let playlists = try await migrated.loadPlaylists()
        XCTAssertEqual(playlists.first?.id, playlistID)
        XCTAssertEqual(playlists.first?.kind, "regular")
        XCTAssertEqual(playlists.first?.tags, [])
    }

    func testAnalyticsEventIsIdempotentAndResetPreservesPreferencesFavoritesAndPlaylists() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let track = fixture.track(title: "Keep Settings", artist: "A", album: "B")
        let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
        try await fixture.insert([track], into: repository)
        try await repository.saveFavorite(Favorite(trackID: track.id))
        try await repository.saveTrackPreference(TrackPreference(trackID: track.id, playbackPreference: 5))
        let playlist = Playlist(name: "Keep", items: [PlaylistItem(trackID: track.id)])
        try await repository.savePlaylist(playlist)
        let event = LocalMyMusicPlaybackEvent(
            eventID: "mac-fixed", homeStereoTrackID: track.id,
            playedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 140),
            playDuration: 40, trackDuration: 60, completed: false, skipped: true,
            playSource: .playlist, selectionType: .userAdvanced, endKind: .userSkipped
        )

        let firstInsert = try await repository.appendLocalMyMusicPlaybackEvent(event)
        let duplicateInsert = try await repository.appendLocalMyMusicPlaybackEvent(event)
        let storedEvents = try await repository.loadMyMusicPlaybackEvents()
        XCTAssertTrue(firstInsert)
        XCTAssertFalse(duplicateInsert)
        XCTAssertEqual(storedEvents.count, 1)
        var analyticsDatabase: OpaquePointer?
        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        XCTAssertEqual(sqlite3_open(fixture.database.path, &analyticsDatabase), SQLITE_OK)
        var summaryStatement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(
            analyticsDatabase,
            "SELECT play_count, skip_count FROM playback_track_summaries WHERE home_track_id = ?",
            -1, &summaryStatement, nil
        ), SQLITE_OK)
        sqlite3_bind_text(summaryStatement, 1, track.id.uuidString, -1, sqliteTransient)
        XCTAssertEqual(sqlite3_step(summaryStatement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(summaryStatement, 0), 1)
        XCTAssertEqual(sqlite3_column_int(summaryStatement, 1), 1)
        sqlite3_finalize(summaryStatement)
        XCTAssertEqual(sqlite3_prepare_v2(
            analyticsDatabase,
            "SELECT session_count FROM playback_source_summaries WHERE home_track_id = ? AND source = 'playlist'",
            -1, &summaryStatement, nil
        ), SQLITE_OK)
        sqlite3_bind_text(summaryStatement, 1, track.id.uuidString, -1, sqliteTransient)
        XCTAssertEqual(sqlite3_step(summaryStatement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(summaryStatement, 0), 1)
        sqlite3_finalize(summaryStatement)
        sqlite3_close(analyticsDatabase)
        try await repository.deleteAnalyticsHistory(trackID: track.id)

        let context = try await repository.loadAnalyticsContext()
        XCTAssertTrue(context.events.isEmpty)
        XCTAssertEqual(context.favorites.map(\.trackID), [track.id])
        XCTAssertEqual(context.preferences.first?.playbackPreference, 5)
        XCTAssertEqual(context.playlists.first?.id, playlist.id)
    }

    func testRemovingLibraryTrackKeepsPlaybackEventAsUnresolvedHistory() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let track = fixture.track(title: "Removed", artist: "A", album: "B")
        do {
            let repository = try SQLiteLibraryRepository(databaseURL: fixture.database)
            try await fixture.insert([track], into: repository)
            _ = try await repository.appendLocalMyMusicPlaybackEvent(LocalMyMusicPlaybackEvent(
                eventID: "mac-orphan", homeStereoTrackID: track.id,
                playedAt: Date(timeIntervalSince1970: 100), endedAt: Date(timeIntervalSince1970: 130),
                playDuration: 30, trackDuration: 60, completed: false, skipped: false,
                playSource: .library, selectionType: .manual
            ))
            try await repository.removeFolder(id: fixture.folderID)
            let remainingTracks = try await repository.loadTracks(folderID: nil)
            XCTAssertTrue(remainingTracks.isEmpty)
        }

        let reopened = try SQLiteLibraryRepository(databaseURL: fixture.database)
        let context = try await reopened.loadAnalyticsContext()
        XCTAssertEqual(context.events.map(\.eventID), ["mac-orphan"])
        let snapshot = AnalyticsService.makeSnapshot(context: context)
        XCTAssertEqual(snapshot.recentEvents.first?.title, "不明な曲")
    }

    private func libraryJSON(
        id: UUID, title: String, artist: String, album: String, fingerprint: String? = nil,
        relativePath: String? = nil, fileSize: Int64? = nil
    ) throws -> Data {
        try MyMusicJSONExportService().exportLibrary([
            MyMusicTrackRecord(
                trackID: id, title: title, artist: artist, album: album,
                duration: 60, format: "FLAC", audioFingerprint: fingerprint,
                relativePath: relativePath, fileSize: fileSize
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
