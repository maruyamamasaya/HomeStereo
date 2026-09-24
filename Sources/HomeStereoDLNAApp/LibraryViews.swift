#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import SwiftUI

enum LibraryBrowseMode { case songs, albums, artists }

struct LibraryView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let mode: LibraryBrowseMode
    @State private var searchPresented = false

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty { emptyView }
                else {
                    switch mode {
                    case .songs: SongsTable(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, tracks: library.visibleTracks)
                    case .albums: AlbumsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, albums: library.albums)
                    case .artists: ArtistsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, artists: library.artists)
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $library.searchText, isPresented: $searchPresented, prompt: "Libraryを検索")
            .onChange(of: library.searchFocusRequest) { _, _ in searchPresented = true }
            .toolbar {
                Picker("並び替え", selection: $library.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }.frame(minWidth: 110, idealWidth: 150)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if playback.selectedDevice?.supportsAVTransport != true {
                    HStack(spacing: 10) {
                        Image(systemName: "1.circle.fill").foregroundStyle(.orange)
                        Text(playback.selectedDevice == nil
                             ? "再生するには、先にスピーカーを選んでください。"
                             : "選択中の機器では再生操作を利用できません。")
                            .font(.callout)
                        Spacer()
                        Button("スピーカーを選ぶ") { playback.destination = .devices }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                }
            }
        }
    }

    private var title: String {
        switch mode { case .songs: "曲"; case .albums: "アルバム"; case .artists: "アーティスト" }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("Libraryは空です", systemImage: "music.note.list")
        } description: {
            Text("「フォルダ」からMac上の音楽フォルダを登録してください。")
        } actions: {
            Button("フォルダを追加…") { Task { await library.addFolder() } }
        }
    }
}

private struct SongsTable: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let tracks: [Track]

    var body: some View {
        Table(tracks, selection: $library.selectedTrackIDs) {
            TableColumn("曲名") { track in
                HStack(spacing: 9) {
                    CachedArtwork(track: track, library: library, size: 34)
                    Image(systemName: track.scanState == .available ? "music.note" : "exclamationmark.triangle")
                        .foregroundStyle(track.scanState == .available ? Color.secondary : Color.orange)
                        .accessibilityLabel(track.scanState == .available ? "利用可能" : "missing")
                    Text(track.title).lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { play(track) }
                .contextMenu {
                    let ids = selectedTrackIDs(for: track)
                    QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: ids, startingAt: track.id)
                }
                .draggable(TrackDragPayload.encode(selectedTrackIDs(for: track)))
            }.width(min: 200, ideal: 300)
            TableColumn("アーティスト") { Text($0.artist ?? "—") }
            TableColumn("アルバム") { Text($0.album ?? "—") }
            TableColumn("時間") { Text(formatLibraryDuration($0.duration)) }.width(64)
            TableColumn("形式") { Text($0.fileExtension.uppercased()) }.width(58)
        }
        .safeAreaInset(edge: .bottom) {
            if library.canLoadMoreTracks {
                Button("さらに表示（\(tracks.count)／\(library.totalFilteredTracks)）") { library.loadMoreTracks() }
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .toolbar {
            Button("選択した曲を再生", systemImage: "play.fill") {
                let ids = tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
                guard let first = ids.first else { return }
                Task { await queue.playNow(trackIDs: ids, startingAt: first) }
            }
            .disabled(library.selectedTrackIDs.isEmpty || playback.selectedDevice?.supportsAVTransport != true)
            .help(playButtonHelp)
        }
    }

    private func play(_ track: Track) {
        guard track.scanState == .available else { return }
        Task {
            await queue.playNow(trackIDs: [track.id], startingAt: track.id)
        }
    }

    private func selectedTrackIDs(for track: Track) -> [Track.ID] {
        guard library.selectedTrackIDs.contains(track.id) else { return [track.id] }
        return tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
    }

    private var playButtonHelp: String {
        if playback.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if playback.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if library.selectedTrackIDs.isEmpty { return "再生する曲を選択してください" }
        return "選択した曲をQueueに入れて再生します"
    }
}

private struct AlbumsList: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let albums: [LibraryAlbum]
    @State private var selection = Set<LibraryAlbum.ID>()

    var body: some View {
        List(albums, selection: $selection) { album in
            NavigationLink(value: album.id) {
                HStack(spacing: 12) {
                    if let track = album.tracks.first { CachedArtwork(track: track, library: library, size: 52) }
                    VStack(alignment: .leading) {
                        Text(album.title).font(.headline)
                        Text(album.albumArtist ?? "不明なAlbum Artist").foregroundStyle(.secondary)
                        Text("\(album.tracks.count)曲").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 4)
            }
            .tag(album.id)
            .contextMenu { QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: selectedTrackIDs(for: album)) }
            .draggable(TrackDragPayload.encode(selectedTrackIDs(for: album)))
        }
        .navigationDestination(for: LibraryAlbum.ID.self) { id in
            if let album = library.albums.first(where: { $0.id == id }) {
                CollectionDetail(
                    title: album.title, subtitle: album.albumArtist ?? "不明なAlbum Artist",
                    tracks: album.tracks, playback: playback, library: library, queue: queue, playlists: playlists, listening: listening
                )
            }
        }
    }

    private func selectedTrackIDs(for album: LibraryAlbum) -> [Track.ID] {
        let ids = selection.contains(album.id) ? selection : Set([album.id])
        return albums.filter { ids.contains($0.id) }.flatMap(\.tracks).map(\.id)
    }
}

private struct ArtistsList: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let artists: [LibraryArtist]
    @State private var selection = Set<String>()

    var body: some View {
        List(artists, selection: $selection) { artist in
            NavigationLink(value: artist.id) {
                VStack(alignment: .leading) {
                    Text(artist.name).font(.headline)
                    Text("\(artist.tracks.count)曲").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            .tag(artist.id)
            .contextMenu { QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: selectedTrackIDs(for: artist)) }
            .draggable(TrackDragPayload.encode(selectedTrackIDs(for: artist)))
        }
        .navigationDestination(for: String.self) { id in
            if let artist = library.artists.first(where: { $0.id == id }) {
                CollectionDetail(title: artist.name, subtitle: "Track Artist", tracks: artist.tracks, playback: playback, library: library, queue: queue, playlists: playlists, listening: listening)
            }
        }
    }

    private func selectedTrackIDs(for artist: LibraryArtist) -> [Track.ID] {
        let ids = selection.contains(artist.id) ? selection : Set([artist.id])
        return artists.filter { ids.contains($0.id) }.flatMap(\.tracks).map(\.id)
    }
}

private struct CollectionDetail: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    @State private var selection = Set<Track.ID>()

    var body: some View {
        List(tracks, selection: $selection) { track in
            HStack {
                CachedArtwork(track: track, library: library, size: 36)
                VStack(alignment: .leading) {
                    Text(track.title)
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatLibraryDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard track.scanState == .available else { return }
                Task { await queue.playNow(trackIDs: [track.id], startingAt: track.id) }
            }
            .tag(track.id)
            .contextMenu {
                let ids = selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]
                QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: ids, startingAt: track.id)
            }
            .draggable(TrackDragPayload.encode(selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]))
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }
}

struct QueueContextMenu: View {
    let queue: QueueStore
    let playlists: PlaylistStore
    let listening: ListeningStore
    let trackIDs: [Track.ID]
    var startingAt: Track.ID?
    var body: some View {
        Button("今すぐ再生") { Task { await queue.playNow(trackIDs: trackIDs, startingAt: startingAt) } }
        Button("次に再生") { Task { await queue.playNext(trackIDs: trackIDs) } }
        Button("Queueの最後に追加") { Task { await queue.append(trackIDs: trackIDs) } }
        if trackIDs.count == 1, let id = trackIDs.first {
            Button(listening.isFavorite(id) ? "Favoriteを解除" : "Favoriteに追加") { Task { await listening.toggleFavorite(id) } }
        }
        if !playlists.playlists.isEmpty {
            Menu("Playlistに追加") {
                ForEach(playlists.playlists) { playlist in
                    Button(playlist.name) { Task { await playlists.add(trackIDs: trackIDs, to: playlist.id) } }
                }
            }
        }
    }
}

struct CachedArtwork: View {
    let track: Track
    let library: LibraryStore
    let size: CGFloat
    @State private var data: Data?

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 5))
        .accessibilityLabel("\(track.title)のArtwork")
        .task(id: track.id) {
            let loaded = await library.artworkData(for: track, pixelSize: Int(size * 2))
            guard !Task.isCancelled else { return }
            data = loaded
        }
    }
}

enum TrackDragPayload {
    static func encode(_ ids: [Track.ID]) -> String { ids.map(\.uuidString).joined(separator: ",") }
    static func decode(_ value: String) -> [Track.ID] {
        value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

struct LibraryFoldersView: View {
    @Bindable var library: LibraryStore
    @State private var pendingRemoval: LibraryFolder.ID?
    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(library.folders) { folder in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(folder.displayName, systemImage: folder.accessState == .available ? "folder" : "folder.badge.questionmark").font(.headline)
                            Spacer(); Text("\(folder.trackCount)曲").foregroundStyle(.secondary)
                        }
                        Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if folder.accessState == .needsReselection {
                            Text("アクセス権が失われています。登録解除後、フォルダを再選択してください。").font(.caption).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("再スキャン") { library.scanFolder(folder.id) }.disabled(library.scanningFolderID != nil)
                            Button("登録解除", role: .destructive) { pendingRemoval = folder.id }.disabled(library.scanningFolderID == folder.id)
                            if let date = folder.lastScannedAt { Text("最終scan: \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.padding(.vertical, 5)
                }
            }
            if let progress = library.scanProgress, library.scanningFolderID != nil {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    ProgressView(value: Double(progress.analyzed), total: Double(max(1, progress.discovered)))
                    Text("発見 \(progress.discovered)・解析 \(progress.analyzed)・新規 \(progress.added)・更新 \(progress.updated)・未変更 \(progress.unchanged)・失敗 \(progress.failed)・missing \(progress.missing)").font(.caption)
                    Text(progress.currentRelativePath ?? "完了処理中").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Button("キャンセル") { library.cancelScan() }
                }.padding()
            }
            if !library.scanNotices.isEmpty {
                Divider()
                DisclosureGroup("Scan notice（\(library.scanNotices.count)件）") {
                    ForEach(library.scanNotices) { Text("\($0.relativePath ?? "—"): \($0.message)").font(.caption) }
                }.padding()
            }
        }
        .navigationTitle("音楽フォルダ")
        .toolbar {
            Button("フォルダを追加", systemImage: "folder.badge.plus") { Task { await library.addFolder() } }
            Button("すべて再スキャン", systemImage: "arrow.clockwise") { Task { await library.scanAll() } }.disabled(library.folders.isEmpty || library.scanningFolderID != nil)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Toggle("フォルダの自動更新", isOn: Binding(
                    get: { library.autoUpdateEnabled },
                    set: { enabled in Task { await library.setAutoUpdateEnabled(enabled) } }
                ))
                Spacer()
                Text("最終自動更新: \(library.lastAutomaticUpdate?.formatted(date: .abbreviated, time: .shortened) ?? "未実行")")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).background(.bar)
        }
        .confirmationDialog("音楽フォルダの登録を解除しますか？", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("登録解除", role: .destructive) {
                guard let id = pendingRemoval else { return }
                pendingRemoval = nil
                Task { await library.removeFolder(id) }
            }
        } message: {
            Text("音源ファイルは削除しません。Libraryでは曲が参照できなくなります。")
        }
    }
}

private func formatLibraryDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded()); return String(format: "%d:%02d", total / 60, total % 60)
}
