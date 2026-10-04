#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

enum ListeningViewMode: Equatable { case favorites, history }

struct ListeningView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var store: ListeningStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore
    @Bindable var playlists: PlaylistStore
    @Bindable var preferences: PlaybackPreferenceStore
    @Bindable var genrePresets: GenreDisplayPresetStore
    let mode: ListeningViewMode
    @State private var historySection = 0
    @State private var resetConfirmation: ListeningViewMode?

    var body: some View {
        VStack(spacing: 0) {
            if mode == .favorites { favorites }
            else { history }
        }
        .navigationTitle(mode == .favorites ? "お気に入り" : "再生履歴")
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = store.message {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("データを更新できませんでした").font(.callout.bold())
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("再読み込み") {
                        store.dismissMessage()
                        Task { await store.load() }
                    }
                    Button("閉じる", systemImage: "xmark") { store.dismissMessage() }
                        .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .homeStereoThemeBar()
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
            if mode == .history {
                CreateQueueButton(queue: queue, trackIDs: historyCandidateIDs)
            }
            Menu("管理", systemImage: "ellipsis.circle") {
                if mode == .favorites {
                    Button("お気に入りをすべて解除", role: .destructive) { resetConfirmation = .favorites }
                        .disabled(store.favorites.isEmpty)
                } else {
                    Button("再生履歴をすべて削除", role: .destructive) { resetConfirmation = .history }
                        .disabled(store.events.isEmpty)
                }
            }

                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
        .confirmationDialog(
            resetConfirmation == .favorites ? "お気に入りをすべて解除しますか？" : "再生履歴をすべて削除しますか？",
            isPresented: Binding(get: { resetConfirmation != nil }, set: { if !$0 { resetConfirmation = nil } })
        ) {
            if resetConfirmation == .favorites {
                Button("すべて解除", role: .destructive) { resetConfirmation = nil; Task { await store.resetFavorites() } }
            } else {
                Button("履歴をすべて削除", role: .destructive) { resetConfirmation = nil; Task { await store.resetHistory() } }
            }
        } message: {
            Text(resetConfirmation == .favorites
                 ? "曲のファイルと再生履歴は削除されません。"
                 : "曲のファイルとお気に入りは削除されません。")
        }
    }

    private var favorites: some View {
        LibraryView(
            playback: playback, library: library, queue: queue, playlists: playlists,
            listening: store, preferences: preferences, genrePresets: genrePresets,
            mode: .songs, scope: .favorites
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {  favoritePlaybackButtons
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $historySection) {
                Text("最近再生").tag(0)
                Text("よく聴く").tag(1)
                Text("未再生").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Group {
                if historySection == 0 { recentHistory }
                else if historySection == 1 { frequentHistory }
                else { unplayedHistory }
            }
        }
    }

    @ViewBuilder
    private var recentHistory: some View {
        if store.events.isEmpty {
            historyEmptyView(
                title: "再生履歴はありません", description: "曲を再生すると、最近聴いた曲がここに表示されます。",
                systemImage: "clock.arrow.circlepath"
            )
        } else {
            List(store.recentEvents) { event in
                trackRow(
                    trackID: event.trackID,
                    detail: "\(event.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(event.outcome == .completed ? "最後まで再生" : "途中まで再生")"
                )
            }
        }
    }

    @ViewBuilder
    private var frequentHistory: some View {
        if store.frequentTracks.isEmpty {
            historyEmptyView(
                title: "再生回数の記録がありません", description: "何度か曲を再生すると、よく聴く曲を確認できます。",
                systemImage: "chart.bar"
            )
        } else {
            List(store.frequentTracks) { value in
                trackRow(trackID: value.trackID, detail: "\(value.playCount)回再生")
            }
        }
    }

    @ViewBuilder
    private var unplayedHistory: some View {
        if store.unplayedTracks.isEmpty {
            historyEmptyView(
                title: "未再生の曲はありません", description: "ライブラリにあるすべての曲を再生しています。",
                systemImage: "checkmark.circle"
            )
        } else {
            List(store.unplayedTracks) { track in
                trackRow(trackID: track.id, detail: "まだ再生していません")
            }
        }
    }

    private var historyCandidateIDs: [Track.ID] {
        if historySection == 0 { return store.recentEvents.map(\.trackID) }
        if historySection == 1 { return store.frequentTracks.map(\.trackID) }
        return store.unplayedTracks.map(\.id)
    }

    private var favoritePlaybackButtons: some View {
        HStack(spacing: 10) {
            Button("再生", systemImage: "play.fill") { playFavorites(shuffled: false) }
                .buttonStyle(.borderedProminent)
                .disabled(favoritePlaybackDisabled)
                .help(playbackHelp)
            Button("シャッフル", systemImage: "shuffle") { playFavorites(shuffled: true) }
                .buttonStyle(.bordered)
                .disabled(favoritePlaybackDisabled)
                .help(playbackHelp)
        }
    }

    private func trackRow(trackID: Track.ID, detail: String) -> some View {
        let track = store.track(id: trackID)
        return HStack(spacing: 12) {
            if let track {
                CachedArtwork(track: track, library: library, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if queue.nowPlaying.trackID == track.id {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("再生中")
                        }
                        Text(track.title).lineLimit(1)
                    }
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer()
                if track.scanState == .missing {
                    Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Button("今すぐ再生", systemImage: "play.fill") {
                    Task { await queue.playImmediately(trackID: trackID, source: mode == .favorites ? .favorite : .history) }
                }
                    .labelStyle(.iconOnly)
                    .disabled(track.scanState != .available || !playback.canPlaySelectedOutput)
                    .help(rowPlaybackHelp(track))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title2).foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("ライブラリにない曲")
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(queue.nowPlaying.trackID == trackID ? Color.accentColor.opacity(0.08) : Color.clear)
        .contextMenu {
            if track != nil {
                QueueContextMenu(queue: queue, playlists: playlists, listening: store, trackIDs: [trackID], startingAt: trackID)
            }
        }
    }

    private func historyEmptyView(title: String, description: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button("曲を見る") { playback.destination = .songs }
        }
    }

    private var favoritePlaybackDisabled: Bool {
        availableFavoriteIDs.isEmpty || !playback.canPlaySelectedOutput
    }

    private var availableFavoriteIDs: [Track.ID] {
        let favoriteIDs = Set(store.favorites.map(\.trackID))
        return library.visibleTracks.filter {
            favoriteIDs.contains($0.id) && $0.scanState == .available
        }.map(\.id)
    }

    private func playFavorites(shuffled: Bool) {
        var ids = availableFavoriteIDs
        if shuffled { ids.shuffle() }
        guard let first = ids.first else { return }
        Task { await queue.playNow(trackIDs: ids, startingAt: first, source: .favorite) }
    }

    private var playbackHelp: String {
        if !playback.hasSelectedOutput { return "先に再生先を選んでください" }
        if !playback.canPlaySelectedOutput { return "選択した機器では再生できません" }
        return "お気に入りを再生"
    }

    private func rowPlaybackHelp(_ track: Track) -> String {
        if track.scanState != .available { return "この曲のファイルが見つかりません" }
        if !playback.hasSelectedOutput { return "先に再生先を選んでください" }
        if !playback.canPlaySelectedOutput { return "選択した機器では再生できません" }
        return "\(track.title)を今すぐ再生"
    }
}
