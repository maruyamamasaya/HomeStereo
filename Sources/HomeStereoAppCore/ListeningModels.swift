import Foundation

public struct Favorite: Identifiable, Hashable, Sendable {
    public var id: Track.ID { trackID }
    public let trackID: Track.ID
    public let addedAt: Date

    public init(trackID: Track.ID, addedAt: Date = .now) {
        self.trackID = trackID
        self.addedAt = addedAt
    }
}

public enum PlaybackEventOutcome: String, Codable, Sendable {
    case completed
    case stopped
}

public struct PlaybackEvent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let trackID: Track.ID
    public let startedAt: Date
    public var playedSeconds: TimeInterval
    public var outcome: PlaybackEventOutcome

    public init(
        id: UUID = UUID(), trackID: Track.ID, startedAt: Date = .now,
        playedSeconds: TimeInterval = 0, outcome: PlaybackEventOutcome = .stopped
    ) {
        self.id = id
        self.trackID = trackID
        self.startedAt = startedAt
        self.playedSeconds = max(0, playedSeconds)
        self.outcome = outcome
    }
}

public struct FrequentTrack: Identifiable, Hashable, Sendable {
    public let trackID: Track.ID
    public let playCount: Int
    public var id: Track.ID { trackID }

    public init(trackID: Track.ID, playCount: Int) {
        self.trackID = trackID
        self.playCount = playCount
    }
}
