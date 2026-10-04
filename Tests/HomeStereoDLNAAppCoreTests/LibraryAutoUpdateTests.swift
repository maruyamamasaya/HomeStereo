import Foundation
import HomeStereoAppCore
import Testing
@testable import HomeStereoDLNAAppCore

@MainActor
@Test func folderEventsAreDebouncedIntoDifferentialScan() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
    let folder = LibraryFolder(displayName: "Music", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data([1]))
    let scanner = CountingScanner()
    let monitor = TestFolderMonitor()
    let store = LibraryStore(
        scanner: scanner, folderAccess: TestFolderAccess(url: root), repository: repository,
        changeMonitor: monitor, lifecycleMonitor: TestSystemMonitor(), changeDebounce: .zero
    )
    await store.load()
    await store.setAutoUpdateEnabled(true)

    monitor.emit(folder.id)
    monitor.emit(folder.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(await scanner.scanCount == 1)
    #expect(store.lastAutomaticUpdate != nil)
}

@MainActor
@Test func automaticScanWaitsUntilPlaybackStops() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("library.sqlite3"))
    let folder = LibraryFolder(displayName: "Music", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data([1]))
    let scanner = CountingScanner()
    let monitor = TestFolderMonitor()
    let store = LibraryStore(
        scanner: scanner, folderAccess: TestFolderAccess(url: root), repository: repository,
        changeMonitor: monitor, lifecycleMonitor: TestSystemMonitor(), changeDebounce: .zero
    )
    await store.load()
    await store.setAutoUpdateEnabled(true)
    store.setPlaybackActive(true)

    monitor.emit(folder.id)
    try await Task.sleep(for: .milliseconds(100))
    #expect(await scanner.scanCount == 0)

    store.setPlaybackActive(false)
    try await Task.sleep(for: .seconds(2.1))
    #expect(await scanner.scanCount == 1)
}

private actor CountingScanner: LibraryScanning {
    private(set) var scanCount = 0
    func scan(folder: URL) async throws -> [Track] { [] }
    func scan(
        folder: LibraryFolder, resolvedURL: URL, existingTracks: [Track],
        progress: @escaping @Sendable (ScanProgress) async -> Void
    ) async throws -> LibraryScanResult {
        scanCount += 1
        return LibraryScanResult(tracks: existingTracks, progress: ScanProgress(), notices: [])
    }
}

@MainActor
private final class TestFolderMonitor: FolderChangeMonitoring {
    private var handler: ((UUID) -> Void)?
    func watch(_ folders: [UUID: URL], handler: @escaping @MainActor (UUID) -> Void) { self.handler = handler }
    func stop() { handler = nil }
    func emit(_ id: UUID) { handler?(id) }
}

@MainActor
private final class TestSystemMonitor: SystemEventMonitoring {
    func start(_ handler: @escaping @MainActor (SystemPlaybackEvent) -> Void) {}
    func stop() {}
}

@MainActor
private final class TestFolderAccess: FolderAccessServicing {
    let url: URL
    init(url: URL) { self.url = url }
    func chooseFolder() -> URL? { nil }
    func makeBookmark(for folder: URL) throws -> Data { Data([1]) }
    func resolveBookmark(_ data: Data) throws -> BookmarkResolution { BookmarkResolution(url: url) }
    func saveBookmark(for folder: URL) throws {}
    func restoreFolder() throws -> URL? { nil }
    func beginAccessing(_ folder: URL) -> Bool { true }
    func stopAccessing(_ folder: URL) {}
}

@MainActor
@Test func genrePresetAndRapidSortRefreshAllBrowserCollectionsTogether() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("genre.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data([1]))
    let jazz = Track(libraryFolderID: folder.id, relativePath: "jazz.mp3", url: root.appendingPathComponent("jazz.mp3"), title: "Jazz", artist: "Jazz Artist", album: "Jazz Album", genre: "Jazz")
    let rock = Track(libraryFolderID: folder.id, relativePath: "rock.mp3", url: root.appendingPathComponent("rock.mp3"), title: "Rock", artist: "Rock Artist", album: "Rock Album", genre: "Rock")
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: [jazz, rock], scannedAt: .now)
    let store = LibraryStore(scanner: CountingScanner(), folderAccess: TestFolderAccess(url: root), repository: repository, changeMonitor: TestFolderMonitor(), lifecycleMonitor: TestSystemMonitor(), changeDebounce: .zero)
    defer { store.pauseMonitoring() }
    await store.load()
    store.applyGenrePreset(GenreDisplayPreset(name: "Jazz", enabledGenreNames: ["Jazz"]))
    store.setSort(.artist, direction: .descending)
    for _ in 0..<100 {
        if store.visibleTracks.map(\.id) == [jazz.id] && store.albums.map(\.title) == ["Jazz Album"] { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.visibleTracks.map(\.id) == [jazz.id])
    #expect(store.albums.flatMap { $0.tracks.map(\.id) } == [jazz.id])
    #expect(store.artists.flatMap { $0.tracks.map(\.id) } == [jazz.id])
    store.applySingleGenre("Rock")
    for _ in 0..<100 {
        if store.visibleTracks.map(\.id) == [rock.id] && store.albums.map(\.title) == ["Rock Album"] { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.artists.map(\.name) == ["Rock Artist"])
    store.applyGenrePreset(nil)
    for _ in 0..<100 {
        if store.visibleTracks.count == 2 && store.albums.count == 2 { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(store.visibleTracks.count == 2)
    #expect(store.albums.count == 2)
    #expect(store.artists.count == 2)
}
