import Foundation

public struct TrackPreference: Equatable, Sendable {
    public let trackID: Track.ID
    public let playbackPreference: Int
    public let updatedAt: Date

    public init(trackID: Track.ID, playbackPreference: Int, updatedAt: Date = .now) {
        self.trackID = trackID
        self.playbackPreference = min(10, max(-10, playbackPreference))
        self.updatedAt = updatedAt
    }
}

public enum PlaybackAnalyticsEndKind: String, Codable, Sendable {
    case natural
    case userSkipped = "user_skipped"
    case other
}

public struct AnalyticsContext: Sendable {
    public let tracks: [Track]
    public let events: [PersistedMyMusicPlaybackEvent]
    public let favorites: [Favorite]
    public let preferences: [TrackPreference]
    public let playlists: [Playlist]
    public let myMusicPlayCounts: [PersistedMyMusicPlayCount]

    public init(
        tracks: [Track], events: [PersistedMyMusicPlaybackEvent], favorites: [Favorite],
        preferences: [TrackPreference], playlists: [Playlist],
        myMusicPlayCounts: [PersistedMyMusicPlayCount] = []
    ) {
        self.tracks = tracks; self.events = events; self.favorites = favorites
        self.preferences = preferences; self.playlists = playlists
        self.myMusicPlayCounts = myMusicPlayCounts
    }
}

public protocol AnalyticsPersisting: Sendable {
    func loadAnalyticsContext() async throws -> AnalyticsContext
    func saveTrackPreference(_ preference: TrackPreference) async throws
    func deleteAnalyticsHistory(trackID: Track.ID?) async throws
}

public protocol TrackPreferencePersisting: Sendable {
    func loadTrackPreferences() async throws -> [TrackPreference]
    func saveTrackPreference(_ preference: TrackPreference) async throws
}

public struct AnalyticsOverview: Equatable, Sendable {
    public let playCount: Int
    public let totalPlaybackDuration: TimeInterval
    public let manualPlayCount: Int
    public let automaticPlayCount: Int
    public let userAdvancedPlayCount: Int
    public let playedTrackCount: Int
    public let favoriteTrackCount: Int
    public let todayPlayCount: Int
    public let todayPlaybackDuration: TimeInterval
    public let last7DaysPlayCount: Int
    public let last30DaysPlayCount: Int
    public let usesMyMusicPlayCount: Bool
}

public struct AnalyticsTrackSummary: Identifiable, Equatable, Sendable {
    public let trackID: Track.ID
    public let title: String
    public let artist: String
    public let album: String
    public let genre: String
    public let playCount: Int
    public let sessionCount: Int
    public let totalPlaybackDuration: TimeInterval
    public let lastPlayedAt: Date?
    public let completionRate: Double?
    public let skipRate: Double?
    public let earlySkipCount: Int
    public let favorite: Bool
    public let playbackPreference: Int?
    public let isAvailable: Bool
    public var id: Track.ID { trackID }
}

public struct AnalyticsEventRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let trackID: Track.ID
    public let title: String
    public let artist: String
    public let startedAt: Date
    public let endedAt: Date
    public let listenedSeconds: TimeInterval
    public let trackDuration: TimeInterval
    public let completionRatio: Double?
    public let wasFullPlayback: Bool
    public let wasSkipped: Bool
    public let wasEarlySkip: Bool
    public let startKind: MyMusicSelectionType
    public let startSource: MyMusicPlaySource
    public let endKind: PlaybackAnalyticsEndKind
    public let platform: String

    public var playbackPlatform: AnalyticsPlaybackPlatform {
        AnalyticsPlaybackPlatform(platform)
    }
}

public enum AnalyticsPlaybackPlatform: Equatable, Sendable {
    case mac
    case app
    case other(String)

    public init(_ rawValue: String) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.lowercased()
        if normalized.contains("mac") {
            self = .mac
        } else if normalized.contains("ios") || normalized.contains("iphone") || normalized.contains("ipad") {
            self = .app
        } else {
            self = .other(value)
        }
    }
}

public struct AnalyticsHistoryDay: Identifiable, Equatable, Sendable {
    public let date: Date
    public let events: [AnalyticsEventRow]
    public var id: Date { date }
}

public enum AnalyticsTrendKind: String, Sendable {
    case recentPopular, risingArtist, comeback, lowPlay, earlySkip
}

public struct AnalyticsTrendItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: AnalyticsTrendKind
    public let title: String
    public let subtitle: String
    public let reason: String
    public let trackID: Track.ID?
}

public enum AnalyticsRatingGroup: String, Sendable {
    case good, neutral, bad, unset
}

public struct AnalyticsRatingSummary: Identifiable, Equatable, Sendable {
    public let group: AnalyticsRatingGroup
    public let trackCount: Int
    public let playCount: Int
    public let completionRate: Double?
    public let skipRate: Double?
    public var id: AnalyticsRatingGroup { group }
}

public struct AnalyticsSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let overview: AnalyticsOverview
    public let topTracks: [AnalyticsTrackSummary]
    public let allTracks: [AnalyticsTrackSummary]
    public let recentEvents: [AnalyticsEventRow]
    public let historyDays: [AnalyticsHistoryDay]
    public let trends: [AnalyticsTrendItem]
    public let ratings: [AnalyticsRatingSummary]

    public static func empty(at date: Date = .distantPast) -> AnalyticsSnapshot {
        AnalyticsSnapshot(
            generatedAt: date,
            overview: AnalyticsOverview(
                playCount: 0, totalPlaybackDuration: 0, manualPlayCount: 0,
                automaticPlayCount: 0, userAdvancedPlayCount: 0, playedTrackCount: 0,
                favoriteTrackCount: 0, todayPlayCount: 0, todayPlaybackDuration: 0,
                last7DaysPlayCount: 0, last30DaysPlayCount: 0,
                usesMyMusicPlayCount: false
            ),
            topTracks: [], allTracks: [], recentEvents: [], historyDays: [], trends: [], ratings: []
        )
    }
}
