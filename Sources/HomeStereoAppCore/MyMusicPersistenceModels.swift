import Foundation

public enum MyMusicTrackMatchMethod: String, Codable, Sendable {
    case trackID = "track_id"
    case relativePath = "relative_path"
    case fingerprint
    case metadataFallback = "metadata_fallback"
    case manual
}

public enum MyMusicLinkSource: String, Codable, Sendable {
    case libraryImport = "mymusic_library_import"
    case homeStereoExport = "home_stereo_export"
    case manual
}

public struct MyMusicTrackLink: Equatable, Sendable {
    public let homeStereoTrackID: Track.ID
    public let myMusicTrackID: UUID
    public let relativePath: String
    public let fileSize: Int64
    public let duration: TimeInterval
    public let audioFingerprint: String?
    public let matchedAt: Date
    public let matchMethod: MyMusicTrackMatchMethod
    public let source: MyMusicLinkSource

    public init(
        homeStereoTrackID: Track.ID, myMusicTrackID: UUID, relativePath: String,
        fileSize: Int64, duration: TimeInterval, audioFingerprint: String? = nil,
        matchedAt: Date, matchMethod: MyMusicTrackMatchMethod, source: MyMusicLinkSource
    ) {
        self.homeStereoTrackID = homeStereoTrackID; self.myMusicTrackID = myMusicTrackID
        self.relativePath = relativePath; self.fileSize = fileSize; self.duration = duration
        self.audioFingerprint = audioFingerprint; self.matchedAt = matchedAt
        self.matchMethod = matchMethod; self.source = source
    }
}

public struct PersistedMyMusicPreference: Equatable, Sendable {
    public let homeStereoTrackID: Track.ID
    public let myMusicTrackID: UUID
    public let playbackPreference: Int
    public let favorite: Bool
    public let exportedAt: Date
}

public struct PersistedMyMusicPlaybackEvent: Equatable, Sendable {
    public let eventID: String
    public let homeStereoTrackID: Track.ID
    public let myMusicTrackID: UUID?
    public let playedAt: Date
    public let playDuration: TimeInterval
    public let trackDuration: TimeInterval
    public let completed: Bool
    public let skipped: Bool
    public let playSource: String
    public let selectionType: String
    public let platform: String
    public let schemaVersion: Int
}

public enum MyMusicLibraryMatchStatus: String, Sendable {
    case matched, newlyLinked, unchanged, unmatched, ambiguous, invalid
}

public struct MyMusicLibraryMatchItem: Equatable, Sendable {
    public let myMusicTrackID: UUID
    public let homeStereoTrackID: Track.ID?
    public let status: MyMusicLibraryMatchStatus
    public let matchMethod: MyMusicTrackMatchMethod?
    public let detail: String?
}

public struct MyMusicLibraryPersistenceResult: Equatable, Sendable {
    public let items: [MyMusicLibraryMatchItem]
    public var matched: Int { items.count { $0.status == .matched } }
    public var newlyLinked: Int { items.count { $0.status == .newlyLinked } }
    public var unchanged: Int { items.count { $0.status == .unchanged } }
    public var unmatched: Int { items.count { $0.status == .unmatched } }
    public var ambiguous: Int { items.count { $0.status == .ambiguous } }
    public var invalid: Int { items.count { $0.status == .invalid } }
}

public struct MyMusicPreferencesPersistenceResult: Equatable, Sendable {
    public let updated: Int
    public let unchanged: Int
    public let unresolvedTrackIDs: [UUID]
}

public struct MyMusicPlaybackEventsPersistenceResult: Equatable, Sendable {
    public let inserted: Int
    public let duplicates: Int
    public let unresolvedTrackIDs: [UUID]
}

public protocol MyMusicPersisting: Sendable {
    func loadMyMusicMatchContext() async throws -> (tracks: [Track], links: [MyMusicTrackLink])
    func saveMyMusicTrackLinks(_ links: [MyMusicTrackLink]) async throws
    func loadMyMusicTrackLinks() async throws -> [MyMusicTrackLink]
    func mergeMyMusicPreferences(
        _ preferences: [MyMusicPreferenceRecord], exportedAt: Date
    ) async throws -> MyMusicPreferencesPersistenceResult
    func loadMyMusicPreferences() async throws -> [PersistedMyMusicPreference]
    func appendMyMusicPlaybackEvents(
        _ events: [MyMusicPlaybackEventRecord]
    ) async throws -> MyMusicPlaybackEventsPersistenceResult
    @discardableResult
    func appendLocalMyMusicPlaybackEvent(_ event: LocalMyMusicPlaybackEvent) async throws -> Bool
    func loadMyMusicPlaybackEvents() async throws -> [PersistedMyMusicPlaybackEvent]
    func loadMyMusicLibraryRecords() async throws -> [MyMusicTrackRecord]
    func loadMyMusicPlaybackEventRecords() async throws -> [MyMusicPlaybackEventRecord]
}

public struct MyMusicPlaybackEventsExportResult: Equatable, Sendable {
    public let data: Data
    public let exported: Int
    public let unresolved: Int

    public init(data: Data, exported: Int, unresolved: Int) {
        self.data = data; self.exported = exported; self.unresolved = unresolved
    }
}
