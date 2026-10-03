#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import SwiftUI

struct MenuBarPlaybackView: View {
    @Environment(\.openWindow) private var openWindow
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var preferences: PlaybackPreferenceStore

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
        if let track = queue.nowPlayingTrack {
            let value = preferences.preference(for: track.id)
            Text("評価: \(value > 0 ? "+" : "")\(value)（−10〜+10）")
            Button("Good (+1)", systemImage: value > 0 ? "hand.thumbsup.fill" : "hand.thumbsup") {
                Task { await preferences.adjustPreference(trackID: track.id, delta: 1) }
            }
            .disabled(value >= 10)
            Button("Bad (−1)", systemImage: value < 0 ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                Task { await preferences.adjustPreference(trackID: track.id, delta: -1) }
            }
            .disabled(value <= -10)
            Divider()
        }
        if let error = preferences.errorMessage {
            Text("評価を保存できませんでした: \(error)")
        }
        Button("小型プレイヤーを開く") { openWindow(id: "mini-player") }
        Button("メイン画面を開く") { openWindow(id: "main") }
    }

    private var playbackDisabled: Bool {
        !queue.nowPlaying.hasMedia || !playback.canPlaySelectedOutput || playback.isBusy
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
    @Bindable var preferences: PlaybackPreferenceStore
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
                    NowPlayingPreferenceControls(queue: queue, preferences: preferences)
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
        if !playback.hasSelectedOutput { return "先に再生先を選んでください" }
        if !playback.canPlaySelectedOutput { return "選択した機器は再生操作に対応していません" }
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

struct NowPlayingPreferenceControls: View {
    @Bindable var queue: QueueStore
    @Bindable var preferences: PlaybackPreferenceStore

    var body: some View {
        if let track = queue.nowPlayingTrack {
            let value = preferences.preference(for: track.id)
            HStack(spacing: 10) {
                ratingButton(track: track, value: value, delta: 1)
                ratingButton(track: track, value: value, delta: -1)
            }
            .overlay(alignment: .topTrailing) {
                if preferences.errorMessage != nil {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("評価を保存できませんでした: \(preferences.errorMessage ?? "")")
                        .offset(x: 8, y: -8)
                }
            }
        }
    }

    private func ratingButton(track: Track, value: Int, delta: Int) -> some View {
        let isGood = delta == 1
        let active = isGood ? value > 0 : value < 0
        let symbol = isGood ? "hand.thumbsup" : "hand.thumbsdown"
        let color: Color = active ? (isGood ? .green : .orange) : .secondary
        return Button {
            Task { await preferences.adjustPreference(trackID: track.id, delta: delta) }
        } label: {
            Image(systemName: symbol + (active ? ".fill" : ""))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(active ? abs(value) : 0)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(color, in: Capsule())
                        .offset(x: 4, y: 3)
                        .accessibilityHidden(true)
                }
        }
        .buttonStyle(.plain)
        .disabled(isGood ? value >= 10 : value <= -10)
        .help("\(isGood ? "Good +1" : "Bad −1")（現在 \(value)、−10〜+10）")
        .accessibilityLabel("\(track.title)の\(isGood ? "Good評価を1増やす" : "Bad評価を1減らす")")
        .accessibilityValue("現在 \(value)、−10から+10")
    }
}
