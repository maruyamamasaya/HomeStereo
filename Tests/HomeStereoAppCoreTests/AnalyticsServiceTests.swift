import Foundation
import XCTest
@testable import HomeStereoAppCore

final class AnalyticsServiceTests: XCTestCase {
    func testSnapshotTotalsRankingPeriodsSourcesAndRatings() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let top = track(title: "Top", artist: "Artist A")
        let other = track(title: "Other", artist: "Artist B")
        let events = [
            event("one", track: top, at: now.addingTimeInterval(-60), listened: 30, source: .library, selection: .manual),
            event("two", track: top, at: now.addingTimeInterval(-86_400 * 3), listened: 50, source: .playlist, selection: .automatic, completed: true),
            event("three", track: other, at: now.addingTimeInterval(-86_400 * 10), listened: 5, source: .search, selection: .userAdvanced, skipped: true),
        ]
        let snapshot = AnalyticsService.makeSnapshot(
            context: AnalyticsContext(
                tracks: [other, top], events: events,
                favorites: [Favorite(trackID: top.id)],
                preferences: [TrackPreference(trackID: top.id, playbackPreference: 5)],
                playlists: []
            ),
            now: now, calendar: calendar
        )

        XCTAssertEqual(snapshot.overview.playCount, 2)
        XCTAssertEqual(snapshot.overview.manualPlayCount, 1)
        XCTAssertEqual(snapshot.overview.automaticPlayCount, 1)
        XCTAssertEqual(snapshot.overview.userAdvancedPlayCount, 1)
        XCTAssertEqual(snapshot.overview.todayPlayCount, 1)
        XCTAssertEqual(snapshot.overview.last7DaysPlayCount, 2)
        XCTAssertEqual(snapshot.overview.last30DaysPlayCount, 2)
        XCTAssertEqual(snapshot.topTracks.first?.trackID, top.id)
        XCTAssertEqual(snapshot.topTracks.first?.playCount, 2)
        XCTAssertEqual(snapshot.historyDays.count, 3)
        XCTAssertEqual(snapshot.ratings.first(where: { $0.group == .good })?.trackCount, 1)
        XCTAssertEqual(snapshot.ratings.first(where: { $0.group == .unset })?.trackCount, 1)
        XCTAssertTrue(snapshot.recentEvents.contains { $0.startSource == .playlist })
        XCTAssertTrue(snapshot.recentEvents.allSatisfy { $0.playbackPlatform == .mac })
    }

    func testPlaybackPlatformDistinguishesMyMusicAppAndMacWithoutChangingJSONContract() {
        XCTAssertEqual(AnalyticsPlaybackPlatform("macOS"), .mac)
        XCTAssertEqual(AnalyticsPlaybackPlatform("iOS"), .app)
        XCTAssertEqual(AnalyticsPlaybackPlatform("iPhone"), .app)
        XCTAssertEqual(AnalyticsPlaybackPlatform("future-device"), .other("future-device"))
        XCTAssertEqual(AnalyticsPlaybackPlatform(""), .other(""))
    }

    func testUnknownDurationAndEmptyDataKeepUnknownSeparateFromZero() throws {
        let value = track(title: "Unknown")
        let unknown = event("unknown", track: value, at: .now, listened: 29.9, duration: 0)
        let snapshot = AnalyticsService.makeSnapshot(context: AnalyticsContext(
            tracks: [value], events: [unknown], favorites: [], preferences: [], playlists: []
        ))

        XCTAssertEqual(snapshot.overview.playCount, 0)
        XCTAssertNil(snapshot.allTracks.first?.completionRate)
        XCTAssertFalse(MyMusicPlaybackPolicy.isCompleted(listenedSeconds: 100, trackDuration: 0))
        XCTAssertFalse(MyMusicPlaybackPolicy.isCompleted(listenedSeconds: 100, trackDuration: .nan))
        XCTAssertFalse(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 29.9, trackDuration: 0))
        XCTAssertTrue(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 30, trackDuration: 0))
        XCTAssertTrue(MyMusicPlaybackPolicy.isEarlySkip(skipped: true, listenedSeconds: 30))
        XCTAssertFalse(MyMusicPlaybackPolicy.isEarlySkip(skipped: true, listenedSeconds: 30.1))

        let empty = AnalyticsService.makeSnapshot(context: AnalyticsContext(
            tracks: [], events: [], favorites: [], preferences: [], playlists: []
        ))
        XCTAssertEqual(empty.overview.playCount, 0)
        XCTAssertTrue(empty.recentEvents.isEmpty)
    }

    func testMyMusicLibraryPlayCountsAreAuthoritativeIncludingUnmatchedTracks() throws {
        let linked = track(title: "Linked")
        let localOnly = track(title: "Local Only")
        let eventDate = Date(timeIntervalSince1970: 200)
        let importedAt = Date(timeIntervalSince1970: 300)
        let snapshot = AnalyticsService.makeSnapshot(context: AnalyticsContext(
            tracks: [linked, localOnly],
            events: [
                event("linked-event", track: linked, at: eventDate, listened: 30),
                event("local-event", track: localOnly, at: eventDate, listened: 30),
            ],
            favorites: [], preferences: [], playlists: [],
            myMusicPlayCounts: [
                PersistedMyMusicPlayCount(
                    myMusicTrackID: UUID(), homeStereoTrackID: linked.id,
                    playCount: 12, lastPlayedAt: eventDate, importedAt: importedAt
                ),
                PersistedMyMusicPlayCount(
                    myMusicTrackID: UUID(), playCount: 3,
                    lastPlayedAt: eventDate, importedAt: importedAt
                ),
            ]
        ), now: eventDate)

        XCTAssertTrue(snapshot.overview.usesMyMusicPlayCount)
        XCTAssertEqual(snapshot.overview.playCount, 15)
        XCTAssertEqual(snapshot.overview.playedTrackCount, 2)
        XCTAssertEqual(snapshot.allTracks.first(where: { $0.trackID == linked.id })?.playCount, 12)
        XCTAssertEqual(snapshot.allTracks.first(where: { $0.trackID == localOnly.id })?.playCount, 0)
        XCTAssertEqual(snapshot.overview.last30DaysPlayCount, 2)
    }

    private func track(title: String, artist: String? = nil) -> Track {
        Track(url: URL(fileURLWithPath: "/tmp/\(UUID()).flac"), title: title, artist: artist, duration: 100)
    }

    private func event(
        _ id: String, track: Track, at: Date, listened: TimeInterval,
        duration: TimeInterval = 100, source: MyMusicPlaySource = .library,
        selection: MyMusicSelectionType = .manual, completed: Bool = false, skipped: Bool = false
    ) -> PersistedMyMusicPlaybackEvent {
        PersistedMyMusicPlaybackEvent(
            eventID: id, homeStereoTrackID: track.id, myMusicTrackID: nil,
            playedAt: at, endedAt: at.addingTimeInterval(listened),
            playDuration: listened, trackDuration: duration, completed: completed,
            skipped: skipped, playSource: source.rawValue, selectionType: selection.rawValue,
            endKind: completed ? .natural : (skipped ? .userSkipped : .other),
            platform: "macOS", schemaVersion: 1
        )
    }
}
