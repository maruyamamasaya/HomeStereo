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
    @State private var store: RendererPlaybackStore
    @State private var library: LibraryStore
    @State private var queue: QueueStore
    @State private var playlists: PlaylistStore
    @State private var listening: ListeningStore
    @State private var recovery: RecoveryStore
    @State private var backup: BackupStore
    private let systemPlayback: SystemPlaybackIntegration

    init() {
        let repository: SQLiteLibraryRepository
        do { repository = try SQLiteLibraryRepository() }
        catch { fatalError("Library databaseを初期化できません: \(error.localizedDescription)") }
        let playback = RendererPlaybackStore(
            discovery: RendererDiscoveryService(), descriptions: DeviceDescriptionService(),
            fileSelection: MediaFileSelectionService(), serverFactory: LocalMediaHTTPServerFactory(),
            controller: UPnPRendererController(), activityManager: MacPlaybackActivityManager()
        )
        let libraryStore = LibraryStore(
            scanner: LibraryService(), folderAccess: FolderAccessService(), repository: repository
        )
        _store = State(initialValue: playback)
        _library = State(initialValue: libraryStore)
        let queueStore = QueueStore(repository: repository, library: libraryStore, playback: playback)
        _queue = State(initialValue: queueStore)
        let playlistStore = PlaylistStore(
            repository: repository, library: libraryStore, queue: queueStore, files: PlaylistFileService()
        )
        _playlists = State(initialValue: playlistStore)
        let listeningStore = ListeningStore(repository: repository, library: libraryStore, queue: queueStore)
        _listening = State(initialValue: listeningStore)
        _recovery = State(initialValue: RecoveryStore(
            monitor: MacSystemEventMonitor(), playback: playback, queue: queueStore, listening: listeningStore
        ))
        _backup = State(initialValue: BackupStore(
            repository: repository, library: libraryStore, playlists: playlistStore,
            listening: listeningStore, files: BackupFileService()
        ))
        systemPlayback = SystemPlaybackIntegration(queue: queueStore, playback: playback, library: libraryStore)
    }

    var body: some Scene {
        WindowGroup("HomeStereo", id: "main") {
            DLNAContentView(store: store, library: library, queue: queue, playlists: playlists, listening: listening, recovery: recovery, backup: backup)
                .background(WindowFrameAutosave(name: "HomeStereo.MainWindow.CompactV1"))
                .task { recovery.start(); await library.load(); await queue.restore(); await playlists.load(); await listening.load(); await store.discoverRenderers() }
                .onDisappear { recovery.stop(); library.pauseMonitoring(); Task { await listening.flush() }; library.releasePlaybackAccess(); store.shutdown() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { Task { await listening.flush() } }
                }
        }
        .defaultSize(width: 820, height: 620)
        Window("Mini Player", id: "mini-player") {
            MiniPlayerView(playback: store, queue: queue, library: library)
                .background(WindowFrameAutosave(name: "HomeStereo.MiniPlayer"))
        }
        .defaultSize(width: 430, height: 130)
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarPlaybackView(playback: store, queue: queue)
        } label: {
            Label(queue.currentTrack?.title ?? "HomeStereo", systemImage: store.playbackState == .playing ? "speaker.wave.2.fill" : "speaker")
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("音楽フォルダを追加…") { Task { await library.addFolder() } }
                    .keyboardShortcut("o", modifiers: .command)
                Button("音源ファイルを開く…") { store.chooseFile() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Libraryを検索") {
                    store.destination = .songs
                    library.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("再生") {
                Button(store.playbackState == .playing ? "一時停止" : "再生") { Task { await store.togglePlayback() } }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(store.media == nil || store.selectedDevice?.supportsAVTransport != true)
                Button("停止") { Task { await queue.stop() } }
                Divider()
                Button("前の曲") { Task { await queue.previous() } }
                Button("次の曲") { Task { await queue.next() } }
            }
        }
    }
}
