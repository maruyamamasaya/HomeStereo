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
