#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

@main
struct HomeStereoApp: App {
    @State private var store = PlaybackStore(
        playback: AudioPlaybackService(),
        library: LibraryService(),
        folderAccess: FolderAccessService()
    )

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 760, minHeight: 480)
                .task { await store.restoreLibrary() }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("音楽フォルダを開く…") {
                    Task { await store.chooseFolder() }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("再生") {
                Button(store.playbackState == .playing ? "一時停止" : "再生") {
                    store.togglePlayback()
                }
                .disabled(store.currentTrack == nil)
                Button("前の曲") { store.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("次の曲") { store.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
    }
}
