#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
import AppKit
import SwiftUI

struct MenuBarPlaybackView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore

    var body: some View {
        Text(queue.currentTrack?.title ?? "再生中の曲はありません")
        if let track = queue.currentTrack { Text(track.artist ?? "—").foregroundStyle(.secondary) }
        Divider()
        Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
        Button(playback.playbackState == .playing ? "一時停止" : "再生", systemImage: playback.playbackState == .playing ? "pause.fill" : "play.fill") {
            Task { await queue.togglePlayback() }
        }
        Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
        Divider()
        Button("小型プレイヤーを開く") { openWindow(id: "mini-player") }
        Button("メイン画面を開く") { openWindow(id: "main") }
    }
}

struct MiniPlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            if let track = queue.currentTrack {
                CachedArtwork(track: track, library: library, size: 72)
            } else {
                Image(systemName: "music.note").font(.largeTitle).frame(width: 72, height: 72)
                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Artworkなし")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(queue.currentTrack?.title ?? "再生中の曲はありません").font(.headline).lineLimit(2)
                Text(queue.currentTrack?.artist ?? "—").foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }.labelStyle(.iconOnly)
                    Button(playback.playbackState == .playing ? "一時停止" : "再生", systemImage: playback.playbackState == .playing ? "pause.fill" : "play.fill") {
                        Task { await queue.togglePlayback() }
                    }.labelStyle(.iconOnly)
                    Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }.labelStyle(.iconOnly)
                    Spacer()
                    Button("メイン画面を開く", systemImage: "macwindow") { openWindow(id: "main") }.labelStyle(.iconOnly)
                }
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
    }
}

struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.setFrameAutosaveName(name) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.setFrameAutosaveName(name) }
    }
}
