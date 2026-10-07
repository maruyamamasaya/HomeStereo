#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

@main
struct HomeStereoDLNAApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HomeStereoTheme.storageKey) private var storedTheme = HomeStereoTheme.system.rawValue
    @State private var store: RendererPlaybackStore
    @State private var library: LibraryStore
    @State private var queue: QueueStore
    @State private var playlists: PlaylistStore
    @State private var listening: ListeningStore
    @State private var analytics: AnalyticsStore
    @State private var preferences: PlaybackPreferenceStore
    @State private var genrePresets: GenreDisplayPresetStore
    @State private var recovery: RecoveryStore
    @State private var backup: BackupStore
    @State private var myMusic: MyMusicTransferStore
    @State private var myMusicStatus: MyMusicStatusStore
    @State private var developer: MyMusicJSONEditorStore
    @State private var features: TrackFeatureStore
    private let systemPlayback: SystemPlaybackIntegration

    private var selectedTheme: HomeStereoTheme {
        HomeStereoTheme(rawValue: storedTheme) ?? .system
    }

    init() {
        let repository: SQLiteLibraryRepository
        let stateBackup: StateBackupService
        do {
            stateBackup = StateBackupService(root: try StateBackupService.defaultRoot())
            try stateBackup.applyPendingRestore()
            repository = try SQLiteLibraryRepository()
        }
        catch { fatalError("Library databaseを初期化できません: \(error.localizedDescription)") }
        let featureStore: TrackFeatureStore
        do {
            featureStore = TrackFeatureStore(library: repository,
                archive: FeatureRepository(url: try FeatureRepository.defaultURL()), files: MyMusicFileService())
            _features = State(initialValue: featureStore)
        } catch { fatalError("特徴量保存先を初期化できません: \(error.localizedDescription)") }
        let playback = RendererPlaybackStore(
            discovery: RendererDiscoveryService(), descriptions: DeviceDescriptionService(),
            fileSelection: MediaFileSelectionService(), serverFactory: LocalMediaHTTPServerFactory(),
            controller: UPnPRendererController(), secondaryController: UPnPRendererController(),
            activityManager: MacPlaybackActivityManager()
        )
        let libraryStore = LibraryStore(
            scanner: LibraryService(), folderAccess: FolderAccessService(), repository: repository
        )
        featureStore.onPlaybackFeatures = { [weak playback] values, enabled in
            playback?.configureNormalization(features: values, enabled: enabled)
        }
        _store = State(initialValue: playback)
        _library = State(initialValue: libraryStore)
        let queueStore = QueueStore(repository: repository, library: libraryStore, playback: playback)
        let previousTracksChanged = libraryStore.onTracksChanged
        libraryStore.onTracksChanged = {
            previousTracksChanged?()
            Task { await featureStore.load() }
        }
        _queue = State(initialValue: queueStore)
        let playlistStore = PlaylistStore(
            repository: repository, library: libraryStore, queue: queueStore, files: PlaylistFileService()
        )
        _playlists = State(initialValue: playlistStore)
        let listeningStore = ListeningStore(
            repository: repository, library: libraryStore, queue: queueStore,
            myMusicRepository: repository
        )
        _listening = State(initialValue: listeningStore)
        let analyticsStore = AnalyticsStore(repository: repository)
        _analytics = State(initialValue: analyticsStore)
        let preferenceStore = PlaybackPreferenceStore(repository: repository)
        _preferences = State(initialValue: preferenceStore)
        let genrePresetStore = GenreDisplayPresetStore(repository: repository, files: MyMusicFileService())
        _genrePresets = State(initialValue: genrePresetStore)
        genrePresetStore.onChange = { presets in
            guard let selectedID = libraryStore.selectedGenrePresetID else { return }
            libraryStore.applyGenrePreset(presets.first { $0.id == selectedID })
        }
        preferenceStore.onChange = { analyticsStore.invalidate() }
        listeningStore.onAnalyticsRevision = { _ in
            analyticsStore.invalidate()
        }
        _recovery = State(initialValue: RecoveryStore(
            monitor: MacSystemEventMonitor(), playback: playback, queue: queueStore, listening: listeningStore
        ))
        _backup = State(initialValue: BackupStore(
            repository: repository, library: libraryStore, playlists: playlistStore,
            listening: listeningStore, files: BackupFileService(),
            stateBackup: stateBackup
        ))
        let myMusicStatusStore = MyMusicStatusStore(repository: repository)
        _myMusicStatus = State(initialValue: myMusicStatusStore)
        _developer = State(initialValue: MyMusicJSONEditorStore(
            repository: repository, files: MyMusicFileService()
        ))
        _myMusic = State(initialValue: MyMusicTransferStore(
            repository: repository, files: MyMusicFileService()
        ) { kind in
            if kind == .playlists { await playlistStore.load() }
            if kind == .preferences { await listeningStore.load(); await preferenceStore.load() }
            if kind == .library || kind == .preferences || kind == .playbackEvents {
                analyticsStore.invalidate()
            }
            await myMusicStatusStore.load()
        })
        systemPlayback = SystemPlaybackIntegration(queue: queueStore, playback: playback, library: libraryStore)
    }

    var body: some Scene {
        WindowGroup("HomeStereo", id: "main") {
            HomeStereoThemeRoot(theme: selectedTheme) {
                DLNAContentView(
                    store: store, library: library, queue: queue, playlists: playlists,
                    listening: listening, analytics: analytics, preferences: preferences,
                    genrePresets: genrePresets,
                    recovery: recovery, backup: backup, myMusic: myMusic,
                    myMusicStatus: myMusicStatus, features: features, developer: developer
                )
                    .background(WindowFrameAutosave(name: "HomeStereo.MainWindow.CompactV1"))
            }
                .task {
                    recovery.start(); await library.load(); await genrePresets.load(); await queue.restore(); await playlists.load()
                    await listening.load(); await preferences.load(); await features.load(); await store.discoverRenderers()
                }
                .onDisappear { recovery.stop(); library.pauseMonitoring(); Task { await listening.flush() }; library.releasePlaybackAccess(); store.shutdown() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await listening.flush() } }
                }
        }
        .defaultSize(width: 1_280, height: 760)
        Window("Mini Player", id: "mini-player") {
            HomeStereoThemeRoot(theme: selectedTheme) {
                MiniPlayerView(playback: store, queue: queue, preferences: preferences, library: library)
                    .background(WindowFrameAutosave(name: "HomeStereo.MiniPlayer"))
            }
        }
        .defaultSize(width: 430, height: 130)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            HomeStereoThemeRoot(theme: selectedTheme) {
                MenuBarPlaybackView(playback: store, queue: queue, preferences: preferences)
            }
        } label: {
            Label(queue.nowPlaying.title ?? "HomeStereo", systemImage: queue.nowPlaying.state == .playing ? "speaker.wave.2.fill" : "speaker")
        }
        Settings {
            HomeStereoThemeRoot(theme: selectedTheme) {
                HomeStereoThemeSettingsView()
            }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("音楽フォルダを追加…") { Task { await library.addFolder() } }
                    .keyboardShortcut("o", modifiers: .command)
                Button("音源ファイルを開く…") { store.chooseFile() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("ライブラリを検索") {
                    store.destination = .songs
                    library.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("再生") {
                Button(queue.nowPlaying.state == .playing ? "一時停止" : "再生") { Task { await queue.togglePlayback() } }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!queue.nowPlaying.hasMedia || !store.canPlaySelectedOutput || store.isBusy)
                Button("停止") { Task { await queue.stop() } }
                Divider()
                Button("前の曲") { Task { await queue.previous() } }
                    .disabled(!queue.nowPlaying.isQueueTrack || store.isBusy)
                Button("次の曲") { Task { await queue.next() } }
                    .disabled(!queue.nowPlaying.isQueueTrack || store.isBusy)
            }
            CommandMenu("表示") {
                Picker("テーマ", selection: $storedTheme) {
                    ForEach(HomeStereoTheme.allCases) { theme in
                        Label(theme.title, systemImage: theme.symbol).tag(theme.rawValue)
                    }
                }
            }
        }
    }
}
