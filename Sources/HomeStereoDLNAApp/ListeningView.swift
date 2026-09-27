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
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .toolbar {
            Menu("管理", systemImage: "ellipsis.circle") {
                if mode == .favorites {
                    Button("お気に入りをすべて解除", role: .destructive) { resetConfirmation = .favorites }
                        .disabled(store.favorites.isEmpty)
                } else {
                    Button("再生履歴をすべて削除", role: .destructive) { resetConfirmation = .history }
                        .disabled(store.events.isEmpty)
                }
            }
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

    @ViewBuilder
    private var favorites: some View {
        if store.favorites.isEmpty {
            ContentUnavailableView {
                Label("お気に入りはありません", systemImage: "heart")
            } description: {
                Text("曲のメニューから「お気に入りに追加」を選ぶと、ここからすぐ再生できます。")
            } actions: {
                Button("曲を見る") { playback.destination = .songs }
            }
        } else {
            VStack(spacing: 0) {
                listeningHeader(
                    title: "お気に入り", subtitle: favoriteSummary,
                    systemImage: "heart.fill", tint: .pink
                )
                Divider()
                List(store.favorites) { favorite in
                    trackRow(trackID: favorite.trackID, detail: "\(favorite.addedAt.formatted(date: .abbreviated, time: .omitted))に追加")
                }
            }
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

    private func listeningHeader(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                headerIdentity(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
                Spacer()
                favoritePlaybackButtons
            }
            VStack(alignment: .leading, spacing: 14) {
                headerIdentity(title: title, subtitle: subtitle, systemImage: systemImage, tint: tint)
                favoritePlaybackButtons
            }
        }
        .padding(20)
    }

    private func headerIdentity(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
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

    private var favoriteSummary: String {
        let unavailable = store.favorites.count - availableFavoriteIDs.count
        return unavailable == 0
            ? "\(store.favorites.count)曲"
            : "\(store.favorites.count)曲 · \(unavailable)曲は利用できません"
    }

    private var favoritePlaybackDisabled: Bool {
        availableFavoriteIDs.isEmpty || !playback.canPlaySelectedOutput
    }

    private var availableFavoriteIDs: [Track.ID] {
        store.favorites.compactMap { favorite in
            guard let track = store.track(id: favorite.trackID), track.scanState == .available else { return nil }
            return track.id
        }
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
