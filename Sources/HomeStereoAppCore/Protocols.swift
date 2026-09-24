import AVFoundation
import Foundation

@MainActor
public protocol AudioPlaybackServicing: AnyObject {
    var routePickerPlayer: AVPlayer? { get }
    var onStateChange: (@MainActor (PlaybackState, Int?) -> Void)? { get set }
    var onFailure: (@MainActor (String) -> Void)? { get set }
    func load(queue: [Track], startingAt index: Int) throws
    func play()
    func pause()
    func next()
    func previous()
    func seek(to seconds: TimeInterval)
    func currentTime() -> TimeInterval
}

public protocol LibraryScanning: Sendable {
    func scan(folder: URL) async throws -> [Track]
    func scan(
        folder: LibraryFolder,
        resolvedURL: URL,
        existingTracks: [Track],
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> LibraryScanResult
}

public extension LibraryScanning {
    func scan(
        folder: LibraryFolder,
        resolvedURL: URL,
        existingTracks: [Track],
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> LibraryScanResult {
        let tracks = try await scan(folder: resolvedURL)
        var value = ScanProgress()
        value.discovered = tracks.count
        value.analyzed = tracks.count
        value.added = tracks.count
        await progress(value)
        return LibraryScanResult(tracks: tracks, progress: value, notices: [])
    }
}

public struct BookmarkResolution: Sendable {
    public let url: URL
    public let refreshedBookmark: Data?
    public init(url: URL, refreshedBookmark: Data? = nil) {
        self.url = url; self.refreshedBookmark = refreshedBookmark
    }
}

@MainActor
public protocol FolderAccessServicing: AnyObject {
    func chooseFolder() -> URL?
    func makeBookmark(for folder: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> BookmarkResolution
    func saveBookmark(for folder: URL) throws
    func restoreFolder() throws -> URL?
    func beginAccessing(_ folder: URL) -> Bool
    func stopAccessing(_ folder: URL)
}

public extension FolderAccessServicing {
    func makeBookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolveBookmark(_ data: Data) throws -> BookmarkResolution {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
            relativeTo: nil, bookmarkDataIsStale: &stale
        )
        return BookmarkResolution(url: url, refreshedBookmark: stale ? try makeBookmark(for: url) : nil)
    }
}

public struct PersistedFolder: Sendable {
    public let folder: LibraryFolder
    public let bookmarkData: Data
    public init(folder: LibraryFolder, bookmarkData: Data) {
        self.folder = folder; self.bookmarkData = bookmarkData
    }
}

public protocol LibraryPersisting: Sendable {
    func schemaVersion() async throws -> Int
    func loadFolders() async throws -> [LibraryFolder]
    func loadFolder(id: UUID) async throws -> PersistedFolder?
    func addFolder(_ folder: LibraryFolder, bookmarkData: Data) async throws
    func updateBookmark(folderID: UUID, bookmarkData: Data, path: String, displayName: String) async throws
    func setFolderAccessState(id: UUID, state: LibraryFolder.AccessState) async throws
    func removeFolder(id: UUID) async throws
    func loadTracks(folderID: UUID?) async throws -> [Track]
    func applySuccessfulScan(folderID: UUID, tracks: [Track], scannedAt: Date) async throws
    func loadQueue() async throws -> QueueSnapshot
    func saveQueue(_ snapshot: QueueSnapshot) async throws
    func loadPlaylists() async throws -> [Playlist]
    func savePlaylist(_ playlist: Playlist) async throws
    func deletePlaylist(id: UUID) async throws
    func loadFavorites() async throws -> [Favorite]
    func saveFavorite(_ favorite: Favorite) async throws
    func deleteFavorite(trackID: Track.ID) async throws
    func deleteAllFavorites() async throws
    func loadPlaybackEvents() async throws -> [PlaybackEvent]
    func savePlaybackEvent(_ event: PlaybackEvent) async throws
    func deleteAllPlaybackEvents() async throws
    func mergeBackup(playlists: [Playlist], favorites: [Favorite], events: [PlaybackEvent]) async throws
}

public protocol BookmarkStoring: Sendable {
    func save(_ data: Data) throws
    func load() throws -> Data?
    func remove() throws
}
