#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import SwiftUI

struct MiniPlayerView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(MiniPlayerStyle.storageKey) private var storedStyle = MiniPlayerStyle.smoke.rawValue
    @State private var window: NSWindow?
    @State private var ratingBusy = false
    @State private var favoriteBusy = false
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var preferences: PlaybackPreferenceStore
    @Bindable var listening: ListeningStore

    private var style: MiniPlayerStyle { MiniPlayerStyle(rawValue: storedStyle) ?? .smoke }
    private var reducedEffects: Bool { reduceTransparency || contrast == .increased }
    private var trackID: Track.ID? { queue.nowPlayingTrack?.id }
    private var favorite: Bool { trackID.map { listening.isFavorite($0) } ?? false }
    private var rating: Int { trackID.map { preferences.preference(for: $0) } ?? 0 }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                windowControls
                display.frame(minWidth: 240, maxWidth: .infinity)
                playbackControls
            }
            .padding(7)
            .background { MiniPlayerShell(style: style, reducedEffects: reducedEffects) }
            .contextMenu {
                MiniPlayerStylePicker()
                Button("メイン画面を開く") { openWindow(id: "main") }
                Button("Bad −1") { adjustRating(-1) }
                    .disabled(trackID == nil || rating <= -10 || ratingBusy)
            }
            if let error = preferences.errorMessage {
                Text("評価を保存できませんでした: \(error)").font(.caption).foregroundStyle(.red)
            }
            if let message = listening.message {
                Text(message).font(.caption).foregroundStyle(MiniPlayerAssets.display)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(minWidth: 630)
        .fixedSize(horizontal: false, vertical: true)
        .background(MiniPlayerWindow { window = $0 })
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
    }

    private var windowControls: some View {
        VStack(spacing: 5) {
            Button { window?.performClose(nil) } label: { Image(systemName: "xmark") }
                .help("小型プレイヤーを閉じる（再生は継続）")
                .accessibilityLabel("小型プレイヤーを閉じる")
            Button { window?.miniaturize(nil) } label: { Image(systemName: "minus") }
                .help("小型プレイヤーを最小化")
                .accessibilityLabel("小型プレイヤーを最小化")
        }
        .buttonStyle(MiniPlayerCeramicButtonStyle(diameter: 23))
        .padding(.horizontal, 9)
        .frame(height: 72)
        .background { MiniPlayerMetal(style: style) }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 33, bottomLeadingRadius: 33, bottomTrailingRadius: 6, topTrailingRadius: 6))
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(stateLabel)
                Spacer(minLength: 4)
                Text("\(favorite ? "♥ " : "")GOOD \(rating > 0 ? "+" : "")\(rating)")
            }
            .font(MiniPlayerAssets.font(10))
            .foregroundStyle(MiniPlayerAssets.display.opacity(0.8))
            MiniPlayerDisplayText(text: queue.nowPlaying.title ?? "曲を選んでください", fontSize: 14, lineHeight: 19)
                .help(queue.nowPlaying.title ?? "曲を選んでください")
            MiniPlayerDisplayText(text: queue.nowPlaying.artist ?? "未再生", fontSize: 11, lineHeight: 15)
                .help(queue.nowPlaying.artist ?? "未再生")
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(MiniPlayerAssets.display.opacity(0.18))
                    Capsule().fill(MiniPlayerAssets.display).frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 2)
            .accessibilityLabel("再生位置")
            .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
        }
        .foregroundStyle(MiniPlayerAssets.display)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(white: 0.19), Color(red: 0.025, green: 0.045, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.8), radius: reducedEffects ? 0 : 2, y: -1)
        }
        .overlay {
            if !reducedEffects {
                RoundedRectangle(cornerRadius: 7).fill(LinearGradient(stops: [.init(color: .white.opacity(0.13), location: 0), .init(color: .clear, location: 0.5)], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.35), lineWidth: 1) }
        .overlay { MiniPlayerDragArea().accessibilityHidden(true) }
        .help("ドラッグして移動。右クリックで外観の切り替えとメイン画面を開く")
    }

    private var playbackControls: some View {
        HStack(spacing: 7) {
            Button {
                guard let id = trackID, !favoriteBusy else { return }
                favoriteBusy = true
                Task { defer { favoriteBusy = false }; await listening.toggleFavorite(id) }
            } label: { Image(systemName: favorite ? "heart.fill" : "heart") }
                .buttonStyle(MiniPlayerCeramicButtonStyle(active: favorite))
                .disabled(trackID == nil || favoriteBusy)
                .help(favorite ? "お気に入りを解除" : "お気に入りに追加")
                .accessibilityLabel(favorite ? "お気に入りを解除" : "お気に入りに追加")
                .accessibilityValue(favorite ? "オン" : "オフ")
            Button { adjustRating(1) } label: { Image(systemName: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsup") }
                .buttonStyle(MiniPlayerCeramicButtonStyle(active: rating > 0))
                .disabled(trackID == nil || rating >= 15 || ratingBusy)
                .help("Good +1（現在 \(rating)）")
                .accessibilityLabel("Goodを1増やす")
                .accessibilityValue("現在 \(rating)、上限15")
            Button { Task { await queue.previous() } } label: { Image(systemName: "backward.end.fill") }
                .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
                .help("前の曲").accessibilityLabel("前の曲")
            Button { Task { await queue.togglePlayback() } } label: {
                Image(systemName: queue.nowPlaying.state == .playing ? "pause.fill" : "play.fill")
            }
            .buttonStyle(MiniPlayerCeramicButtonStyle(diameter: 38))
            .disabled(playbackDisabledReason != nil)
            .help(playbackDisabledReason ?? "再生／一時停止")
            .accessibilityLabel(queue.nowPlaying.state == .playing ? "一時停止" : "再生")
            Button { Task { await queue.next() } } label: { Image(systemName: "forward.end.fill") }
                .disabled(!queue.nowPlaying.isQueueTrack || playback.isBusy)
                .help("次の曲").accessibilityLabel("次の曲")
        }
        .buttonStyle(MiniPlayerCeramicButtonStyle(diameter: 26))
        .padding(.horizontal, 12)
        .frame(height: 72)
        .background { MiniPlayerMetal(style: style) }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 33, topTrailingRadius: 33))
    }

    private func adjustRating(_ delta: Int) {
        guard let id = trackID, !ratingBusy else { return }
        ratingBusy = true
        Task { defer { ratingBusy = false }; await preferences.adjustPreference(trackID: id, delta: delta) }
    }
    private var progress: Double {
        let value = queue.nowPlaying
        guard value.duration.isFinite, value.duration > 0, value.elapsed.isFinite else { return 0 }
        return min(1, max(0, value.elapsed / value.duration))
    }
    private var stateLabel: String {
        switch queue.nowPlaying.state {
        case .empty: "NO TRACK"
        case .loading: "LOADING"
        case .stopped: "STOPPED"
        case .playing: "▶ NOW PLAYING"
        case .paused: "PAUSED"
        case .unknown: "通信状態不明"
        }
    }
    private var playbackDisabledReason: String? {
        if !playback.hasSelectedOutput { return "先に再生先を選んでください" }
        if !playback.canPlaySelectedOutput { return "選択した機器は再生操作に対応していません" }
        if !queue.nowPlaying.hasMedia { return "先に曲を選んでください" }
        if playback.isBusy { return "Rendererの応答を待っています" }
        return nil
    }
}
