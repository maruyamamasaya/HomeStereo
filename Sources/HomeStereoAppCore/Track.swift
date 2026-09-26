import Foundation

public enum TrackScanState: String, Sendable { case available, unreadable, missing }

public struct Track: Identifiable, Hashable, Sendable {
    public static let metadataVersion = 4

    public let id: UUID
    public let libraryFolderID: UUID
    public let relativePath: String
    public let url: URL
    public let fileName: String
    public let fileSize: Int64
    public let modificationDate: Date
    public let fileResourceIdentifier: Data?
    public let audioFingerprint: String?
    public let title: String
    public let artist: String?
    public let albumArtist: String?
    public let album: String?
    public let genre: String?
    public let composer: String?
    public let releaseYear: Int?
    public let trackNumber: Int?
    public let trackTotal: Int?
    public let discNumber: Int?
    public let discTotal: Int?
    public let duration: TimeInterval
    public let fileExtension: String
    public let codec: String?
    public let sampleRate: Double?
    public let bitRate: Double?
    public let bitDepth: Int?
    public let channelCount: Int?
    public let hasArtwork: Bool
    public let artworkData: Data?
    public let scanState: TrackScanState
    public let metadataSchemaVersion: Int
    public let lastScannedAt: Date

    public init(
        id: UUID = UUID(), libraryFolderID: UUID = UUID(), relativePath: String? = nil,
        url: URL, fileSize: Int64 = 0, modificationDate: Date = .distantPast,
        fileResourceIdentifier: Data? = nil, audioFingerprint: String? = nil,
        title: String, artist: String? = nil, albumArtist: String? = nil,
        album: String? = nil, genre: String? = nil, composer: String? = nil,
        releaseYear: Int? = nil, trackNumber: Int? = nil, trackTotal: Int? = nil,
        discNumber: Int? = nil, discTotal: Int? = nil, duration: TimeInterval = 0,
        codec: String? = nil, sampleRate: Double? = nil, bitRate: Double? = nil, bitDepth: Int? = nil,
        channelCount: Int? = nil, hasArtwork: Bool = false, artworkData: Data? = nil,
        scanState: TrackScanState = .available,
        metadataSchemaVersion: Int = Track.metadataVersion, lastScannedAt: Date = .now
    ) {
        let normalizedURL = url.standardizedFileURL
        self.id = id
        self.libraryFolderID = libraryFolderID
        self.relativePath = relativePath ?? normalizedURL.lastPathComponent
        self.url = normalizedURL
        self.fileName = normalizedURL.lastPathComponent
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileResourceIdentifier = fileResourceIdentifier
        self.audioFingerprint = audioFingerprint
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.genre = genre
        self.composer = composer
        self.releaseYear = releaseYear
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.fileExtension = normalizedURL.pathExtension.lowercased()
        self.codec = codec
        self.sampleRate = sampleRate
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
        self.hasArtwork = hasArtwork || artworkData != nil
        self.artworkData = artworkData
        self.scanState = scanState
        self.metadataSchemaVersion = metadataSchemaVersion
        self.lastScannedAt = lastScannedAt
    }

    public func replacingURL(
        _ url: URL,
        relativePath: String? = nil,
        fileResourceIdentifier: Data? = nil,
        scanState: TrackScanState? = nil,
        scannedAt: Date? = nil
    ) -> Track {
        Track(
            id: id, libraryFolderID: libraryFolderID, relativePath: relativePath ?? self.relativePath, url: url,
            fileSize: fileSize, modificationDate: modificationDate,
            fileResourceIdentifier: fileResourceIdentifier ?? self.fileResourceIdentifier,
            audioFingerprint: audioFingerprint,
            title: title, artist: artist,
            albumArtist: albumArtist, album: album, genre: genre, composer: composer,
            releaseYear: releaseYear, trackNumber: trackNumber, trackTotal: trackTotal,
            discNumber: discNumber, discTotal: discTotal, duration: duration, codec: codec,
            sampleRate: sampleRate, bitRate: bitRate, bitDepth: bitDepth, channelCount: channelCount,
            hasArtwork: hasArtwork, artworkData: artworkData, scanState: scanState ?? self.scanState,
            metadataSchemaVersion: metadataSchemaVersion, lastScannedAt: scannedAt ?? lastScannedAt
        )
    }

    public func replacingIdentity(id: UUID, relativePath: String, url: URL, scannedAt: Date) -> Track {
        Track(
            id: id, libraryFolderID: libraryFolderID, relativePath: relativePath, url: url,
            fileSize: fileSize, modificationDate: modificationDate, fileResourceIdentifier: fileResourceIdentifier,
            audioFingerprint: audioFingerprint,
            title: title, artist: artist, albumArtist: albumArtist, album: album, genre: genre,
            composer: composer, releaseYear: releaseYear, trackNumber: trackNumber, trackTotal: trackTotal,
            discNumber: discNumber, discTotal: discTotal, duration: duration, codec: codec,
            sampleRate: sampleRate, bitRate: bitRate, bitDepth: bitDepth, channelCount: channelCount,
            hasArtwork: hasArtwork, artworkData: artworkData, scanState: .available,
            metadataSchemaVersion: metadataSchemaVersion, lastScannedAt: scannedAt
        )
    }
}

public enum TrackIdentityMatchReason: String, Equatable, Sendable {
    case fileResourceIdentifier
    case conservativeMetadata
}

public enum TrackIdentityMatchResult: Equatable, Sendable {
    case matched(trackID: UUID, reason: TrackIdentityMatchReason)
    case ambiguous(candidateCount: Int, reason: TrackIdentityMatchReason)
    case none
}

public enum TrackIdentityResolver {
    public static func match(_ candidate: Track, among existing: [Track]) -> TrackIdentityMatchResult {
        if let identifier = candidate.fileResourceIdentifier {
            let matches = existing.filter { $0.fileResourceIdentifier == identifier }
            if matches.count == 1 { return .matched(trackID: matches[0].id, reason: .fileResourceIdentifier) }
            if matches.count > 1 { return .ambiguous(candidateCount: matches.count, reason: .fileResourceIdentifier) }
        }

        guard candidate.fileSize > 0, candidate.duration > 0,
              candidate.sampleRate != nil, candidate.channelCount != nil else { return .none }
        let matches = existing.filter { conservativeMatch(candidate, $0) }
        if matches.count == 1 { return .matched(trackID: matches[0].id, reason: .conservativeMetadata) }
        if matches.count > 1 { return .ambiguous(candidateCount: matches.count, reason: .conservativeMetadata) }
        return .none
    }

    private static func conservativeMatch(_ lhs: Track, _ rhs: Track) -> Bool {
        lhs.fileSize == rhs.fileSize
            && lhs.fileExtension == rhs.fileExtension
            && abs(lhs.duration - rhs.duration) <= 0.25
            && lhs.codec == rhs.codec
            && equal(lhs.sampleRate, rhs.sampleRate, tolerance: 1)
            && lhs.bitDepth == rhs.bitDepth
            && lhs.channelCount == rhs.channelCount
            && normalized(lhs.title) == normalized(rhs.title)
            && normalized(lhs.artist) == normalized(rhs.artist)
            && normalized(lhs.albumArtist) == normalized(rhs.albumArtist)
            && normalized(lhs.album) == normalized(rhs.album)
    }

    private static func equal(_ lhs: Double?, _ rhs: Double?, tolerance: Double) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return abs(lhs - rhs) <= tolerance
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }
}

public struct LibraryFolder: Identifiable, Hashable, Sendable {
    public enum AccessState: String, Sendable { case available, needsReselection }
    public let id: UUID
    public var displayName: String
    public var path: String
    public var accessState: AccessState
    public var lastScannedAt: Date?
    public var trackCount: Int

    public init(id: UUID = UUID(), displayName: String, path: String, accessState: AccessState = .available, lastScannedAt: Date? = nil, trackCount: Int = 0) {
        self.id = id; self.displayName = displayName; self.path = path
        self.accessState = accessState; self.lastScannedAt = lastScannedAt; self.trackCount = trackCount
    }
}

public struct ScanProgress: Equatable, Sendable {
    public var discovered = 0
    public var analyzed = 0
    public var added = 0
    public var updated = 0
    public var unchanged = 0
    public var failed = 0
    public var missing = 0
    public var currentRelativePath: String?
    public var isCancelled = false
    public init() {}
}

public struct ScanNotice: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let relativePath: String?
    public let message: String
    public init(id: UUID = UUID(), relativePath: String? = nil, message: String) {
        self.id = id; self.relativePath = relativePath; self.message = message
    }
}

public struct LibraryScanResult: Sendable {
    public let tracks: [Track]
    public let progress: ScanProgress
    public let notices: [ScanNotice]
    public init(tracks: [Track], progress: ScanProgress, notices: [ScanNotice]) {
        self.tracks = tracks; self.progress = progress; self.notices = notices
    }
}

public enum SidebarDestination: String, CaseIterable, Identifiable, Sendable {
    case songs, folders, settings
    public var id: Self { self }
}

public enum PlaybackState: Equatable, Sendable { case stopped, playing, paused }

public enum UserFacingError: LocalizedError, Equatable, Sendable {
    case folderAccessLost, folderUnavailable, duplicateFolder, noPlayableAudio
    case playbackFailed(String), scanFailed(String), persistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .folderAccessLost: "音楽フォルダへのアクセス権が失われました。フォルダをもう一度選択してください。"
        case .folderUnavailable: "選択した音楽フォルダが見つかりません。移動または削除されていないか確認してください。"
        case .duplicateFolder: "この音楽フォルダはすでに登録されています。"
        case .noPlayableAudio: "このフォルダに再生可能な音源が見つかりませんでした。"
        case let .playbackFailed(message): "再生できませんでした。ファイルが存在し、読み取り可能か確認してください。\n\(message)"
        case let .scanFailed(message): "音楽フォルダを読み込めませんでした。\n\(message)"
        case let .persistenceFailed(message): "Libraryを保存できませんでした。\n\(message)"
        }
    }
}
