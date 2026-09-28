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
    public let firstSeenAt: Date?
    public let lastSeenAt: Date
    public let isInCurrentSnapshot: Bool
    public let matchedAt: Date
    public let matchMethod: MyMusicTrackMatchMethod
    public let source: MyMusicLinkSource

    public init(
        homeStereoTrackID: Track.ID, myMusicTrackID: UUID, relativePath: String,
        fileSize: Int64, duration: TimeInterval, audioFingerprint: String? = nil,
        firstSeenAt: Date? = nil, lastSeenAt: Date? = nil, isInCurrentSnapshot: Bool = true,
        matchedAt: Date, matchMethod: MyMusicTrackMatchMethod, source: MyMusicLinkSource
    ) {
        self.homeStereoTrackID = homeStereoTrackID; self.myMusicTrackID = myMusicTrackID
        self.relativePath = relativePath; self.fileSize = fileSize; self.duration = duration
        self.audioFingerprint = audioFingerprint; self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt ?? matchedAt; self.isInCurrentSnapshot = isInCurrentSnapshot
        self.matchedAt = matchedAt
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
    public let endedAt: Date
    public let playDuration: TimeInterval
    public let trackDuration: TimeInterval
    public let completed: Bool
    public let skipped: Bool
    public let playSource: String
    public let selectionType: String
    public let endKind: PlaybackAnalyticsEndKind
    public let platform: String
    public let schemaVersion: Int

    public var completionRatio: Double? {
        MyMusicPlaybackPolicy.completionRatio(
            listenedSeconds: playDuration, trackDuration: trackDuration
        )
    }
}

public struct PersistedMyMusicPlayCount: Equatable, Sendable {
    public let myMusicTrackID: UUID
    public let homeStereoTrackID: Track.ID?
    public let playCount: Int
    public let lastPlayedAt: Date?
    public let importedAt: Date

    public init(
        myMusicTrackID: UUID, homeStereoTrackID: Track.ID? = nil, playCount: Int,
        lastPlayedAt: Date? = nil, importedAt: Date
    ) {
        self.myMusicTrackID = myMusicTrackID
        self.homeStereoTrackID = homeStereoTrackID
        self.playCount = max(0, playCount)
        self.lastPlayedAt = lastPlayedAt
        self.importedAt = importedAt
    }
}

public enum MyMusicLibraryMatchStatus: String, Sendable {
    case matched, newlyLinked, unchanged, unmatched, ambiguous, conflict, invalid
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
    public var conflicts: Int { items.count { $0.status == .conflict } }
    public var invalid: Int { items.count { $0.status == .invalid } }
    public var exactTrackID: Int { items.count { $0.matchMethod == .trackID && $0.status != .conflict } }
    public var relativePath: Int { items.count { $0.matchMethod == .relativePath && $0.status == .newlyLinked } }
    public var fingerprint: Int { items.count { $0.matchMethod == .fingerprint && $0.status == .newlyLinked } }
    public let missingFromSnapshot: Int

    public init(items: [MyMusicLibraryMatchItem], missingFromSnapshot: Int = 0) {
        self.items = items; self.missingFromSnapshot = missingFromSnapshot
    }
}

public struct MyMusicPlaylistPersistenceResult: Equatable, Sendable {
    public let addedPlaylists: Int
    public let updatedPlaylists: Int
    public let unchangedPlaylists: Int
    public let importedTracks: Int
    public let unresolvedTrackIDs: [UUID]
    public let conflictedTrackIDs: [UUID]
}

public struct MyMusicPlaylistExportResult: Equatable, Sendable {
    public let data: Data
    public let totalTracks: Int
    public let exportedTracks: Int
    public let missingMyMusicID: Int
    public let conflictedTracks: Int
}

public struct MyMusicPreferencesPersistenceResult: Equatable, Sendable {
    public let updated: Int
    public let unchanged: Int
    public let unresolvedTrackIDs: [UUID]
}

public struct PendingMyMusicPreferenceExport: Equatable, Sendable {
    public let homeStereoTrackID: Track.ID
    public let changeToken: UUID
    public let record: MyMusicPreferenceRecord

    public init(homeStereoTrackID: Track.ID, changeToken: UUID, record: MyMusicPreferenceRecord) {
        self.homeStereoTrackID = homeStereoTrackID
        self.changeToken = changeToken
        self.record = record
    }
}

public struct MyMusicPreferencesExportResult: Equatable, Sendable {
    public let data: Data
    public let pendingChanges: [PendingMyMusicPreferenceExport]

    public init(data: Data, pendingChanges: [PendingMyMusicPreferenceExport]) {
        self.data = data
        self.pendingChanges = pendingChanges
    }
}

public struct MyMusicPlaybackEventsPersistenceResult: Equatable, Sendable {
    public let inserted: Int
    public let duplicates: Int
    public let unresolvedTrackIDs: [UUID]
}

public protocol MyMusicPersisting: Sendable {
    func loadMyMusicMatchContext() async throws -> (tracks: [Track], links: [MyMusicTrackLink])
    func applyMyMusicLibrarySnapshot(
        _ links: [MyMusicTrackLink], records: [MyMusicTrackRecord], importedAt: Date
    ) async throws
    func saveMyMusicTrackLinks(_ links: [MyMusicTrackLink]) async throws
    func loadMyMusicTrackLinks() async throws -> [MyMusicTrackLink]
    func loadMyMusicPlayCounts() async throws -> [PersistedMyMusicPlayCount]
    func mergeMyMusicPreferences(
        _ preferences: [MyMusicPreferenceRecord], exportedAt: Date
    ) async throws -> MyMusicPreferencesPersistenceResult
    func loadMyMusicPreferences() async throws -> [PersistedMyMusicPreference]
    func loadCurrentMyMusicPreferenceRecords() async throws -> [MyMusicPreferenceRecord]
    func loadPendingMyMusicPreferenceExports() async throws -> [PendingMyMusicPreferenceExport]
    func acknowledgeMyMusicPreferenceExports(
        _ pendingChanges: [PendingMyMusicPreferenceExport]
    ) async throws
    func appendMyMusicPlaybackEvents(
        _ events: [MyMusicPlaybackEventRecord]
    ) async throws -> MyMusicPlaybackEventsPersistenceResult
    @discardableResult
    func appendLocalMyMusicPlaybackEvent(_ event: LocalMyMusicPlaybackEvent) async throws -> Bool
    func loadMyMusicPlaybackEvents() async throws -> [PersistedMyMusicPlaybackEvent]
    func loadMyMusicLibraryRecords() async throws -> [MyMusicTrackRecord]
    func loadMyMusicPlaybackEventRecords() async throws -> [MyMusicPlaybackEventRecord]
    func loadMyMusicPlaylistContext() async throws -> (playlists: [Playlist], tracks: [Track], links: [MyMusicTrackLink])
    func mergeMyMusicPlaylists(_ playlists: [MyMusicPlaylistRecord]) async throws -> MyMusicPlaylistPersistenceResult
}

public struct MyMusicPlaybackEventsExportResult: Equatable, Sendable {
    public let data: Data
    public let exported: Int
    public let unresolved: Int

    public init(data: Data, exported: Int, unresolved: Int) {
        self.data = data; self.exported = exported; self.unresolved = unresolved
    }
}
