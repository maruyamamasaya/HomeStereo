#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct PlaylistsView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var store: PlaylistStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore
    @State private var newName = ""
    @State private var renameValue = ""
    @State private var showsCreateDialog = false
    @State private var showsRenameDialog = false
    @State private var confirmsPlaylistDelete = false
    @State private var confirmsItemDelete = false
    @State private var playlistForTrackPicker: Playlist?

    var body: some View {
        HSplitView {
            playlistSidebar
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity)

            if let playlist = selectedPlaylist {
                playlistDetail(playlist)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("プレイリストを選択", systemImage: "music.note.list")
                } description: {
                    Text(visiblePlaylists.isEmpty
                         ? emptyDescription
                         : "左の一覧からプレイリストを選んでください。")
                } actions: {
                    if visiblePlaylists.isEmpty {
                        Button(createTitle, systemImage: "plus") { beginCreate() }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("プレイリスト")
        .toolbar {
            Button("プレイリストを作成", systemImage: "plus") { beginCreate() }
            Button("M3U8を読み込む", systemImage: "square.and.arrow.down") { Task { await store.importM3U8() } }
            if let playlist = selectedPlaylist {
                playlistManagementMenu(playlist)
            }
        }
        .alert("新しいプレイリスト", isPresented: $showsCreateDialog) {
            TextField("プレイリスト名", text: $newName)
            Button("作成") {
                let name = newName
                newName = ""
                Task { await store.create(name: name) }
            }
            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("キャンセル", role: .cancel) { newName = "" }
        } message: {
            Text("あとから名称を変更できます。")
        }
        .alert("プレイリスト名を変更", isPresented: $showsRenameDialog) {
            TextField("プレイリスト名", text: $renameValue)
            Button("変更") {
                guard let playlist = selectedPlaylist else { return }
                Task { await store.rename(id: playlist.id, name: renameValue) }
            }
            .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("キャンセル", role: .cancel) {}
        }
        .alert("プレイリスト", isPresented: Binding(
            get: { store.message != nil || store.lastImportResult != nil },
            set: { if !$0 { store.dismissMessage() } }
        )) {
            Button("OK") { store.dismissMessage() }
        } message: {
            if let result = store.lastImportResult {
                Text("読み込み完了：\(result.imported)曲、未解決\(result.unresolved.count)件、曖昧\(result.ambiguous.count)件")
            } else {
                Text(store.message ?? "")
            }
        }
        .confirmationDialog("選択したプレイリストを削除しますか？", isPresented: $confirmsPlaylistDelete) {
            Button("プレイリストを削除", role: .destructive) { Task { await store.deleteSelectedPlaylists() } }
        } message: {
            Text("音源ファイルは削除されません。")
        }
        .confirmationDialog("選択した曲をプレイリストから削除しますか？", isPresented: $confirmsItemDelete) {
            if let playlist = selectedPlaylist {
                Button("プレイリストから削除", role: .destructive) { Task { await store.removeSelected(from: playlist.id) } }
            }
        } message: {
            Text("音源ファイルは削除されません。")
        }
        .sheet(item: $playlistForTrackPicker) { playlist in
            PlaylistTrackPicker(store: store, playlist: playlist, tracks: library.tracks)
        }
    }

    private var playlistSidebar: some View {
        Group {
            if visiblePlaylists.isEmpty {
                ContentUnavailableView("プレイリストなし", systemImage: "music.note.list")
            } else {
                List(visiblePlaylists, selection: $store.selectedPlaylistIDs) { playlist in
                    playlistSidebarRow(playlist)
                        .tag(playlist.id)
                        .dropDestination(for: String.self) { values, _ in
                            let ids = values.flatMap(TrackDragPayload.decode)
                            guard !ids.isEmpty, store.canAdd(trackIDs: ids, to: playlist.id) else { return false }
                            Task { await store.add(trackIDs: ids, to: playlist.id) }
                            return true
                        }
                        .contextMenu {
                            Button("再生") { Task { await store.play(playlist, shuffled: false) } }
                                .disabled(!playback.canPlaySelectedOutput)
                            Button("再生キューの最後に追加") {
                                Task { await store.appendToQueue(trackIDs: playlist.items.map(\.trackID)) }
                            }
                            Divider()
                            Button("名称を変更") { beginRename(playlist) }
                            Button("プレイリストを削除", role: .destructive) {
                                store.selectedPlaylistIDs = [playlist.id]
                                confirmsPlaylistDelete = true
                            }
                        }
                }
                .onChange(of: store.selectedPlaylistIDs) { _, value in
                    if let active = store.selectedPlaylistID, value.contains(active) { return }
                    store.selectedPlaylistID = value.first
                }
            }
        }
    }

    private func playlistSidebarRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 10) {
            playlistArtwork(playlist, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if containsNowPlaying(playlist) {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("このプレイリストを再生中")
                    }
                    Text(playlist.name).lineLimit(1)
                }
                Text(playlistSummary(playlist, compact: true))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private func playlistDetail(_ playlist: Playlist) -> some View {
        VStack(spacing: 0) {
            playlistHeader(playlist)
            Divider()
            if playlist.items.isEmpty {
                ContentUnavailableView {
                    Label("曲がありません", systemImage: "music.note")
                } description: {
                    Text("ライブラリから曲を選ぶか、ドラッグまたは現在の再生キューから追加してください。")
                } actions: {
                    Button("曲を追加", systemImage: "plus") { playlistForTrackPicker = playlist }
                    Button("現在の再生キューを追加") { Task { await store.addCurrentQueue(to: playlist.id) } }
                        .disabled(queue.items.isEmpty)
                }
            } else {
                playlistTracks(playlist)
                Divider()
                playlistSelectionBar
            }
        }
        .dropDestination(for: String.self) { values, _ in
            let ids = values.flatMap(TrackDragPayload.decode)
            guard !ids.isEmpty, store.canAdd(trackIDs: ids, to: playlist.id) else { return false }
            Task { await store.add(trackIDs: ids, to: playlist.id) }
            return true
        }
    }

    private func playlistHeader(_ playlist: Playlist) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 22) {
                playlistArtwork(playlist, size: 138)
                playlistHeaderDetails(playlist)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 14) {
                playlistArtwork(playlist, size: 112)
                playlistHeaderDetails(playlist)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playlistHeaderDetails(_ playlist: Playlist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プレイリスト")
                .font(.caption.bold()).foregroundStyle(.secondary)
            Text(playlist.name).font(.system(size: 28, weight: .bold)).lineLimit(2)
            Text(playlistSummary(playlist, compact: false)).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("再生", systemImage: "play.fill") { Task { await store.play(playlist, shuffled: false) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!playback.canPlaySelectedOutput || playableTrackIDs(playlist).isEmpty)
                Button("シャッフル", systemImage: "shuffle") { Task { await store.play(playlist, shuffled: true) } }
                    .buttonStyle(.bordered)
                    .disabled(!playback.canPlaySelectedOutput || playableTrackIDs(playlist).isEmpty)
                Button("曲を追加", systemImage: "plus") { playlistForTrackPicker = playlist }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func playlistTracks(_ playlist: Playlist) -> some View {
        List(selection: $store.selectedItemIDs) {
            ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 11) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    if let track = store.track(for: item) {
                        CachedArtwork(track: track, library: library, size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if queue.nowPlaying.trackID == track.id {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(.tint).accessibilityLabel("再生中")
                                }
                                Text(track.title).lineLimit(1)
                            }
                            Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if track.scanState == .missing {
                            Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                                .labelStyle(.iconOnly).foregroundStyle(.orange)
                        }
                        Text(formatPlaylistDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "questionmark.square.dashed")
                            .font(.title2).foregroundStyle(.orange)
                            .frame(width: 40, height: 40)
                        Text("ライブラリにない曲").foregroundStyle(.orange)
                        Spacer()
                    }
                }
                .padding(.vertical, 3)
                .tag(item.id)
                .draggable(TrackDragPayload.encode([item.trackID]))
                .listRowBackground(queue.nowPlaying.trackID == item.trackID ? Color.accentColor.opacity(0.08) : Color.clear)
                .contextMenu {
                    Button("今すぐ再生") { Task { await store.playNow(trackIDs: [item.trackID], startingAt: item.trackID) } }
                        .disabled(
                            !playback.canPlaySelectedOutput ||
                            store.track(for: item)?.scanState != .available
                        )
                    Button("次に再生") { Task { await store.playNext(trackIDs: [item.trackID]) } }
                    Button("再生キューの最後に追加") { Task { await store.appendToQueue(trackIDs: [item.trackID]) } }
                    Divider()
                    Button("プレイリストから削除", role: .destructive) {
                        store.selectedItemIDs = [item.id]
                        confirmsItemDelete = true
                    }
                }
            }
            .onMove { source, destination in
                Task { await store.move(fromOffsets: source, toOffset: destination, in: playlist.id) }
            }
        }
        .onDeleteCommand { if !store.selectedItemIDs.isEmpty { confirmsItemDelete = true } }
    }

    private var playlistSelectionBar: some View {
        HStack(spacing: 12) {
            Text(store.selectedItemIDs.isEmpty ? "曲を選択して編集" : "\(store.selectedItemIDs.count)曲を選択中")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("選択した曲を削除", systemImage: "trash", role: .destructive) { confirmsItemDelete = true }
                .disabled(store.selectedItemIDs.isEmpty)
        }
        .padding(12)
        .homeStereoThemeBar()
    }

    private func playlistManagementMenu(_ playlist: Playlist) -> some View {
        Menu("プレイリストを管理", systemImage: "ellipsis.circle") {
            Button("名称を変更", systemImage: "pencil") { beginRename(playlist) }
            Button("ライブラリから曲を追加", systemImage: "plus") { playlistForTrackPicker = playlist }
            Button("現在の再生キューを追加", systemImage: "text.append") {
                Task { await store.addCurrentQueue(to: playlist.id) }
            }
            .disabled(queue.items.isEmpty)
            Button("M3U8を書き出す", systemImage: "square.and.arrow.up") { Task { await store.exportM3U8(playlist) } }
            Divider()
            Button("プレイリストを削除", role: .destructive) {
                if store.selectedPlaylistIDs.isEmpty { store.selectedPlaylistIDs = [playlist.id] }
                confirmsPlaylistDelete = true
            }
        }
    }

    @ViewBuilder
    private func playlistArtwork(_ playlist: Playlist, size: CGFloat) -> some View {
        if let track = playlist.items.lazy.compactMap({ store.track(for: $0) }).first {
            CachedArtwork(track: track, library: library, size: size)
        } else {
            ZStack {
                LinearGradient(colors: [.purple.opacity(0.75), .pink.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note.list")
                    .font(.system(size: max(18, size * 0.3), weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.07)))
            .accessibilityLabel("\(playlist.name)のArtwork")
        }
    }

    private func playlistSummary(_ playlist: Playlist, compact: Bool) -> String {
        let tracks = playlist.items.compactMap { store.track(for: $0) }
        let unavailable = playlist.items.count - tracks.filter { $0.scanState == .available }.count
        var parts = ["\(playlist.items.count)曲"]
        if !compact { parts.append(formatPlaylistCollectionDuration(tracks.reduce(0) { $0 + $1.duration })) }
        if unavailable > 0 { parts.append("\(unavailable)曲は利用不可") }
        return parts.joined(separator: " · ")
    }

    private func playableTrackIDs(_ playlist: Playlist) -> [Track.ID] {
        playlist.items.compactMap { item in
            guard let track = store.track(for: item), track.scanState == .available else { return nil }
            return track.id
        }
    }

    private func containsNowPlaying(_ playlist: Playlist) -> Bool {
        guard let id = queue.nowPlaying.trackID else { return false }
        return playlist.items.contains { $0.trackID == id }
    }

    private func beginCreate() {
        newName = ""
        showsCreateDialog = true
    }

    private func beginRename(_ playlist: Playlist) {
        store.selectedPlaylistID = playlist.id
        store.selectedPlaylistIDs = [playlist.id]
        renameValue = playlist.name
        showsRenameDialog = true
    }

    private var visiblePlaylists: [Playlist] { store.playlists }
    private var selectedPlaylist: Playlist? { store.selectedPlaylist }
    private var createTitle: String { "プレイリストを作成" }
    private var emptyDescription: String {
        "通常の曲、作業用BGM、ハイレゾを目的に合わせて自由にまとめられます。"
    }
}

private struct PlaylistTrackPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: PlaylistStore
    let playlist: Playlist
    let tracks: [Track]
    @State private var searchText = ""
    @State private var selectedTrackIDs = Set<Track.ID>()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(selectedTrackIDs.isEmpty ? "曲を選択してください" : "\(selectedTrackIDs.count)曲を選択中")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("表示中をすべて選択") {
                        selectedTrackIDs.formUnion(filteredTracks.map(\.id))
                    }
                    .disabled(filteredTracks.isEmpty)
                    Button("選択解除") { selectedTrackIDs.removeAll() }
                        .disabled(selectedTrackIDs.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .homeStereoThemeBar()

                if filteredTracks.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(filteredTracks, selection: $selectedTrackIDs) { track in
                        HStack(spacing: 10) {
                            Image(systemName: track.scanState == .available ? "music.note" : "exclamationmark.triangle")
                                .foregroundStyle(track.scanState == .available ? Color.secondary : Color.orange)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(track.title).lineLimit(1)
                                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if playlist.items.contains(where: { $0.trackID == track.id }) {
                                Text("追加済み")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(formatPlaylistDuration(track.duration))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                        .tag(track.id)
                    }
                }
            }
            .navigationTitle("\(playlist.name)に曲を追加")
            .searchable(text: $searchText, prompt: "曲名、アーティスト、アルバムを検索")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("\(selectedTrackIDs.count)曲を追加") {
                        let ids = filteredAndSelectedTrackIDs
                        Task {
                            await store.add(trackIDs: ids, to: playlist.id)
                            dismiss()
                        }
                    }
                    .disabled(selectedTrackIDs.isEmpty)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var compatibleTracks: [Track] {
        tracks
            .sorted {
                let titleOrder = $0.title.localizedStandardCompare($1.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private var filteredTracks: [Track] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return compatibleTracks }
        return compatibleTracks.filter { track in
            [track.title, track.artist, track.album]
                .compactMap { $0 }
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var filteredAndSelectedTrackIDs: [Track.ID] {
        compatibleTracks.map(\.id).filter { selectedTrackIDs.contains($0) }
    }
}

private func formatPlaylistDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded()); return String(format: "%d:%02d", total / 60, total % 60)
}

private func formatPlaylistCollectionDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "時間不明" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)分" }
    return "\(minutes / 60)時間\(minutes % 60)分"
}
