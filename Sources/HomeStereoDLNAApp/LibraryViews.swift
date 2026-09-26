#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import Foundation
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
                else if hasNoSearchResults { noSearchResultsView }
                else {
                    switch mode {
                    case .songs: SongsTable(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, tracks: library.visibleTracks)
                    case .albums: AlbumsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, albums: library.albums)
                    case .artists: ArtistsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, artists: library.artists)
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $library.searchText, isPresented: $searchPresented, prompt: "ライブラリを検索")
            .onChange(of: library.searchFocusRequest) { _, _ in searchPresented = true }
            .toolbar {
                Picker("並び替え", selection: $library.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                }.frame(minWidth: 110, idealWidth: 150)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        Divider()
                    }
                    if !library.tracks.isEmpty {
                        HStack {
                            Text(resultSummary).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !normalizedSearch.isEmpty {
                                Button("検索をクリア") { library.searchText = "" }
                                    .buttonStyle(.link)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                    }
                }
                .background(.bar)
            }
        }
    }

    private var title: String {
        switch mode { case .songs: "曲"; case .albums: "アルバム"; case .artists: "アーティスト" }
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("ライブラリは空です", systemImage: "music.note.list")
        } description: {
            Text("「フォルダ」からMac上の音楽フォルダを登録してください。")
        } actions: {
            Button("フォルダを追加…") { Task { await library.addFolder() } }
        }
    }

    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: normalizedSearch)
    }

    private var normalizedSearch: String {
        library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNoSearchResults: Bool {
        guard !normalizedSearch.isEmpty else { return false }
        switch mode {
        case .songs: return library.totalFilteredTracks == 0
        case .albums: return library.albums.isEmpty
        case .artists: return library.artists.isEmpty
        }
    }

    private var resultSummary: String {
        let count: Int
        let unit: String
        switch mode {
        case .songs: count = library.totalFilteredTracks; unit = "曲"
        case .albums: count = library.albums.count; unit = "アルバム"
        case .artists: count = library.artists.count; unit = "組"
        }
        return normalizedSearch.isEmpty ? "\(count)\(unit)" : "「\(normalizedSearch)」の検索結果：\(count)\(unit)"
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
        VStack(spacing: 0) {
            Table(tracks, selection: $library.selectedTrackIDs) {
                TableColumn("") { track in
                    Button {
                        play(track)
                    } label: {
                        Image(systemName: queue.nowPlaying.trackID == track.id ? "speaker.wave.2.fill" : "play.circle.fill")
                            .foregroundStyle(queue.nowPlaying.trackID == track.id ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(track.scanState != .available || playback.selectedDevice?.supportsAVTransport != true)
                    .help(rowPlayHelp(track))
                    .accessibilityLabel(queue.nowPlaying.trackID == track.id ? "再生中：\(track.title)" : "\(track.title)を再生")
                }
                .width(30)
                TableColumn("曲名") { track in
                    HStack(spacing: 9) {
                        CachedArtwork(track: track, library: library, size: 34)
                        Image(systemName: track.scanState == .available ? "music.note" : "exclamationmark.triangle")
                            .foregroundStyle(track.scanState == .available ? Color.secondary : Color.orange)
                            .accessibilityLabel(track.scanState == .available ? "利用可能" : "ファイルが見つかりません")
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
                TableColumn("ジャンル") { Text($0.genre ?? "—").lineLimit(1) }
                    .width(min: 72, ideal: 100)
                TableColumn("年") { Text($0.releaseYear.map(String.init) ?? "—").monospacedDigit() }
                    .width(54)
                TableColumn("時間") { Text(formatLibraryDuration($0.duration)) }.width(64)
                TableColumn("音質") { Text(formatAudioQuality($0)).monospacedDigit().lineLimit(1) }
                    .width(min: 130, ideal: 180)
                TableColumn("サイズ") { Text(formatFileSize($0.fileSize)).monospacedDigit() }
                    .width(78)
                TableColumn("ファイルパス") { track in
                    Text(track.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(track.url.path)
                }
                .width(min: 140, ideal: 240)
            }

            if library.canLoadMoreTracks {
                Divider()
                Button("さらに表示（\(tracks.count)／\(library.totalFilteredTracks)）") { library.loadMoreTracks() }
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
            }
        }
        .toolbar {
            Text(selectionSummary)
                .foregroundStyle(.secondary)
            Button("選択した曲を再生", systemImage: "play.fill") {
                let ids = selectedTrackIDs
                guard let first = ids.first else { return }
                Task { await queue.playNow(trackIDs: ids, startingAt: first, source: .library) }
            }
            .disabled(library.selectedTrackIDs.isEmpty || playback.selectedDevice?.supportsAVTransport != true)
            .help(playButtonHelp)
            Menu("選択した曲の操作", systemImage: "ellipsis.circle") {
                Button("次に再生", systemImage: "text.insert") { Task { await queue.playNext(trackIDs: selectedTrackIDs) } }
                Button("再生キューの最後に追加", systemImage: "text.append") { Task { await queue.append(trackIDs: selectedTrackIDs) } }
                if !playlists.playlists.isEmpty {
                    Divider()
                    Menu("プレイリストに追加") {
                        ForEach(playlists.playlists) { playlist in
                            Button(playlist.name) { Task { await playlists.add(trackIDs: selectedTrackIDs, to: playlist.id) } }
                        }
                    }
                }
            }
            .disabled(library.selectedTrackIDs.isEmpty)
            .help(library.selectedTrackIDs.isEmpty ? "操作する曲を選択してください" : "選択した曲を再生キューまたはプレイリストへ追加")
        }
    }

    private func play(_ track: Track) {
        guard track.scanState == .available else { return }
        Task {
            await queue.playNow(trackIDs: [track.id], startingAt: track.id, source: .library)
        }
    }

    private func selectedTrackIDs(for track: Track) -> [Track.ID] {
        guard library.selectedTrackIDs.contains(track.id) else { return [track.id] }
        return tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
    }

    private var selectedTrackIDs: [Track.ID] {
        tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
    }

    private var selectionSummary: String {
        library.selectedTrackIDs.isEmpty ? "曲を選択" : "\(library.selectedTrackIDs.count)曲を選択中"
    }

    private func rowPlayHelp(_ track: Track) -> String {
        if track.scanState != .available { return "この曲のファイルが見つかりません" }
        if playback.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if playback.selectedDevice?.supportsAVTransport != true { return "選択した機器では再生できません" }
        return "\(track.title)を今すぐ再生"
    }

    private var playButtonHelp: String {
        if playback.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if playback.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if library.selectedTrackIDs.isEmpty { return "再生する曲を選択してください" }
        return "選択した曲を再生キューに入れて再生します"
    }
}

private struct AlbumsList: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let albums: [LibraryAlbum]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 210), spacing: 22)], alignment: .leading, spacing: 26) {
                ForEach(albums) { album in
                    NavigationLink(value: album.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let track = album.tracks.first {
                                CachedArtwork(track: track, library: library, size: 158)
                                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                            }
                            Text(album.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text(album.albumArtist ?? "不明なアーティスト")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("\(album.tracks.count)曲")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(width: 158, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        QueueContextMenu(
                            queue: queue, playlists: playlists, listening: listening,
                            trackIDs: album.tracks.map(\.id), startingAt: album.tracks.first?.id
                        )
                    }
                    .draggable(TrackDragPayload.encode(album.tracks.map(\.id)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(album.title)、\(album.albumArtist ?? "不明なアーティスト")、\(album.tracks.count)曲")
                }
            }
            .padding(24)
        }
        .navigationDestination(for: LibraryAlbum.ID.self) { id in
            if let album = library.albums.first(where: { $0.id == id }) {
                CollectionDetail(
                    title: album.title, subtitle: album.albumArtist ?? "不明なアルバムアーティスト",
                    tracks: album.tracks, artworkTrack: album.tracks.first,
                    playback: playback, library: library, queue: queue, playlists: playlists, listening: listening
                )
            }
        }
    }
}

private struct ArtistsList: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    let artists: [LibraryArtist]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 210), spacing: 22)], alignment: .leading, spacing: 26) {
                ForEach(artists) { artist in
                    NavigationLink(value: artist.id) {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                if let track = artist.tracks.first {
                                    CachedArtwork(track: track, library: library, size: 158)
                                        .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                                }
                                if artist.tracks.contains(where: { $0.id == queue.nowPlaying.trackID }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(8)
                                        .background(.tint, in: Circle())
                                        .padding(8)
                                        .accessibilityLabel("このアーティストを再生中")
                                }
                            }
                            Text(artist.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text("\(albumCount(for: artist))アルバム · \(artist.tracks.count)曲")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 158, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        QueueContextMenu(
                            queue: queue, playlists: playlists, listening: listening,
                            trackIDs: artist.tracks.map(\.id), startingAt: artist.tracks.first?.id
                        )
                    }
                    .draggable(TrackDragPayload.encode(artist.tracks.map(\.id)))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(artist.name)、\(albumCount(for: artist))アルバム、\(artist.tracks.count)曲")
                }
            }
            .padding(24)
        }
        .navigationDestination(for: String.self) { id in
            if let artist = library.artists.first(where: { $0.id == id }) {
                ArtistDetail(
                    artist: artist, playback: playback, library: library,
                    queue: queue, playlists: playlists, listening: listening
                )
            }
        }
    }

    private func albumCount(for artist: LibraryArtist) -> Int {
        Set(artist.tracks.map { track in
            LibraryAlbum.ID(
                albumArtist: track.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                title: track.album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "アルバム未設定"
            )
        }).count
    }
}

private struct ArtistDetail: View {
    let artist: LibraryArtist
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                artistHeader
                Divider()
                ForEach(albumGroups) { group in
                    albumSection(group)
                    Divider().padding(.leading, 24)
                }
            }
        }
        .navigationTitle(artist.name)
        .navigationSubtitle("アーティスト")
    }

    private var artistHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 24) {
                artistArtwork
                artistSummary
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 16) {
                artistArtwork
                artistSummary
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var artistArtwork: some View {
        if let track = artist.tracks.first {
            CachedArtwork(track: track, library: library, size: 168)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
        }
    }

    private var artistSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("アーティスト").font(.caption.bold()).foregroundStyle(.secondary)
            Text(artist.name).font(.system(size: 30, weight: .bold)).lineLimit(2)
            Text("\(albumGroups.count)アルバム · \(artist.tracks.count)曲 · \(formatCollectionDuration(totalDuration))")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("再生", systemImage: "play.fill") { play(shuffled: false) }
                    .buttonStyle(.borderedProminent)
                    .disabled(playback.selectedDevice?.supportsAVTransport != true || availableTrackIDs.isEmpty)
                Button("シャッフル", systemImage: "shuffle") { play(shuffled: true) }
                    .buttonStyle(.bordered)
                    .disabled(playback.selectedDevice?.supportsAVTransport != true || availableTrackIDs.isEmpty)
                Button("再生キューに追加", systemImage: "text.append") {
                    Task { await queue.append(trackIDs: availableTrackIDs) }
                }
                .buttonStyle(.bordered)
                .disabled(availableTrackIDs.isEmpty)
            }
        }
    }

    private func albumSection(_ group: ArtistAlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let track = group.tracks.first {
                    CachedArtwork(track: track, library: library, size: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.title3.bold())
                    Text(albumDescription(group))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("アルバムを再生", systemImage: "play.fill") {
                    let ids = group.tracks.filter { $0.scanState == .available }.map(\.id)
                    guard let first = ids.first else { return }
                    Task { await queue.playNow(trackIDs: ids, startingAt: first, source: .album) }
                }
                .labelStyle(.iconOnly)
                .disabled(playback.selectedDevice?.supportsAVTransport != true)
                .help("\(group.title)を再生")
            }
            ForEach(group.tracks) { track in
                ArtistTrackRow(
                    track: track, playback: playback, queue: queue,
                    playlists: playlists, listening: listening
                )
            }
        }
        .padding(24)
    }

    private var albumGroups: [ArtistAlbumGroup] {
        Dictionary(grouping: artist.tracks, by: albumID(for:))
            .map { ArtistAlbumGroup(id: $0.key, tracks: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func albumID(for track: Track) -> LibraryAlbum.ID {
        LibraryAlbum.ID(
            albumArtist: track.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            title: track.album?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "アルバム未設定"
        )
    }

    private func albumDescription(_ group: ArtistAlbumGroup) -> String {
        let metadata = "\(group.tracks.count)曲 · \(formatCollectionDuration(group.tracks.reduce(0) { $0 + $1.duration }))"
        guard let albumArtist = group.id.albumArtist, albumArtist != artist.name else { return metadata }
        return "\(albumArtist) · \(metadata)"
    }

    private var availableTrackIDs: [Track.ID] {
        artist.tracks.filter { $0.scanState == .available }.map(\.id)
    }

    private var totalDuration: TimeInterval { artist.tracks.reduce(0) { $0 + $1.duration } }

    private func play(shuffled: Bool) {
        var ids = availableTrackIDs
        if shuffled { ids.shuffle() }
        guard let first = ids.first else { return }
        Task { await queue.playNow(trackIDs: ids, startingAt: first, source: shuffled ? .shuffle : .artist) }
    }
}

private struct ArtistAlbumGroup: Identifiable {
    let id: LibraryAlbum.ID
    let tracks: [Track]
    var title: String { id.title }
}

private struct ArtistTrackRow: View {
    let track: Track
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore

    var body: some View {
        HStack(spacing: 10) {
            Text(track.trackNumber.map(String.init) ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            if queue.nowPlaying.trackID == track.id {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("再生中")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                if let albumArtist = track.albumArtist, albumArtist != track.artist {
                    Text(albumArtist).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if track.scanState == .missing {
                Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
            }
            Text(formatLibraryDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
            Button("再生", systemImage: "play.fill") {
                Task { await queue.playNow(trackIDs: [track.id], startingAt: track.id, source: .artist) }
            }
            .labelStyle(.iconOnly)
            .disabled(track.scanState != .available || playback.selectedDevice?.supportsAVTransport != true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            guard track.scanState == .available else { return }
            Task { await queue.playNow(trackIDs: [track.id], startingAt: track.id, source: .artist) }
        }
        .contextMenu {
            QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: [track.id], startingAt: track.id)
        }
        .draggable(TrackDragPayload.encode([track.id]))
    }
}

private struct CollectionDetail: View {
    let title: String
    let subtitle: String
    let tracks: [Track]
    let artworkTrack: Track?
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    @State private var selection = Set<Track.ID>()

    var body: some View {
        VStack(spacing: 0) {
            if let artworkTrack {
                albumHeader(artworkTrack)
                Divider()
            }
            List(tracks, selection: $selection) { track in
                HStack(spacing: 10) {
                    Text(track.trackNumber.map { String($0) } ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                    if queue.nowPlaying.trackID == track.id {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("再生中")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(track.title)
                        Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if track.scanState == .missing {
                        Label("見つかりません", systemImage: "exclamationmark.triangle")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.orange)
                    }
                    Text(formatLibraryDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard track.scanState == .available else { return }
                    Task { await queue.playNow(trackIDs: [track.id], startingAt: track.id, source: .album) }
                }
                .tag(track.id)
                .contextMenu {
                    let ids = selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]
                    QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: ids, startingAt: track.id)
                }
                .draggable(TrackDragPayload.encode(selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]))
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
    }

    private func albumHeader(_ artworkTrack: Track) -> some View {
        HStack(alignment: .bottom, spacing: 24) {
            CachedArtwork(track: artworkTrack, library: library, size: 168)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            VStack(alignment: .leading, spacing: 9) {
                Text("アルバム").font(.caption.bold()).foregroundStyle(.secondary)
                Text(title).font(.system(size: 30, weight: .bold)).lineLimit(2)
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
                Text("\(tracks.count)曲 · \(formatCollectionDuration(tracks.reduce(0) { $0 + $1.duration }))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("再生", systemImage: "play.fill") { playAlbum(shuffled: false) }
                        .buttonStyle(.borderedProminent)
                        .disabled(playback.selectedDevice?.supportsAVTransport != true || tracks.isEmpty)
                    Button("シャッフル", systemImage: "shuffle") { playAlbum(shuffled: true) }
                        .buttonStyle(.bordered)
                        .disabled(playback.selectedDevice?.supportsAVTransport != true || tracks.isEmpty)
                    Button("再生キューに追加", systemImage: "text.append") { Task { await queue.append(trackIDs: tracks.map(\.id)) } }
                        .buttonStyle(.bordered)
                        .disabled(tracks.isEmpty)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playAlbum(shuffled: Bool) {
        var ids = tracks.filter { $0.scanState == .available }.map(\.id)
        if shuffled { ids.shuffle() }
        guard let first = ids.first else { return }
        Task { await queue.playNow(trackIDs: ids, startingAt: first, source: shuffled ? .shuffle : .album) }
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
        Button("再生キューの最後に追加") { Task { await queue.append(trackIDs: trackIDs) } }
        if trackIDs.count == 1, let id = trackIDs.first {
            Button(listening.isFavorite(id) ? "お気に入りから削除" : "お気に入りに追加") { Task { await listening.toggleFavorite(id) } }
        }
        if !playlists.playlists.isEmpty {
            Menu("プレイリストに追加") {
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct LibraryFoldersView: View {
    @Bindable var library: LibraryStore
    @State private var pendingRemoval: LibraryFolder.ID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let message = library.message {
                    InlineLibraryMessage(message: message, dismiss: library.dismissMessage)
                }

                GroupBox {
                    HStack(spacing: 28) {
                        summaryValue("登録フォルダ", value: "\(library.folders.count)", icon: "folder.fill")
                        summaryValue("ライブラリ", value: "\(library.tracks.count)曲", icon: "music.note")
                        Spacer()
                        Toggle("自動更新", isOn: Binding(
                            get: { library.autoUpdateEnabled },
                            set: { enabled in Task { await library.setAutoUpdateEnabled(enabled) } }
                        ))
                        .toggleStyle(.switch)
                    }
                }

                if library.folders.isEmpty {
                    ContentUnavailableView {
                        Label("音楽フォルダがありません", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Mac内の音楽フォルダを追加すると、曲・アルバム・アーティストから探せるようになります。")
                    } actions: {
                        Button("フォルダを追加", systemImage: "folder.badge.plus") { Task { await library.addFolder() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(library.folders) { folder in
                            folderCard(folder)
                        }
                    }
                }

                if let progress = library.scanProgress, library.scanningFolderID != nil {
                    scanCard(progress)
                }

                if !library.scanNotices.isEmpty {
                    DisclosureGroup("読み込めなかった項目（\(library.scanNotices.count)件）") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(library.scanNotices) {
                                Text("\($0.relativePath ?? "場所不明"): \($0.message)").font(.caption)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                }

                Text("最終自動更新: \(library.lastAutomaticUpdate?.formatted(date: .abbreviated, time: .shortened) ?? "未実行")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("音楽フォルダ")
        .toolbar {
            Button("フォルダを追加", systemImage: "folder.badge.plus") { Task { await library.addFolder() } }
            Button("すべて再スキャン", systemImage: "arrow.clockwise") { Task { await library.scanAll() } }.disabled(library.folders.isEmpty || library.scanningFolderID != nil)
                .help(library.folders.isEmpty ? "先に音楽フォルダを追加してください" : "登録したすべてのフォルダを更新します")
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
            Text("音源ファイルは削除しません。ライブラリでは、このフォルダの曲を参照できなくなります。")
        }
    }

    private func summaryValue(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.headline)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func folderCard(_ folder: LibraryFolder) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: folder.accessState == .available ? "folder.fill" : "folder.badge.questionmark")
                    .font(.title2).foregroundStyle(folder.accessState == .available ? Color.accentColor : Color.orange)
                    .frame(width: 42, height: 42).background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.displayName).font(.headline)
                    Text("\(folder.trackCount)曲 · \(folder.lastScannedAt.map { "最終更新 \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "未更新")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更新", systemImage: "arrow.clockwise") { library.scanFolder(folder.id) }
                    .disabled(library.scanningFolderID != nil)
                Menu("管理", systemImage: "ellipsis.circle") {
                    Button("登録を解除", systemImage: "trash", role: .destructive) { pendingRemoval = folder.id }
                        .disabled(library.scanningFolderID == folder.id)
                }
                .menuStyle(.borderlessButton)
            }
            if folder.accessState == .needsReselection {
                Label("このフォルダへアクセスできません。登録を解除して、もう一度追加してください。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            DisclosureGroup("場所と詳細") {
                Text(folder.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 6)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor).opacity(0.5)))
    }

    private func scanCard(_ progress: ScanProgress) -> some View {
        GroupBox("音楽を更新しています") {
            VStack(alignment: .leading, spacing: 9) {
                ProgressView(value: Double(progress.analyzed), total: Double(max(1, progress.discovered)))
                Text(progress.currentRelativePath ?? "変更を保存しています…")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                DisclosureGroup("処理の詳細") {
                    Text("検出 \(progress.discovered) · 確認 \(progress.analyzed) · 追加 \(progress.added) · 更新 \(progress.updated) · 変更なし \(progress.unchanged) · 失敗 \(progress.failed) · 見つからない曲 \(progress.missing)")
                        .font(.caption).padding(.top, 6)
                }
                Button("更新をキャンセル", role: .cancel) { library.cancelScan() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct InlineLibraryMessage: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("閉じる", action: dismiss).buttonStyle(.borderless)
        }
        .padding(12).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }
}

private func formatLibraryDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded()); return String(format: "%d:%02d", total / 60, total % 60)
}

private func formatCollectionDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "時間不明" }
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)分" }
    return "\(minutes / 60)時間\(minutes % 60)分"
}

private func formatBitRate(_ bitsPerSecond: Double?) -> String {
    guard let bitsPerSecond, bitsPerSecond.isFinite, bitsPerSecond > 0 else { return "—" }
    return "\(Int((bitsPerSecond / 1_000).rounded())) kbps"
}

private func formatSampleRate(_ hertz: Double?) -> String {
    guard let hertz, hertz.isFinite, hertz > 0 else { return "—" }
    let kilohertz = hertz / 1_000
    let value = kilohertz.formatted(.number.precision(.fractionLength(kilohertz.rounded() == kilohertz ? 0 : 1)))
    return "\(value) kHz"
}

private func formatFileSize(_ bytes: Int64) -> String {
    guard bytes > 0 else { return "—" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func formatAudioQuality(_ track: Track) -> String {
    let values = [
        track.fileExtension.isEmpty ? nil : track.fileExtension.uppercased(),
        track.bitRate.map { formatBitRate($0) },
        track.sampleRate.map { formatSampleRate($0) },
    ].compactMap { $0 }
    return values.isEmpty ? "—" : values.joined(separator: " · ")
}
