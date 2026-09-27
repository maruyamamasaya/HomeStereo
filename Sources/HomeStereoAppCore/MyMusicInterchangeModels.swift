import Foundation

/// JSONから独立した、MyMusic連携サービスの入出力モデル。
public struct MyMusicTrackRecord: Equatable, Sendable {
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let album: String?
    public let genre: String?
    public let year: Int?
    public let duration: TimeInterval
    public let format: String?
    public let favorite: Bool?
    public let playCount: Int?
    public let lastPlayedAt: Date?
    public let audioFingerprint: String?
    public let firstSeenAt: Date?
    public let relativePath: String?
    public let fileSize: Int64?

    public init(
        trackID: UUID, title: String, artist: String, album: String? = nil,
        genre: String? = nil, year: Int? = nil, duration: TimeInterval,
        format: String? = nil, favorite: Bool? = nil, playCount: Int? = nil,
        lastPlayedAt: Date? = nil, audioFingerprint: String? = nil, firstSeenAt: Date? = nil,
        relativePath: String? = nil, fileSize: Int64? = nil
    ) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.genre = genre; self.year = year; self.duration = duration; self.format = format
        self.favorite = favorite; self.playCount = playCount; self.lastPlayedAt = lastPlayedAt
        self.audioFingerprint = audioFingerprint; self.firstSeenAt = firstSeenAt
        self.relativePath = relativePath; self.fileSize = fileSize
    }
}

public struct MyMusicPreferenceRecord: Equatable, Sendable {
    public let trackID: UUID
    public let playbackPreference: Int
    public let favorite: Bool

    public init(trackID: UUID, playbackPreference: Int, favorite: Bool) {
        self.trackID = trackID; self.playbackPreference = playbackPreference; self.favorite = favorite
    }
}

public struct MyMusicPlaybackEventRecord: Equatable, Sendable {
    public let eventID: String
    public let trackID: UUID
    public let trackTitle: String
    public let artist: String
    public let album: String?
    public let playedAt: Date
    public let playDuration: TimeInterval
    public let trackDuration: TimeInterval
    public let completed: Bool
    public let skipped: Bool
    public let playSource: String
    public let selectionType: String
    public let platform: String
    public let schemaVersion: Int

    public init(
        eventID: String, trackID: UUID, trackTitle: String, artist: String, album: String? = nil,
        playedAt: Date, playDuration: TimeInterval, trackDuration: TimeInterval,
        completed: Bool, skipped: Bool, playSource: String, selectionType: String, platform: String,
        schemaVersion: Int = 1
    ) {
        self.eventID = eventID; self.trackID = trackID; self.trackTitle = trackTitle; self.artist = artist
        self.album = album; self.playedAt = playedAt; self.playDuration = playDuration
        self.trackDuration = trackDuration; self.completed = completed; self.skipped = skipped
        self.playSource = playSource; self.selectionType = selectionType; self.platform = platform
        self.schemaVersion = schemaVersion
    }
}

public struct MyMusicLibraryImport: Equatable, Sendable {
    public let tracks: [MyMusicTrackRecord]
    public init(tracks: [MyMusicTrackRecord]) { self.tracks = tracks }
}

public struct MyMusicPreferencesImport: Equatable, Sendable {
    public let exportedAt: Date
    public let tracks: [MyMusicPreferenceRecord]
    public init(exportedAt: Date, tracks: [MyMusicPreferenceRecord]) {
        self.exportedAt = exportedAt; self.tracks = tracks
    }
}

public struct MyMusicPlaybackEventsImport: Equatable, Sendable {
    public let exportedAt: Date
    public let events: [MyMusicPlaybackEventRecord]
    public init(exportedAt: Date, events: [MyMusicPlaybackEventRecord]) {
        self.exportedAt = exportedAt; self.events = events
    }
}

public struct MyMusicPlaylistTrackRecord: Equatable, Sendable {
    public let trackID: UUID
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?

    public init(
        trackID: UUID, title: String? = nil, artist: String? = nil,
        album: String? = nil, duration: TimeInterval? = nil
    ) {
        self.trackID = trackID; self.title = title; self.artist = artist
        self.album = album; self.duration = duration
    }
}

public struct MyMusicPlaylistRecord: Equatable, Sendable {
    public let playlistID: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let kind: String
    public let tags: [String]
    public let tracks: [MyMusicPlaylistTrackRecord]

    public init(
        playlistID: UUID, name: String, createdAt: Date, updatedAt: Date,
        kind: String = "regular", tags: [String] = [], tracks: [MyMusicPlaylistTrackRecord]
    ) {
        self.playlistID = playlistID; self.name = name; self.createdAt = createdAt
        self.updatedAt = updatedAt; self.kind = kind; self.tags = tags; self.tracks = tracks
    }
}

public struct MyMusicPlaylistsImport: Equatable, Sendable {
    public let playlists: [MyMusicPlaylistRecord]
    public init(playlists: [MyMusicPlaylistRecord]) { self.playlists = playlists }
}
