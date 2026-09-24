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
        Text(queue.nowPlaying.title ?? emptyTitle)
        Text(queue.nowPlaying.artist ?? stateLabel).foregroundStyle(.secondary)
        Divider()
        Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
            .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
        Button(queue.nowPlaying.state == .playing ? "一時停止" : "再生", systemImage: queue.nowPlaying.state == .playing ? "pause.fill" : "play.fill") {
            Task { await queue.togglePlayback() }
        }
        .disabled(playbackDisabled)
        Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
            .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
        Divider()
        Button("小型プレイヤーを開く") { openWindow(id: "mini-player") }
        Button("メイン画面を開く") { openWindow(id: "main") }
    }

    private var playbackDisabled: Bool {
        !queue.nowPlaying.hasMedia || playback.selectedDevice?.supportsAVTransport != true || playback.isBusy
    }

    private var emptyTitle: String {
        queue.nowPlaying.state == .unknown ? "再生状態を確認できません" : "再生中の曲はありません"
    }

    private var stateLabel: String { playbackStateLabel(queue.nowPlaying.state) }
}

struct MiniPlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore

    var body: some View {
        HStack(spacing: 14) {
            if let track = queue.nowPlayingTrack {
                CachedArtwork(track: track, library: library, size: 72)
            } else {
                Image(systemName: "music.note").font(.largeTitle).frame(width: 72, height: 72)
                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Artworkなし")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(queue.nowPlaying.title ?? emptyTitle).font(.headline).lineLimit(2)
                Text(queue.nowPlaying.artist ?? playbackStateLabel(queue.nowPlaying.state)).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
                        .labelStyle(.iconOnly)
                        .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
                    Button(queue.nowPlaying.state == .playing ? "一時停止" : "再生", systemImage: queue.nowPlaying.state == .playing ? "pause.fill" : "play.fill") {
                        Task { await queue.togglePlayback() }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(playbackDisabled)
                    .help(playbackDisabledReason ?? "再生または一時停止")
                    Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
                        .labelStyle(.iconOnly)
                        .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
                    Spacer()
                    Button("メイン画面を開く", systemImage: "macwindow") { openWindow(id: "main") }.labelStyle(.iconOnly)
                }
            }
        }
        .padding()
        .accessibilityElement(children: .contain)
    }

    private var emptyTitle: String {
        queue.nowPlaying.state == .unknown ? "再生状態を確認できません" : "再生中の曲はありません"
    }

    private var playbackDisabled: Bool { playbackDisabledReason != nil }

    private var playbackDisabledReason: String? {
        if playback.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if playback.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if !queue.nowPlaying.hasMedia { return "先に曲を選んでください" }
        if playback.isBusy { return "Rendererの応答を待っています" }
        return nil
    }
}

private func playbackStateLabel(_ state: NowPlayingDisplayState) -> String {
    switch state {
    case .empty: "曲なし"
    case .loading: "読込中"
    case .stopped: "停止中"
    case .playing: "再生中"
    case .paused: "一時停止"
    case .unknown: "通信不明"
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
