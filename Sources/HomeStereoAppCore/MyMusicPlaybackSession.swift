import Foundation

public enum MyMusicPlaySource: String, Codable, Sendable, CaseIterable {
    case library, album, artist, favorite, playlist, queue, search, shuffle, history, station, unknown
}

public enum MyMusicSelectionType: String, Codable, Sendable {
    case manual
    case userAdvanced = "user_advanced"
    case automatic
}

public enum MyMusicPlaybackEndReason: Sendable {
    case naturalEnd
    case userAdvanced
    case directSelection
    case queueReplacement
    case stop
    case error
    case playerDestroyed

    fileprivate var isUserDeparture: Bool {
        switch self {
        case .userAdvanced, .directSelection, .queueReplacement: true
        case .naturalEnd, .stop, .error, .playerDestroyed: false
        }
    }
}

/// HomeStereo内で生成したイベント。外部ID未解決でも再生事実を保持するためtrackIDは任意。
public struct LocalMyMusicPlaybackEvent: Equatable, Sendable {
    public let eventID: String
    public let homeStereoTrackID: Track.ID
    public let myMusicTrackID: UUID?
    public let playedAt: Date
    public let endedAt: Date
    public let playDuration: TimeInterval
    public let trackDuration: TimeInterval
    public let completed: Bool
    public let skipped: Bool
    public let playSource: MyMusicPlaySource
    public let selectionType: MyMusicSelectionType
    public let endKind: PlaybackAnalyticsEndKind
    public let platform: String
    public let schemaVersion: Int

    public var completionRatio: Double? {
        MyMusicPlaybackPolicy.completionRatio(
            listenedSeconds: playDuration, trackDuration: trackDuration
        )
    }

    public init(
        eventID: String, homeStereoTrackID: Track.ID, myMusicTrackID: UUID? = nil,
        playedAt: Date, endedAt: Date? = nil, playDuration: TimeInterval, trackDuration: TimeInterval,
        completed: Bool, skipped: Bool, playSource: MyMusicPlaySource,
        selectionType: MyMusicSelectionType, endKind: PlaybackAnalyticsEndKind = .other,
        platform: String = "macOS", schemaVersion: Int = 1
    ) {
        self.eventID = eventID; self.homeStereoTrackID = homeStereoTrackID
        self.myMusicTrackID = myMusicTrackID; self.playedAt = playedAt
        self.endedAt = endedAt ?? playedAt.addingTimeInterval(max(0, playDuration))
        self.playDuration = playDuration; self.trackDuration = trackDuration
        self.completed = completed; self.skipped = completed ? false : skipped
        self.playSource = playSource; self.selectionType = selectionType
        self.endKind = endKind
        self.platform = platform; self.schemaVersion = schemaVersion
    }
}

public struct MyMusicPlaybackSession: Equatable, Sendable {
    public let eventID: String
    public let homeStereoTrackID: Track.ID
    public let myMusicTrackID: UUID?
    public let startedAt: Date
    public private(set) var listenedSeconds: TimeInterval
    public let trackDuration: TimeInterval
    public let playSource: MyMusicPlaySource
    public let selectionType: MyMusicSelectionType
    public private(set) var lastObservedPosition: TimeInterval?
    public private(set) var finalized: Bool
    public private(set) var isPlaying: Bool

    public init(
        eventID: String, homeStereoTrackID: Track.ID, myMusicTrackID: UUID? = nil,
        startedAt: Date, trackDuration: TimeInterval, playSource: MyMusicPlaySource,
        selectionType: MyMusicSelectionType
    ) {
        self.eventID = eventID; self.homeStereoTrackID = homeStereoTrackID
        self.myMusicTrackID = myMusicTrackID; self.startedAt = startedAt
        self.listenedSeconds = 0
        self.trackDuration = MyMusicPlaybackPolicy.hasValidDuration(trackDuration) ? trackDuration : 0
        self.playSource = playSource; self.selectionType = selectionType
        self.lastObservedPosition = nil; self.finalized = false; self.isPlaying = true
    }

    public mutating func setPlaying(_ playing: Bool) {
        guard !finalized else { return }
        if playing != isPlaying { lastObservedPosition = nil }
        isPlaying = playing
    }

    public mutating func observe(position: TimeInterval, maximumContinuousDelta: TimeInterval = 5) {
        guard !finalized, isPlaying, position.isFinite, position >= 0 else { return }
        defer { lastObservedPosition = position }
        guard let previous = lastObservedPosition else { return }
        let delta = position - previous
        guard delta > 0, delta <= maximumContinuousDelta else { return }
        listenedSeconds += delta
    }

    public mutating func finalize(reason: MyMusicPlaybackEndReason, endedAt: Date = .now) -> LocalMyMusicPlaybackEvent? {
        guard !finalized else { return nil }
        finalized = true; isPlaying = false
        let completed = MyMusicPlaybackPolicy.isCompleted(
            listenedSeconds: listenedSeconds, trackDuration: trackDuration
        )
        return LocalMyMusicPlaybackEvent(
            eventID: eventID, homeStereoTrackID: homeStereoTrackID,
            myMusicTrackID: myMusicTrackID, playedAt: startedAt,
            endedAt: max(endedAt, startedAt),
            playDuration: listenedSeconds, trackDuration: trackDuration,
            completed: completed, skipped: reason.isUserDeparture && !completed,
            playSource: playSource, selectionType: selectionType, endKind: reason.analyticsEndKind
        )
    }
}

public enum MyMusicPlaybackPolicy {
    public static let maximumContinuousPositionDelta: TimeInterval = 5

    public static func isCompleted(listenedSeconds: TimeInterval, trackDuration: TimeInterval) -> Bool {
        guard listenedSeconds.isFinite, listenedSeconds >= 0, hasValidDuration(trackDuration) else { return false }
        return listenedSeconds >= max(3, trackDuration * 0.94)
    }

    public static func completionRatio(
        listenedSeconds: TimeInterval, trackDuration: TimeInterval
    ) -> Double? {
        guard listenedSeconds.isFinite, listenedSeconds >= 0, hasValidDuration(trackDuration) else { return nil }
        return min(1, listenedSeconds / trackDuration)
    }

    public static func countsAsPlay(listenedSeconds: TimeInterval, trackDuration: TimeInterval) -> Bool {
        guard listenedSeconds.isFinite, listenedSeconds >= 0 else { return false }
        guard hasValidDuration(trackDuration) else { return listenedSeconds >= 30 }
        return listenedSeconds >= min(30, trackDuration * 0.5)
    }

    public static func isEarlySkip(skipped: Bool, listenedSeconds: TimeInterval) -> Bool {
        skipped && listenedSeconds.isFinite && listenedSeconds >= 0 && listenedSeconds <= 30
    }

    public static func hasValidDuration(_ duration: TimeInterval) -> Bool {
        duration.isFinite && duration > 0
    }
}

private extension MyMusicPlaybackEndReason {
    var analyticsEndKind: PlaybackAnalyticsEndKind {
        switch self {
        case .naturalEnd: .natural
        case .userAdvanced, .directSelection, .queueReplacement: .userSkipped
        case .stop, .error, .playerDestroyed: .other
        }
    }
}
