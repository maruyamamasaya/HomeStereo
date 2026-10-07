import Foundation
import XCTest
@testable import HomeStereoAppCore

final class AnalyticsServiceTests: XCTestCase {
    func testArtistAndGenreRankingsAggregateAndRespectPreset() {
        func row(_ artist: String, _ genre: String, _ count: Int, _ seconds: Double) -> AnalyticsTrackSummary {
            AnalyticsTrackSummary(trackID: UUID(), title: "Fixture", artist: artist, album: "", genre: genre,
                playCount: count, sessionCount: 0, totalPlaybackDuration: seconds, lastPlayedAt: nil,
                completionRate: nil, skipRate: nil, earlySkipCount: 0, favorite: false,
                playbackPreference: nil, isAvailable: true)
        }
        let tracks = [row("A", "Rock", 3, 100), row("A", "Jazz", 2, 50),
            row("B", "Jazz", 4, 400), row("", "", 1, 20), row("Never", "Rock", 0, 0)]
        let all = AnalyticsService.rankings(tracks: tracks)
        XCTAssertEqual(all.artistsByCount.first?.name, "A")
        XCTAssertEqual(all.artistsByCount.first?.playCount, 5)
        XCTAssertEqual(all.artistsByDuration.first?.name, "B")
        XCTAssertEqual(all.artistsByDuration.first?.playbackDuration, 400)
        XCTAssertEqual(all.genresByCount.first?.name, "Jazz")
        XCTAssertEqual(all.genresByCount.first?.playCount, 6)
        XCTAssertTrue(all.artistsByCount.contains { $0.name == "アーティスト未設定" })
        XCTAssertFalse(all.artistsByCount.contains { $0.name == "Never" })
        let preset = GenreDisplayPreset(name: "Rock", enabledGenreNames: ["Rock"])
        let filtered = AnalyticsService.rankings(tracks: tracks, artistPreset: preset)
        XCTAssertEqual(filtered.artistsByCount.map(\.name), ["A"])
        XCTAssertEqual(filtered.artistsByCount.first?.playCount, 3)
        XCTAssertEqual(filtered.artistsByDuration.first?.playbackDuration, 100)
        XCTAssertEqual(filtered.genresByCount, all.genresByCount)
        let unassigned = GenreDisplayPreset(name: "未分類", enabledGenreNames: [GenreDisplayPreset.unassignedGenreID])
        XCTAssertEqual(AnalyticsService.rankings(tracks: tracks, artistPreset: unassigned).artistsByCount.first?.name, "アーティスト未設定")
        XCTAssertEqual(AnalyticsService.rankings(tracks: []).artistsByCount, [])
    }

    func testRankingsKeepCountAndDurationIndependentAndUseStableTies() {
        func row(_ artist: String, _ count: Int, _ seconds: Double) -> AnalyticsTrackSummary {
            AnalyticsTrackSummary(trackID: UUID(), title: "Fixture", artist: artist, album: "", genre: "Rock",
                playCount: count, sessionCount: 0, totalPlaybackDuration: seconds, lastPlayedAt: nil,
                completionRate: nil, skipRate: nil, earlySkipCount: 0, favorite: false,
                playbackPreference: nil, isAvailable: false)
        }
        let value = AnalyticsService.rankings(tracks: [row("B", 5, 0), row("A", 5, 0), row("C", 0, 30)])
        XCTAssertEqual(value.artistsByCount.map(\.name), ["A", "B"])
        XCTAssertEqual(value.artistsByDuration.map(\.name), ["C"])
        XCTAssertEqual(value.genresByCount.first?.playCount, 10)
    }

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

    func testCalendarKeepsHistoryBeyondRecentEventLimit() {
        let song = track(title: "Archive")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let events = (0..<620).map { event("event-\($0)", track: song, at: now.addingTimeInterval(-Double($0) * 3600), listened: 30) }
        let snapshot = AnalyticsService.makeSnapshot(context: AnalyticsContext(tracks: [song], events: events, favorites: [], preferences: [], playlists: []), now: now)
        XCTAssertEqual(snapshot.recentEvents.count, 500)
        XCTAssertEqual(snapshot.historyDays.flatMap(\.events).count, 620)
        XCTAssertTrue(snapshot.historyDays.flatMap(\.events).contains { $0.id == "event-619" })
    }

    func testVoiceHintsAndCanonicalIdentityRemainConservative() {
        XCTAssertEqual(FeatureVoiceCategory.classify(["vocal": 0.8, "instrumental": 0.2]), .vocal)
        XCTAssertEqual(FeatureVoiceCategory.classify(["vocal": 0.2, "instrumental": 0.8]), .instrumental)
        XCTAssertEqual(FeatureVoiceCategory.classify(["vocal": 0.5, "instrumental": 0.55]), .uncertain)
        XCTAssertEqual(FeatureVoiceCategory.classify(["vocal": .nan, "instrumental": 0.8]), .unavailable)
        XCTAssertEqual(FeatureVoiceCategory.classify(nil), .unavailable)
        let id = UUID()
        XCTAssertTrue(FeatureIdentityCheck.matches(featureID: id, linkedIDs: [id], canonicalHomeCount: 1))
        XCTAssertFalse(FeatureIdentityCheck.matches(featureID: id, linkedIDs: [id], canonicalHomeCount: 2))
        XCTAssertFalse(FeatureIdentityCheck.matches(featureID: id, linkedIDs: [UUID()], canonicalHomeCount: 1))
        XCTAssertFalse(FeatureIdentityCheck.matches(featureID: nil, linkedIDs: [], canonicalHomeCount: 0))
    }

    func testSelectedPeriodUsesEventsAndExcludesEndBoundary() {
        let song = track(title: "Period")
        let start = Date(timeIntervalSince1970: 1800000000)
        let interval = DateInterval(start: start, duration: 86400)
        let values = [event("before", track: song, at: start.addingTimeInterval(-1), listened: 40),
                      event("start", track: song, at: start, listened: 50),
                      event("end", track: song, at: interval.end, listened: 60)]
        let context = AnalyticsContext(tracks: [song], events: values, favorites: [], preferences: [], playlists: [])
        let snapshot = AnalyticsService.makeSnapshot(context: context, interval: interval)
        XCTAssertEqual(snapshot.overview.playCount, 1)
        XCTAssertEqual(snapshot.overview.totalPlaybackDuration, 50)
        XCTAssertEqual(snapshot.allTracks.first?.playCount, 1)
        XCTAssertEqual(AnalyticsService.events(in: AnalyticsService.makeSnapshot(context: context), interval: interval).map(\.id), ["start"])
    }

    func testMonthAndCustomPeriodsUseCalendarBoundaries() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        let previous = AnalyticsPeriod.lastMonth.interval(now: now, start: now, end: now, calendar: calendar)!
        XCTAssertEqual(calendar.component(.month, from: previous.start), 2)
        XCTAssertEqual(calendar.component(.month, from: previous.end), 3)
        let custom = AnalyticsPeriod.custom.interval(now: now, start: now, end: now, calendar: calendar)!
        XCTAssertEqual(custom.duration, 86400)
        XCTAssertNil(AnalyticsPeriod.all.interval(now: now, start: now, end: now, calendar: calendar))
    }

    func testNormalRankingExcludesWorkAndHighResolutionByMetadata() {
        let regular = track(title: "Normal")
        let work = Track(url: URL(fileURLWithPath: "/tmp/work.flac"), title: "Work", genre: "Rock;作業用BGM")
        let hi = Track(url: URL(fileURLWithPath: "/tmp/hi.flac"), title: "Hi", sampleRate: 96000, bitDepth: 24)
        XCTAssertEqual(AnalyticsService.normalTrackIDs([regular, work, hi]), [regular.id])
    }

    func testRankingPageStableArtworkSeparateMetricsAndRegularOnly() {
        let first = Track(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/one.flac"), title: "One", artist: "Artist", album: "Album", genre: "Rock;Jazz", hasArtwork: true)
        let second = Track(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/two.flac"), title: "Two", artist: "Other", album: "Album", genre: "Rock", hasArtwork: true)
        let work = Track(url: URL(fileURLWithPath: "/tmp/work.flac"), title: "Work", artist: "Work", genre: "作業用BGM")
        let hi = Track(url: URL(fileURLWithPath: "/tmp/hi.flac"), title: "Hi", genre: "ハイレゾ")
        let now = Date.now
        let snapshot = AnalyticsService.makeSnapshot(context: AnalyticsContext(tracks: [first, second, work, hi],
            events: [event("one", track: first, at: now, listened: 40),
                     event("two", track: second, at: now, listened: 90),
                     event("work", track: work, at: now, listened: 99),
                     event("hi", track: hi, at: now, listened: 99)], favorites: [], preferences: [], playlists: []))
        let album = AnalyticsService.rankingPage(summaries: snapshot.allTracks, libraryTracks: [first, second, work, hi], kind: .album)
        XCTAssertEqual(album.byCount.count, 1)
        XCTAssertEqual(album.byCount[0].playCount, 2)
        XCTAssertEqual(album.byCount[0].seconds, 130)
        XCTAssertEqual(album.byCount[0].artworkTrackID, first.id)
        let reordered = AnalyticsService.rankingPage(summaries: snapshot.allTracks.reversed(), libraryTracks: [second, first, hi, work], kind: .album)
        XCTAssertEqual(album, reordered)
        let later = AnalyticsService.makeSnapshot(context: AnalyticsContext(tracks: [first, second],
            events: [event("only-second", track: second, at: now, listened: 90)], favorites: [], preferences: [], playlists: []))
        XCTAssertEqual(AnalyticsService.rankingPage(summaries: later.allTracks, libraryTracks: [first, second], kind: .album).byCount[0].artworkTrackID, first.id)
        let genres = AnalyticsService.rankingPage(summaries: snapshot.allTracks, libraryTracks: [first, second, work, hi], kind: .genre)
        XCTAssertEqual(genres.byCount.first?.title, "Rock")
        XCTAssertEqual(genres.byCount.first?.playCount, 2)
        XCTAssertEqual(Set(genres.byCount.map(\.title)), ["Rock", "Jazz"])
    }

    func testRankingPageLimitsBothMetricsToFifty() {
        let tracks = (0..<60).map { track(title: "Song \($0)") }
        let now = Date.now
        let snapshot = AnalyticsService.makeSnapshot(context: AnalyticsContext(tracks: tracks,
            events: tracks.enumerated().map { event("event-\($0.offset)", track: $0.element, at: now, listened: Double(40 + $0.offset)) },
            favorites: [], preferences: [], playlists: []))
        let page = AnalyticsService.rankingPage(summaries: snapshot.allTracks, libraryTracks: tracks, kind: .track)
        XCTAssertEqual(page.byCount.count, 50)
        XCTAssertEqual(page.byTime.count, 50)
        XCTAssertEqual(page.byTime.first?.seconds, 99)
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
