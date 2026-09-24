import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class LibraryStore {
    public private(set) var folders: [LibraryFolder] = []
    public private(set) var tracks: [Track] = []
    public private(set) var scanProgress: ScanProgress?
    public private(set) var scanNotices: [ScanNotice] = []
    public private(set) var scanningFolderID: UUID?
    public private(set) var message: String?
    public var selectedTrackID: Track.ID?
    public var selectedTrackIDs = Set<Track.ID>()
    public var searchText = "" { didSet { scheduleBrowserRebuild() } }
    public var sort: LibrarySort = .title { didSet { scheduleBrowserRebuild(immediate: true) } }
    public private(set) var visibleTracks: [Track] = []
    public private(set) var albums: [LibraryAlbum] = []
    public private(set) var artists: [LibraryArtist] = []
    public private(set) var totalFilteredTracks = 0
    public private(set) var displayLimit = 150
    public private(set) var autoUpdateEnabled: Bool
    public private(set) var lastAutomaticUpdate: Date?
    public private(set) var searchFocusRequest = UUID()

    @ObservationIgnored private let scanner: any LibraryScanning
    @ObservationIgnored private let folderAccess: any FolderAccessServicing
    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var playbackScopedRoot: URL?
    @ObservationIgnored private let artworkCache = ArtworkCache()
    @ObservationIgnored private let changeMonitor: any FolderChangeMonitoring
    @ObservationIgnored private let lifecycleMonitor: any SystemEventMonitoring
    @ObservationIgnored private var changeTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var monitoredRoots: [UUID: URL] = [:]
    @ObservationIgnored private var scanGeneration = UUID()
    @ObservationIgnored private let changeDebounce: Duration
    @ObservationIgnored private var browserTask: Task<Void, Never>?
    @ObservationIgnored private var indexedTracks: [Track] = []

    public convenience init(
        scanner: any LibraryScanning, folderAccess: any FolderAccessServicing, repository: any LibraryPersisting
    ) {
        self.init(
            scanner: scanner, folderAccess: folderAccess, repository: repository,
            changeMonitor: FolderChangeMonitor(), lifecycleMonitor: MacSystemEventMonitor(), changeDebounce: .seconds(2)
        )
    }

    public init(
        scanner: any LibraryScanning, folderAccess: any FolderAccessServicing, repository: any LibraryPersisting,
        changeMonitor: any FolderChangeMonitoring, lifecycleMonitor: any SystemEventMonitoring,
        changeDebounce: Duration
    ) {
        self.scanner = scanner
        self.folderAccess = folderAccess
        self.repository = repository
        self.changeMonitor = changeMonitor
        self.lifecycleMonitor = lifecycleMonitor
        self.changeDebounce = changeDebounce
        self.autoUpdateEnabled = UserDefaults.standard.object(forKey: "LibraryAutoUpdateEnabled") as? Bool ?? true
        self.lastAutomaticUpdate = UserDefaults.standard.object(forKey: "LibraryLastAutomaticUpdate") as? Date
        lifecycleMonitor.start { [weak self] event in
            switch event {
            case .willSleep: self?.pauseMonitoring()
            case .didWake: Task { await self?.resumeMonitoring(rescan: true) }
            case .networkAvailable: break
            }
        }
    }

    deinit { scanTask?.cancel(); browserTask?.cancel(); changeTasks.values.forEach { $0.cancel() } }

    public func load() async {
        do {
            folders = try await repository.loadFolders()
            tracks = try await repository.loadTracks(folderID: nil)
            scheduleBrowserRebuild(immediate: true)
            if autoUpdateEnabled, monitoredRoots.isEmpty { await resumeMonitoring(rescan: false) }
        } catch { show(error) }
    }

    public func addFolder() async {
        guard let url = folderAccess.chooseFolder() else { return }
        do {
            let normalized = Self.normalizedPath(url.path)
            guard !folders.contains(where: { Self.normalizedPath($0.path) == normalized }) else {
                throw UserFacingError.duplicateFolder
            }
            let folder = LibraryFolder(displayName: url.lastPathComponent, path: url.standardizedFileURL.path)
            try await repository.addFolder(folder, bookmarkData: folderAccess.makeBookmark(for: url))
            await load()
            scanFolder(folder.id)
        } catch { show(error) }
    }

    public func removeFolder(_ id: UUID) async {
        do {
            if scanningFolderID == id { cancelScan() }
            try await repository.removeFolder(id: id)
            await load()
        } catch { show(error) }
    }

    public func scanFolder(_ id: UUID) {
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        scanTask = Task { [weak self] in
            guard let self else { return }
            scanningFolderID = id
            scanProgress = ScanProgress()
            scanNotices = []
            defer {
                if scanGeneration == generation { scanningFolderID = nil; scanTask = nil }
            }
            do {
                guard let persisted = try await repository.loadFolder(id: id) else { return }
                let resolution = try folderAccess.resolveBookmark(persisted.bookmarkData)
                if let refreshed = resolution.refreshedBookmark {
                    try await repository.updateBookmark(
                        folderID: id, bookmarkData: refreshed, path: resolution.url.path,
                        displayName: resolution.url.lastPathComponent
                    )
                }
                guard folderAccess.beginAccessing(resolution.url) else { throw UserFacingError.folderAccessLost }
                defer { folderAccess.stopAccessing(resolution.url) }
                let existing = try await repository.loadTracks(folderID: id)
                let result = try await scanner.scan(
                    folder: persisted.folder, resolvedURL: resolution.url, existingTracks: existing
                ) { value in
                    await self.updateScanProgress(value, generation: generation)
                }
                try Task.checkCancellation()
                guard scanGeneration == generation else { return }
                try await repository.applySuccessfulScan(folderID: id, tracks: result.tracks, scannedAt: .now)
                scanProgress = result.progress
                scanNotices = result.notices
                await load()
            } catch is CancellationError {
                scanProgress?.isCancelled = true
            } catch {
                try? await repository.setFolderAccessState(id: id, state: .needsReselection)
                show(error)
                await load()
            }
        }
    }

    public func scanAll() async {
        for folder in folders {
            if Task.isCancelled { return }
            scanFolder(folder.id)
            await scanTask?.value
        }
    }

    public func cancelScan() { scanTask?.cancel() }

    public func setAutoUpdateEnabled(_ enabled: Bool) async {
        autoUpdateEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "LibraryAutoUpdateEnabled")
        if enabled { await resumeMonitoring(rescan: false) } else { pauseMonitoring() }
    }

    public func pauseMonitoring() {
        changeMonitor.stop()
        changeTasks.values.forEach { $0.cancel() }
        changeTasks = [:]
        for url in monitoredRoots.values { folderAccess.stopAccessing(url) }
        monitoredRoots = [:]
    }

    public func resumeMonitoring(rescan: Bool) async {
        guard autoUpdateEnabled else { return }
        pauseMonitoring()
        var roots: [UUID: URL] = [:]
        for folder in folders {
            guard let persisted = try? await repository.loadFolder(id: folder.id),
                  let resolution = try? folderAccess.resolveBookmark(persisted.bookmarkData),
                  folderAccess.beginAccessing(resolution.url) else { continue }
            roots[folder.id] = resolution.url
        }
        monitoredRoots = roots
        changeMonitor.watch(roots) { [weak self] id in self?.folderDidChange(id) }
        if rescan { await scanAll() }
    }

    public func prepareTrack(_ id: Track.ID) async -> URL? {
        guard let track = tracks.first(where: { $0.id == id }), track.scanState == .available else { return nil }
        do {
            guard let persisted = try await repository.loadFolder(id: track.libraryFolderID) else {
                throw UserFacingError.folderUnavailable
            }
            let resolution = try folderAccess.resolveBookmark(persisted.bookmarkData)
            releasePlaybackAccess()
            guard folderAccess.beginAccessing(resolution.url) else { throw UserFacingError.folderAccessLost }
            playbackScopedRoot = resolution.url
            let url = resolution.url.appendingPathComponent(track.relativePath)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                releasePlaybackAccess(); throw UserFacingError.folderUnavailable
            }
            return url
        } catch { show(error); return nil }
    }

    public func artworkData(for track: Track, pixelSize: Int = 256) async -> Data? {
        if track.artworkData != nil {
            return await artworkCache.data(for: track, fileURL: track.url, pixelSize: pixelSize)
        }
        do {
            guard let persisted = try await repository.loadFolder(id: track.libraryFolderID) else { return nil }
            let resolution = try folderAccess.resolveBookmark(persisted.bookmarkData)
            guard folderAccess.beginAccessing(resolution.url) else { return nil }
            defer { folderAccess.stopAccessing(resolution.url) }
            return await artworkCache.data(for: track, fileURL: resolution.url.appendingPathComponent(track.relativePath), pixelSize: pixelSize)
        } catch { return nil }
    }

    public func releasePlaybackAccess() {
        if let playbackScopedRoot { folderAccess.stopAccessing(playbackScopedRoot) }
        playbackScopedRoot = nil
    }

    public func dismissMessage() { message = nil }
    public func requestSearchFocus() { searchFocusRequest = UUID() }
    public var canLoadMoreTracks: Bool { visibleTracks.count < totalFilteredTracks }
    public func loadMoreTracks() {
        displayLimit += 150
        visibleTracks = Array(indexedTracks.prefix(displayLimit))
    }

    private func show(_ error: Error) {
        message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func scheduleBrowserRebuild(immediate: Bool = false) {
        browserTask?.cancel()
        displayLimit = 150
        let source = tracks, query = searchText, selectedSort = sort
        browserTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let index = await Task.detached(priority: .userInitiated) {
                LibraryBrowserIndex(tracks: source, search: query, sort: selectedSort)
            }.value
            guard let self, !Task.isCancelled, self.searchText == query, self.sort == selectedSort else { return }
            indexedTracks = index.tracks
            totalFilteredTracks = index.tracks.count
            visibleTracks = Array(index.tracks.prefix(displayLimit))
            albums = index.albums; artists = index.artists
        }
    }

    private func updateScanProgress(_ value: ScanProgress, generation: UUID) {
        guard scanGeneration == generation else { return }
        scanProgress = value
    }

    private func folderDidChange(_ id: UUID) {
        guard autoUpdateEnabled else { return }
        changeTasks[id]?.cancel()
        let debounce = changeDebounce
        changeTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard let self, !Task.isCancelled else { return }
            scanFolder(id)
            await scanTask?.value
            guard !Task.isCancelled else { return }
            lastAutomaticUpdate = .now
            UserDefaults.standard.set(lastAutomaticUpdate, forKey: "LibraryLastAutomaticUpdate")
            changeTasks[id] = nil
        }
    }
}
