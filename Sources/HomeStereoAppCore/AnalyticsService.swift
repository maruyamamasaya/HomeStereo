import Foundation

public enum AnalyticsService {
    public static func makeSnapshot(
        context: AnalyticsContext, now: Date = .now, calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let tracksByID = Dictionary(uniqueKeysWithValues: context.tracks.map { ($0.id, $0) })
        let favorites = Set(context.favorites.map(\.trackID))
        let preferences = Dictionary(uniqueKeysWithValues: context.preferences.map { ($0.trackID, $0.playbackPreference) })
        let events = context.events.sorted { $0.playedAt > $1.playedAt }
        let qualified = events.filter { MyMusicPlaybackPolicy.countsAsPlay(
            listenedSeconds: $0.playDuration, trackDuration: $0.trackDuration
        ) }
        let usesMyMusicPlayCount = !context.myMusicPlayCounts.isEmpty
        let myMusicCountsByTrack = Dictionary(uniqueKeysWithValues: context.myMusicPlayCounts.compactMap {
            value in value.homeStereoTrackID.map { ($0, value) }
        })
        let today = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -29, to: today) ?? today

        let overview = AnalyticsOverview(
            playCount: usesMyMusicPlayCount
                ? context.myMusicPlayCounts.reduce(0) { $0 + $1.playCount }
                : qualified.count,
            totalPlaybackDuration: events.reduce(0) { $0 + safeSeconds($1.playDuration) },
            manualPlayCount: events.count { $0.selectionType == MyMusicSelectionType.manual.rawValue },
            automaticPlayCount: events.count { $0.selectionType == MyMusicSelectionType.automatic.rawValue },
            userAdvancedPlayCount: events.count { $0.selectionType == MyMusicSelectionType.userAdvanced.rawValue },
            playedTrackCount: usesMyMusicPlayCount
                ? context.myMusicPlayCounts.count { $0.lastPlayedAt != nil }
                : Set(events.map(\.homeStereoTrackID)).count,
            favoriteTrackCount: favorites.count,
            todayPlayCount: qualified.count { $0.playedAt >= today },
            todayPlaybackDuration: events.filter { $0.playedAt >= today }.reduce(0) { $0 + safeSeconds($1.playDuration) },
            last7DaysPlayCount: qualified.count { $0.playedAt >= sevenDaysAgo },
            last30DaysPlayCount: qualified.count { $0.playedAt >= thirtyDaysAgo },
            usesMyMusicPlayCount: usesMyMusicPlayCount
        )

        let grouped = Dictionary(grouping: events, by: \.homeStereoTrackID)
        let summaries = context.tracks.map { track -> AnalyticsTrackSummary in
            summary(
                trackID: track.id, track: track, events: grouped[track.id] ?? [],
                favorite: favorites.contains(track.id), preference: preferences[track.id],
                myMusicCount: usesMyMusicPlayCount ? myMusicCountsByTrack[track.id] : nil,
                authoritativeCountMissing: usesMyMusicPlayCount && myMusicCountsByTrack[track.id] == nil
            )
        }.sorted(by: rank)

        let eventRows = events.map { event -> AnalyticsEventRow in
            let track = tracksByID[event.homeStereoTrackID]
            return AnalyticsEventRow(
                id: event.eventID, trackID: event.homeStereoTrackID,
                title: track?.title ?? "不明な曲", artist: track?.artist ?? "",
                startedAt: event.playedAt, endedAt: event.endedAt,
                listenedSeconds: safeSeconds(event.playDuration), trackDuration: event.trackDuration,
                completionRatio: event.completionRatio,
                wasFullPlayback: event.completed, wasSkipped: event.skipped,
                wasEarlySkip: MyMusicPlaybackPolicy.isEarlySkip(
                    skipped: event.skipped, listenedSeconds: event.playDuration
                ),
                startKind: MyMusicSelectionType(rawValue: event.selectionType) ?? .automatic,
                startSource: MyMusicPlaySource(rawValue: event.playSource) ?? .unknown,
                endKind: event.endKind, platform: event.platform
            )
        }

        return AnalyticsSnapshot(
            generatedAt: now, overview: overview,
            topTracks: Array(summaries.filter { $0.playCount > 0 }.prefix(10)),
            allTracks: summaries, recentEvents: Array(eventRows.prefix(500)),
            historyDays: Dictionary(grouping: eventRows, by: { calendar.startOfDay(for: $0.startedAt) })
                .map { AnalyticsHistoryDay(date: $0.key, events: $0.value) }
                .sorted { $0.date > $1.date },
            trends: makeTrends(
                tracks: context.tracks, events: events, summaries: summaries,
                now: now, calendar: calendar
            ),
            ratings: makeRatings(summaries: summaries)
        )
    }

    private static func summary(
        trackID: Track.ID, track: Track, events: [PersistedMyMusicPlaybackEvent],
        favorite: Bool, preference: Int?, myMusicCount: PersistedMyMusicPlayCount?,
        authoritativeCountMissing: Bool
    ) -> AnalyticsTrackSummary {
        let detailed = events.filter { MyMusicPlaybackPolicy.hasValidDuration($0.trackDuration) }
        let eventPlays = events.count { MyMusicPlaybackPolicy.countsAsPlay(
            listenedSeconds: $0.playDuration, trackDuration: $0.trackDuration
        ) }
        let plays = myMusicCount?.playCount ?? (authoritativeCountMissing ? 0 : eventPlays)
        return AnalyticsTrackSummary(
            trackID: trackID, title: track.title, artist: track.artist ?? "",
            album: track.album ?? "", genre: track.genre ?? "", playCount: plays,
            sessionCount: events.count,
            totalPlaybackDuration: events.reduce(0) { $0 + safeSeconds($1.playDuration) },
            lastPlayedAt: myMusicCount.map(\.lastPlayedAt) ?? events.map(\.playedAt).max(),
            completionRate: detailed.isEmpty ? nil : Double(detailed.count(where: \.completed)) / Double(detailed.count),
            skipRate: events.isEmpty ? nil : Double(events.count(where: \.skipped)) / Double(events.count),
            earlySkipCount: events.count { MyMusicPlaybackPolicy.isEarlySkip(
                skipped: $0.skipped, listenedSeconds: $0.playDuration
            ) },
            favorite: favorite, playbackPreference: preference,
            isAvailable: track.scanState == .available
        )
    }

    private static func rank(_ lhs: AnalyticsTrackSummary, _ rhs: AnalyticsTrackSummary) -> Bool {
        if lhs.playCount != rhs.playCount { return lhs.playCount > rhs.playCount }
        if lhs.totalPlaybackDuration != rhs.totalPlaybackDuration { return lhs.totalPlaybackDuration > rhs.totalPlaybackDuration }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func makeTrends(
        tracks: [Track], events: [PersistedMyMusicPlaybackEvent], summaries: [AnalyticsTrackSummary],
        now: Date, calendar: Calendar
    ) -> [AnalyticsTrendItem] {
        let recentStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -59, to: calendar.startOfDay(for: now)) ?? now
        let trackByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var result: [AnalyticsTrendItem] = []

        let recentGroups = Dictionary(grouping: events.filter { $0.playedAt >= recentStart }, by: \.homeStereoTrackID)
        for (trackID, values) in recentGroups.sorted(by: { $0.value.count > $1.value.count }).prefix(5) {
            guard let track = trackByID[trackID] else { continue }
            result.append(AnalyticsTrendItem(
                id: "recent-\(trackID)", kind: .recentPopular, title: track.title,
                subtitle: track.artist ?? "", reason: "直近30日に\(values.count)セッション再生", trackID: trackID
            ))
        }

        let recentArtists = countsByArtist(events.filter { $0.playedAt >= recentStart }, tracks: trackByID)
        let previousArtists = countsByArtist(
            events.filter { $0.playedAt >= previousStart && $0.playedAt < recentStart }, tracks: trackByID
        )
        for (artist, count) in recentArtists
            .filter({ $0.value > (previousArtists[$0.key] ?? 0) })
            .sorted(by: { ($0.value - (previousArtists[$0.key] ?? 0)) > ($1.value - (previousArtists[$1.key] ?? 0)) })
            .prefix(5) {
            let increase = count - (previousArtists[artist] ?? 0)
            result.append(AnalyticsTrendItem(
                id: "artist-\(artist)", kind: .risingArtist, title: artist,
                subtitle: "Artist", reason: "前の30日間より\(increase)回増加", trackID: nil
            ))
        }

        for (trackID, values) in Dictionary(grouping: events, by: \.homeStereoTrackID) {
            let sorted = values.sorted { $0.playedAt > $1.playedAt }
            guard sorted.count >= 2, sorted[0].playedAt >= recentStart else { continue }
            let days = calendar.dateComponents([.day], from: sorted[1].playedAt, to: sorted[0].playedAt).day ?? 0
            guard days >= 90, let track = trackByID[trackID] else { continue }
            result.append(AnalyticsTrendItem(
                id: "comeback-\(trackID)", kind: .comeback, title: track.title,
                subtitle: track.artist ?? "", reason: "\(days)日ぶりに再生", trackID: trackID
            ))
        }

        for value in summaries.filter({ $0.playCount <= 1 }).prefix(5) {
            result.append(AnalyticsTrendItem(
                id: "low-\(value.trackID)", kind: .lowPlay, title: value.title,
                subtitle: value.artist, reason: value.playCount == 0 ? "まだ正式再生がありません" : "正式再生は1回です",
                trackID: value.trackID
            ))
        }
        for value in summaries.filter({ $0.earlySkipCount > 0 })
            .sorted(by: { $0.earlySkipCount > $1.earlySkipCount }).prefix(5) {
            result.append(AnalyticsTrendItem(
                id: "skip-\(value.trackID)", kind: .earlySkip, title: value.title,
                subtitle: value.artist, reason: "30秒以下のEarly Skipが\(value.earlySkipCount)回", trackID: value.trackID
            ))
        }
        return result
    }

    private static func countsByArtist(
        _ events: [PersistedMyMusicPlaybackEvent], tracks: [Track.ID: Track]
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events {
            guard let artist = tracks[event.homeStereoTrackID]?.artist, !artist.isEmpty else { continue }
            counts[artist, default: 0] += 1
        }
        return counts
    }

    private static func makeRatings(summaries: [AnalyticsTrackSummary]) -> [AnalyticsRatingSummary] {
        let grouped = Dictionary(grouping: summaries) { value -> AnalyticsRatingGroup in
            guard let preference = value.playbackPreference else { return .unset }
            if preference > 0 { return .good }
            if preference < 0 { return .bad }
            return .neutral
        }
        return [AnalyticsRatingGroup.good, .neutral, .bad, .unset].map { group in
            let values = grouped[group] ?? []
            let withCompletion = values.filter { $0.completionRate != nil }
            let withSkip = values.filter { $0.skipRate != nil }
            return AnalyticsRatingSummary(
                group: group, trackCount: values.count,
                playCount: values.reduce(0) { $0 + $1.playCount },
                completionRate: withCompletion.isEmpty ? nil : withCompletion.compactMap(\.completionRate).reduce(0, +) / Double(withCompletion.count),
                skipRate: withSkip.isEmpty ? nil : withSkip.compactMap(\.skipRate).reduce(0, +) / Double(withSkip.count)
            )
        }
    }

    private static func safeSeconds(_ value: TimeInterval) -> TimeInterval {
        value.isFinite ? max(0, value) : 0
    }
}
