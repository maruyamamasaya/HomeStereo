import Foundation

public struct BackupTrackReference: Codable, Equatable, Sendable {
    public let trackID: UUID
    public let relativePath: String
    public let fileSize: Int64
    public let duration: TimeInterval
    public let title: String
    public let artist: String?
    public let album: String?

    public init(track: Track) {
        trackID = track.id; relativePath = track.relativePath; fileSize = track.fileSize
        duration = track.duration; title = track.title; artist = track.artist; album = track.album
    }
    public init(trackID: UUID, relativePath: String, fileSize: Int64, duration: TimeInterval, title: String, artist: String? = nil, album: String? = nil) {
        self.trackID = trackID; self.relativePath = relativePath; self.fileSize = fileSize
        self.duration = duration; self.title = title; self.artist = artist; self.album = album
    }
}

public struct BackupPlaylist: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let updatedAt: Date
    public let kind: String
    public let tracks: [BackupTrackReference]
    public init(
        id: UUID, name: String, createdAt: Date, updatedAt: Date,
        kind: String = PlaylistKind.regular.rawValue, tracks: [BackupTrackReference]
    ) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.kind = kind; self.tracks = tracks
    }

    private enum CodingKeys: String, CodingKey { case id, name, createdAt, updatedAt, kind, tracks }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? PlaylistKind.regular.rawValue
        tracks = try container.decode([BackupTrackReference].self, forKey: .tracks)
    }
}

public struct BackupFavorite: Codable, Equatable, Sendable {
    public let track: BackupTrackReference
    public let addedAt: Date
    public init(track: BackupTrackReference, addedAt: Date) { self.track = track; self.addedAt = addedAt }
}

public struct BackupPlaybackEvent: Codable, Equatable, Sendable {
    public let id: UUID
    public let track: BackupTrackReference
    public let startedAt: Date
    public let playedSeconds: TimeInterval
    public let outcome: PlaybackEventOutcome
    public init(id: UUID, track: BackupTrackReference, startedAt: Date, playedSeconds: TimeInterval, outcome: PlaybackEventOutcome) {
        self.id = id; self.track = track; self.startedAt = startedAt; self.playedSeconds = playedSeconds; self.outcome = outcome
    }
}

public struct BackupSettings: Codable, Equatable, Sendable {
    public let automaticLibraryUpdates: Bool
    public init(automaticLibraryUpdates: Bool) { self.automaticLibraryUpdates = automaticLibraryUpdates }
}

public struct HomeStereoBackup: Codable, Equatable, Sendable {
    public static let kindValue = "home-stereo-backup"
    public static let currentSchemaVersion = 2
    public let kind: String
    public let schemaVersion: Int
    public let exportedAt: Date
    public let appVersion: String
    public let playlists: [BackupPlaylist]
    public let favorites: [BackupFavorite]
    public let playbackEvents: [BackupPlaybackEvent]
    public let settings: BackupSettings
    public let state: StateBackupPayload?

    public init(exportedAt: Date, appVersion: String, playlists: [BackupPlaylist], favorites: [BackupFavorite], playbackEvents: [BackupPlaybackEvent], settings: BackupSettings, state: StateBackupPayload? = nil, schemaVersion: Int = 1) {
        kind = Self.kindValue; self.schemaVersion = schemaVersion; self.exportedAt = exportedAt
        self.appVersion = appVersion; self.playlists = playlists; self.favorites = favorites
        self.playbackEvents = playbackEvents; self.settings = settings; self.state = state
    }
}

public struct BackupImportPreview: Equatable, Sendable {
    public let addedPlaylists: Int
    public let updatedPlaylists: Int
    public let addedFavorites: Int
    public let addedEvents: Int
    public let unresolvedTracks: Int
    public let ambiguousTracks: Int
    public init(addedPlaylists: Int, updatedPlaylists: Int, addedFavorites: Int, addedEvents: Int, unresolvedTracks: Int, ambiguousTracks: Int) {
        self.addedPlaylists = addedPlaylists; self.updatedPlaylists = updatedPlaylists
        self.addedFavorites = addedFavorites; self.addedEvents = addedEvents
        self.unresolvedTracks = unresolvedTracks; self.ambiguousTracks = ambiguousTracks
    }
}

public struct ResolvedBackup: Sendable {
    public let document: HomeStereoBackup
    public let playlists: [Playlist]
    public let favorites: [Favorite]
    public let events: [PlaybackEvent]
    public let preview: BackupImportPreview
    public init(document: HomeStereoBackup, playlists: [Playlist], favorites: [Favorite], events: [PlaybackEvent], preview: BackupImportPreview) {
        self.document = document; self.playlists = playlists; self.favorites = favorites; self.events = events; self.preview = preview
    }
}

public enum BackupContractError: LocalizedError, Equatable, Sendable {
    case invalidStructure(String)
    case unsupportedKind(String)
    case unsupportedVersion(Int)
    public var errorDescription: String? {
        switch self {
        case let .invalidStructure(value): "Backup JSONが不正です: \(value)"
        case let .unsupportedKind(value): "未対応のkindです: \(value)"
        case let .unsupportedVersion(value): "未対応のschemaVersionです: \(value)"
        }
    }
}

public enum BackupCodec {
    public static func encode(_ value: HomeStereoBackup) throws -> Data {
        try validate(value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeISO8601Formatter().string(from: date))
        }
        return try encoder.encode(stabilized(value))
    }

    public static func decode(_ data: Data) throws -> HomeStereoBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = makeISO8601Formatter().date(from: value) else { throw BackupContractError.invalidStructure("不正なUTC日時") }
            return date
        }
        let value: HomeStereoBackup
        do { value = try decoder.decode(HomeStereoBackup.self, from: data) }
        catch let error as BackupContractError { throw error }
        catch { throw BackupContractError.invalidStructure(error.localizedDescription) }
        try validate(value)
        return value
    }

    public static func validate(_ value: HomeStereoBackup) throws {
        guard value.kind == HomeStereoBackup.kindValue else { throw BackupContractError.unsupportedKind(value.kind) }
        guard (1...HomeStereoBackup.currentSchemaVersion).contains(value.schemaVersion) else { throw BackupContractError.unsupportedVersion(value.schemaVersion) }
        guard (value.schemaVersion == 2) == (value.state != nil) else { throw BackupContractError.invalidStructure("保存状態とversionが一致しません") }
        guard Set(value.playlists.map(\.id)).count == value.playlists.count else { throw BackupContractError.invalidStructure("Playlist IDが重複") }
        guard Set(value.playbackEvents.map(\.id)).count == value.playbackEvents.count else { throw BackupContractError.invalidStructure("event IDが重複") }
        guard Set(value.favorites.map(\.track.trackID)).count == value.favorites.count else { throw BackupContractError.invalidStructure("Favoriteが重複") }
        let refs = value.playlists.flatMap(\.tracks) + value.favorites.map(\.track) + value.playbackEvents.map(\.track)
        guard refs.allSatisfy({ $0.duration.isFinite && $0.duration >= 0 && $0.fileSize >= 0 }) else { throw BackupContractError.invalidStructure("不正なsizeまたはduration") }
        guard value.playbackEvents.allSatisfy({ $0.playedSeconds.isFinite && $0.playedSeconds >= 0 }) else { throw BackupContractError.invalidStructure("不正な実再生秒数") }
    }

    private static func stabilized(_ value: HomeStereoBackup) -> HomeStereoBackup {
        HomeStereoBackup(
            exportedAt: value.exportedAt, appVersion: value.appVersion,
            playlists: value.playlists.sorted { $0.id.uuidString < $1.id.uuidString },
            favorites: value.favorites.sorted { $0.track.trackID.uuidString < $1.track.trackID.uuidString },
            playbackEvents: value.playbackEvents.sorted { $0.id.uuidString < $1.id.uuidString }, settings: value.settings, state: value.state, schemaVersion: value.schemaVersion
        )
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let value = ISO8601DateFormatter()
        value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        value.timeZone = TimeZone(secondsFromGMT: 0)
        return value
    }
}

public enum BackupTrackMatcher {
    public enum Result: Equatable { case matched(Track.ID), unresolved, ambiguous }
    public static func match(_ reference: BackupTrackReference, tracks: [Track]) -> Result {
        if tracks.contains(where: { $0.id == reference.trackID }) { return .matched(reference.trackID) }
        let path = tracks.filter { $0.relativePath == reference.relativePath }
        if path.count == 1 { return .matched(path[0].id) }
        let conservative = path.filter { $0.fileSize == reference.fileSize && close($0.duration, reference.duration) }
        if conservative.count == 1 { return .matched(conservative[0].id) }
        let metadata = tracks.filter {
            $0.title == reference.title && $0.artist == reference.artist && $0.album == reference.album && close($0.duration, reference.duration)
        }
        if metadata.count == 1 { return .matched(metadata[0].id) }
        if path.count > 1 || conservative.count > 1 || metadata.count > 1 { return .ambiguous }
        return .unresolved
    }
    private static func close(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool { abs(lhs - rhs) <= 0.5 }
}
