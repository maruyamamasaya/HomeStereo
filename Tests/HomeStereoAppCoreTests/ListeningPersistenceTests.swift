import Foundation
import XCTest
@testable import HomeStereoAppCore

final class ListeningPersistenceTests: XCTestCase {
    func testFavoritesPersistMissingTrackReferencesAndResetIndependently() async throws {
        let (repository, cleanup) = try makeRepository()
        defer { cleanup() }
        let trackID = UUID()
        try await repository.saveFavorite(Favorite(trackID: trackID, addedAt: Date(timeIntervalSince1970: 10)))
        try await repository.savePlaybackEvent(PlaybackEvent(trackID: trackID, playedSeconds: 4))

        let favorites = try await repository.loadFavorites()
        XCTAssertEqual(favorites.map(\.trackID), [trackID])
        try await repository.deleteAllFavorites()
        let resetFavorites = try await repository.loadFavorites()
        let remainingEvents = try await repository.loadPlaybackEvents()
        XCTAssertTrue(resetFavorites.isEmpty)
        XCTAssertEqual(remainingEvents.count, 1)
    }

    func testPlaybackEventUpsertDoesNotDuplicateSamePlayback() async throws {
        let (repository, cleanup) = try makeRepository()
        defer { cleanup() }
        let id = UUID(), trackID = UUID()
        try await repository.savePlaybackEvent(PlaybackEvent(id: id, trackID: trackID, playedSeconds: 2))
        try await repository.savePlaybackEvent(PlaybackEvent(id: id, trackID: trackID, playedSeconds: 8, outcome: .completed))

        let events = try await repository.loadPlaybackEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].playedSeconds, 8)
        XCTAssertEqual(events[0].outcome, .completed)
    }

    private func makeRepository() throws -> (SQLiteLibraryRepository, () -> Void) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3")), { try? FileManager.default.removeItem(at: root) })
    }
}
