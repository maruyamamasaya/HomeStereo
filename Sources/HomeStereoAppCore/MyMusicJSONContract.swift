import Foundation

public struct MyMusicLibraryDocumentDTO: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let tracks: [MyMusicLibraryTrackDTO]
    public init(version: Int, tracks: [MyMusicLibraryTrackDTO]) { self.version = version; self.tracks = tracks }
}

public struct MyMusicLibraryTrackDTO: Codable, Equatable, Sendable {
    public let trackID: UUID
    public let title: String
    public let artist: String
    public let album: String?
    public let genre: String?
    public let year: Int?
    public let duration: Double
    public let format: String?
    public let favorite: Bool?
    public let playCount: Int?
    public let lastPlayedAt: Date?
    public let audioFingerprint: String?
    public let firstSeenAt: Date?

    public init(
        trackID: UUID, title: String, artist: String, album: String? = nil, genre: String? = nil,
        year: Int? = nil, duration: Double, format: String? = nil, favorite: Bool? = nil,
        playCount: Int? = nil, lastPlayedAt: Date? = nil, audioFingerprint: String? = nil,
        firstSeenAt: Date? = nil
    ) {
        self.trackID = trackID; self.title = title; self.artist = artist; self.album = album
        self.genre = genre; self.year = year; self.duration = duration; self.format = format
        self.favorite = favorite; self.playCount = playCount; self.lastPlayedAt = lastPlayedAt
        self.audioFingerprint = audioFingerprint; self.firstSeenAt = firstSeenAt
    }
}

public struct MyMusicPreferencesDocumentDTO: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    public let exportedAt: Date
    public let tracks: [MyMusicPreferenceTrackDTO]
    public init(schemaVersion: Int, exportedAt: Date, tracks: [MyMusicPreferenceTrackDTO]) {
        self.schemaVersion = schemaVersion; self.exportedAt = exportedAt; self.tracks = tracks
    }
}

public struct MyMusicPreferenceTrackDTO: Codable, Equatable, Sendable {
    public let trackId: UUID
    public let playbackPreference: Int
    public let favorite: Bool
    public init(trackId: UUID, playbackPreference: Int, favorite: Bool) {
        self.trackId = trackId; self.playbackPreference = playbackPreference; self.favorite = favorite
    }
}

public struct MyMusicPlaybackEventsDocumentDTO: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let exportedAt: Date
    public let events: [MyMusicPlaybackEventDTO]
    public init(schemaVersion: Int, exportedAt: Date, events: [MyMusicPlaybackEventDTO]) {
        self.schemaVersion = schemaVersion; self.exportedAt = exportedAt; self.events = events
    }
}

public struct MyMusicPlaybackEventDTO: Codable, Equatable, Sendable {
    public let eventId: String
    public let trackId: UUID
    public let trackTitle: String
    public let artist: String
    public let album: String?
    public let playedAt: Date
    public let playDuration: Double
    public let trackDuration: Double
    public let completed: Bool
    public let skipped: Bool
    public let playSource: String
    public let selectionType: String
    public let platform: String
    public let schemaVersion: Int

    public init(
        eventId: String, trackId: UUID, trackTitle: String, artist: String, album: String? = nil,
        playedAt: Date, playDuration: Double, trackDuration: Double, completed: Bool, skipped: Bool,
        playSource: String, selectionType: String, platform: String, schemaVersion: Int
    ) {
        self.eventId = eventId; self.trackId = trackId; self.trackTitle = trackTitle; self.artist = artist
        self.album = album; self.playedAt = playedAt; self.playDuration = playDuration
        self.trackDuration = trackDuration; self.completed = completed; self.skipped = skipped
        self.playSource = playSource; self.selectionType = selectionType; self.platform = platform
        self.schemaVersion = schemaVersion
    }
}

public enum MyMusicJSONContractError: LocalizedError, Equatable, Sendable {
    case invalidStructure(String)
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case let .invalidStructure(reason): "MyMusic JSONが不正です: \(reason)"
        case let .unsupportedVersion(version): "未対応のMyMusic schema versionです: \(version)"
        }
    }
}

public enum MyMusicJSONCodec {
    public static let libraryFileName = "MyMusic-Library.json"
    public static let preferencesFileName = "MyMusic-Playback-Preferences.json"
    public static let playbackEventsFileName = "MyMusic-Playback-Events.json"

    public static func decodeLibrary(_ data: Data) throws -> MyMusicLibraryDocumentDTO {
        let value: MyMusicLibraryDocumentDTO = try decode(data)
        try validate(value)
        return value
    }

    public static func decodePreferences(_ data: Data) throws -> MyMusicPreferencesDocumentDTO {
        let value: MyMusicPreferencesDocumentDTO = try decode(data)
        try validate(value)
        return value
    }

    public static func decodePlaybackEvents(_ data: Data) throws -> MyMusicPlaybackEventsDocumentDTO {
        let value: MyMusicPlaybackEventsDocumentDTO = try decode(data)
        try validate(value)
        return value
    }

    public static func encodeLibrary(_ value: MyMusicLibraryDocumentDTO) throws -> Data {
        try validate(value); return try encode(value)
    }

    public static func encodePreferences(_ value: MyMusicPreferencesDocumentDTO) throws -> Data {
        try validate(value); return try encode(value)
    }

    public static func encodePlaybackEvents(_ value: MyMusicPlaybackEventsDocumentDTO) throws -> Data {
        try validate(value); return try encode(value)
    }

    public static func validate(_ value: MyMusicLibraryDocumentDTO) throws {
        guard value.version == MyMusicLibraryDocumentDTO.currentVersion else {
            throw MyMusicJSONContractError.unsupportedVersion(value.version)
        }
        guard Set(value.tracks.map(\.trackID)).count == value.tracks.count else { throw invalid("trackIDが重複") }
        for track in value.tracks {
            guard track.duration.isFinite, track.duration >= 0 else { throw invalid("durationは0以上の有限値が必要") }
            guard track.playCount.map({ $0 >= 0 }) ?? true else { throw invalid("playCountは0以上が必要") }
            guard track.format.map(supportedFormats.contains) ?? true else { throw invalid("未対応のformat") }
            guard track.audioFingerprint.map(isLowercaseSHA256) ?? true else {
                throw invalid("audioFingerprintは64文字のlowercase SHA-256が必要")
            }
        }
    }

    public static func validate(_ value: MyMusicPreferencesDocumentDTO) throws {
        guard value.schemaVersion == MyMusicPreferencesDocumentDTO.currentSchemaVersion else {
            throw MyMusicJSONContractError.unsupportedVersion(value.schemaVersion)
        }
        guard Set(value.tracks.map(\.trackId)).count == value.tracks.count else { throw invalid("trackIdが重複") }
        guard value.tracks.allSatisfy({ (-10...10).contains($0.playbackPreference) }) else {
            throw invalid("playbackPreferenceは-10〜10が必要")
        }
    }

    public static func validate(_ value: MyMusicPlaybackEventsDocumentDTO) throws {
        guard value.schemaVersion == MyMusicPlaybackEventsDocumentDTO.currentSchemaVersion else {
            throw MyMusicJSONContractError.unsupportedVersion(value.schemaVersion)
        }
        guard Set(value.events.map(\.eventId)).count == value.events.count else { throw invalid("eventIdが重複") }
        for event in value.events {
            guard !event.eventId.isEmpty else { throw invalid("eventIdが空") }
            guard event.schemaVersion == MyMusicPlaybackEventsDocumentDTO.currentSchemaVersion else {
                throw MyMusicJSONContractError.unsupportedVersion(event.schemaVersion)
            }
            guard event.playDuration.isFinite, event.playDuration >= 0,
                  event.trackDuration.isFinite, event.trackDuration >= 0 else {
                throw invalid("再生時間は0以上の有限値が必要")
            }
            guard !(event.completed && event.skipped) else { throw invalid("completed時にskippedはfalseが必要") }
            guard selectionTypes.contains(event.selectionType) else { throw invalid("未対応のselectionType") }
            guard playSources.contains(event.playSource) else { throw invalid("未対応のplaySource") }
        }
    }

    private static let supportedFormats: Set<String> = ["FLAC", "ALAC", "AAC", "MP3", "WAV", "AIFF"]
    private static let selectionTypes: Set<String> = ["manual", "user_advanced", "automatic"]
    private static let playSources: Set<String> = [
        "album", "artist", "favorite", "highlight", "history", "home", "library", "playlist", "queue",
        "repeat", "search", "shuffle", "station", "hi_res_library", "workLibrary", "unknown"
    ]

    private static func invalid(_ reason: String) -> MyMusicJSONContractError { .invalidStructure(reason) }
    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) || (97...102).contains($0.value) }
    }

    private static func decode<T: Decodable>(_ data: Data) throws -> T {
        guard !data.contains(0), String(data: data, encoding: .utf8) != nil else {
            throw invalid("文字コードはUTF-8が必要")
        }
        do { return try decoder().decode(T.self, from: data) }
        catch let error as MyMusicJSONContractError { throw error }
        catch { throw invalid(error.localizedDescription) }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatterWithFraction.string(from: date))
        }
        return try encoder.encode(value)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard value.hasSuffix("Z"), let date = formatterWithFraction.date(from: value) ?? formatterWithoutFraction.date(from: value) else {
                throw invalid("日時はUTCのISO 8601が必要")
            }
            return date
        }
        return decoder
    }

    private static var formatterWithFraction: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static var formatterWithoutFraction: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}
