#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import Foundation
import Observation
import SwiftUI

enum LibraryBrowseMode { case songs, albums, artists }

enum LibraryTrackScope {
    case all
    case regular
    case favorites
    case workBGM
    case highResolution

    func includes(_ track: Track) -> Bool {
        switch self {
        case .all, .favorites: true
        case .regular: track.isRegularLibraryTrack
        case .workBGM: track.isEligibleForWorkPlayback
        case .highResolution: track.isHighResolutionAudio
        }
    }
}

struct LibraryView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    @Bindable var preferences: PlaybackPreferenceStore
    @Bindable var genrePresets: GenreDisplayPresetStore
    let mode: LibraryBrowseMode
    var scope: LibraryTrackScope = .all
    @AppStorage("library.artists.hide-single-track") private var hidesSingleTrackArtists = false
    @AppStorage("library.albums.hide-single-track") private var hidesSingleTrackAlbums = false
    @State private var searchPresented = false
    @AppStorage("library.songs.table-columns")
    private var songTableColumns = TableColumnCustomization<Track>()

    var body: some View {
        NavigationStack {
            Group {
                if library.tracks.isEmpty { emptyView }
                else if mode == .songs, scope != .all, scopedTracks.isEmpty, normalizedSearch.isEmpty {
                    scopedEmptyView
                }
                else if mode == .albums, hidesSingleTrackAlbums, displayedAlbums.isEmpty, !library.albums.isEmpty {
                    singleTrackAlbumsEmptyView
                }
                else if mode == .artists, hidesSingleTrackArtists, displayedArtists.isEmpty, !library.artists.isEmpty {
                    singleTrackArtistsEmptyView
                }
                else if hasNoSearchResults { noSearchResultsView }
                else if library.visibleTracks.isEmpty { noGenreResultsView }
                else if (mode == .albums && displayedAlbums.isEmpty) || (mode == .artists && displayedArtists.isEmpty) {
                    ContentUnavailableView("表示する項目がありません", systemImage: "music.note", description: Text("アルバム・アーティストには通常曲だけを表示します。作業用BGMとハイレゾは専用の曲一覧から確認できます。"))
                }
                else {
                    switch mode {
                    case .songs: SongsTable(
                        playback: playback, library: library, queue: queue, playlists: playlists,
                        listening: listening, preferences: preferences, tracks: scopedTracks,
                        columnCustomization: $songTableColumns,
                        playSource: scope == .favorites ? .favorite : .library
                    )
                    case .albums: AlbumsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, albums: displayedAlbums)
                    case .artists: ArtistsList(playback: playback, library: library, queue: queue, playlists: playlists, listening: listening, artists: displayedArtists)
                    }
                }
            }
            .navigationTitle(title)
            .searchable(text: $library.searchText, isPresented: $searchPresented, prompt: "ライブラリを検索")
            .onChange(of: library.searchFocusRequest) { _, _ in searchPresented = true }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if !playback.canPlaySelectedOutput {
                        HStack(spacing: 10) {
                            Image(systemName: "1.circle.fill").foregroundStyle(.orange)
                            Text(!playback.hasSelectedOutput
                                 ? "再生するには、先に出力先を選んでください。"
                                 : "選択中の機器では再生操作を利用できません。")
                                .font(.callout)
                            Spacer()
                            Button("出力先を選ぶ") { playback.destination = .devices }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        Divider()
                    }
                    if !library.tracks.isEmpty {
                        if !genrePresets.presets.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    presetTag("すべて", selected: library.selectedGenrePresetID == nil && library.selectedGenre == nil) {
                                        library.applyGenrePreset(nil)
                                    }
                                    ForEach(genrePresets.presets) { preset in
                                        presetTag(preset.name, selected: library.selectedGenrePresetID == preset.id) {
                                            library.applyGenrePreset(preset)
                                        }
                                    }
                                    Button("編集", systemImage: "slider.horizontal.3") {
                                        playback.destination = .genrePresets
                                    }
                                    .buttonStyle(.borderless)
                                    .help("ジャンルプリセットを編集")
                                }
                                .padding(.horizontal, 14).padding(.vertical, 7)
                            }
                            Divider()
                        }
                        HStack {
                            Text(resultSummary).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !library.genres.isEmpty {
                                Menu {
                                    Button {
                                        library.applySingleGenre(nil)
                                    } label: {
                                        if library.selectedGenre == nil {
                                            Label("すべてのジャンル", systemImage: "checkmark")
                                        } else {
                                            Text("すべてのジャンル")
                                        }
                                    }
                                    Divider()
                                    ForEach(library.genres, id: \.self) { genre in
                                        Button {
                                            library.applySingleGenre(genre)
                                        } label: {
                                            if library.selectedGenre == genre {
                                                Label(genre, systemImage: "checkmark")
                                            } else {
                                                Text(genre)
                                            }
                                        }
                                    }
                                } label: {
                                    Label(library.selectedGenre ?? "すべてのジャンル", systemImage: "line.3.horizontal.decrease.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("曲一覧をジャンルで絞り込み")
                            }
                            if mode == .albums {
                                Toggle("1曲のアルバムを隠す", isOn: $hidesSingleTrackAlbums)
                                    .toggleStyle(.button)
                                    .help("表示中の収録曲が1曲のアルバムを非表示にします。音源データは変更しません。")
                            }
                            if mode == .artists {
                                Toggle("1曲のアーティストを隠す", isOn: $hidesSingleTrackArtists)
                                    .toggleStyle(.button)
                                    .help("表示中の曲が1曲のアーティストを非表示にします。音源データは変更しません。")
                            }
                            if mode == .songs {
                                Menu("表示項目", systemImage: "tablecells") {
                                    Toggle("音質", isOn: columnVisibilityBinding("audioQuality"))
                                    Toggle("サイズ", isOn: columnVisibilityBinding("fileSize"))
                                    Toggle("ファイルパス", isOn: columnVisibilityBinding("filePath"))
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("曲一覧に表示する追加情報を選択")
                            }
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
                .homeStereoThemeBar()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                CreateQueueButton(queue: queue, trackIDs: queueCandidateIDs)

                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
            .alert("評価を保存できませんでした", isPresented: preferenceErrorPresented) {
                Button("OK") { preferences.dismissError() }
            } message: {
                Text(preferences.errorMessage ?? "不明なエラー")
            }
        }
    }

    private func presetTag(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String {
        switch scope {
        case .favorites: return "お気に入り"
        case .regular: break
        case .workBGM: return "作業用BGM"
        case .highResolution: return "ハイレゾ"
        case .all: break
        }
        return switch mode { case .songs: "曲"; case .albums: "アルバム"; case .artists: "アーティスト" }
    }

    private var scopedTracks: [Track] {
        let favoriteIDs = scope == .favorites ? Set(listening.favorites.map(\.trackID)) : []
        return library.visibleTracks.filter {
            scope.includes($0) && (scope != .favorites || favoriteIDs.contains($0.id))
        }
    }

    private var displayedAlbums: [LibraryAlbum] {
        hidesSingleTrackAlbums ? library.albums.filter { $0.tracks.count > 1 } : library.albums
    }

    private var singleTrackAlbumsEmptyView: some View {
        ContentUnavailableView {
            Label("表示するアルバムがありません", systemImage: "square.stack")
        } description: {
            Text("「1曲のアルバムを隠す」が有効です。ジャンルの絞り込み後の収録曲数で判定します。")
        } actions: {
            Button("1曲のアルバムも表示") { hidesSingleTrackAlbums = false }
        }
    }

    private var displayedArtists: [LibraryArtist] {
        hidesSingleTrackArtists ? library.artists.filter { $0.tracks.count > 1 } : library.artists
    }

    private var singleTrackArtistsEmptyView: some View {
        ContentUnavailableView {
            Label("表示するアーティストがありません", systemImage: "music.mic")
        } description: {
            Text("「1曲のアーティストを隠す」が有効です。通常曲・ジャンルの絞り込み後の曲数で判定します。")
        } actions: {
            Button("1曲のアーティストも表示") { hidesSingleTrackArtists = false }
        }
    }

    private var queueCandidateIDs: [Track.ID] {
        switch mode {
        case .songs: scopedTracks.map(\.id)
        case .albums: displayedAlbums.flatMap { $0.tracks.map(\.id) }
        case .artists: displayedArtists.flatMap { $0.tracks.map(\.id) }
        }
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

    private var noGenreResultsView: some View {
        ContentUnavailableView {
            Label("ジャンルに合う曲がありません", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("プリセットやジャンルを変更するか、「すべて」を選んでください。")
        } actions: {
            Button("すべてのジャンルを表示") { library.applyGenrePreset(nil) }
        }
    }

    private var scopedEmptyView: some View {
        ContentUnavailableView {
            Label(scopedEmptyTitle, systemImage: scopedEmptyIcon)
        } description: {
            Text(scopedEmptyDescription)
        }
    }

    private var scopedEmptyTitle: String {
        switch scope {
        case .favorites: listening.favorites.isEmpty ? "お気に入りはありません" : "条件に一致するお気に入りはありません"
        case .regular: "通常の曲はありません"
        case .workBGM: "作業用BGMはありません"
        case .highResolution: "ハイレゾ音源はありません"
        case .all: "曲はありません"
        }
    }

    private var scopedEmptyIcon: String {
        switch scope {
        case .favorites: "heart"
        case .regular, .all: "music.note"
        case .workBGM: "timer"
        case .highResolution: "waveform"
        }
    }

    private var scopedEmptyDescription: String {
        switch scope {
        case .favorites: "曲のハートボタンで追加できます。ジャンルで絞り込んでいる場合は「すべて」を選ぶと全件表示できます。"
        case .regular: "作業用BGMとハイレゾ以外の曲がここに表示されます。"
        case .workBGM: "ジャンルに「作業用BGM」が設定された曲がここに表示されます。"
        case .highResolution: "ジャンルが「ハイレゾ」、または44.1kHz・16bit以上で24bit以上／48kHz超の音源が表示されます。"
        case .all: "「フォルダ」からMac上の音楽フォルダを登録してください。"
        }
    }

    private var normalizedSearch: String {
        library.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasNoSearchResults: Bool {
        guard !normalizedSearch.isEmpty else { return false }
        switch mode {
        case .songs: return scopedTracks.isEmpty
        case .albums: return displayedAlbums.isEmpty
        case .artists: return displayedArtists.isEmpty
        }
    }

    private var resultSummary: String {
        let count: Int
        let unit: String
        switch mode {
        case .songs: count = scopedTracks.count; unit = "曲"
        case .albums: count = displayedAlbums.count; unit = "アルバム"
        case .artists: count = displayedArtists.count; unit = "組"
        }
        let presetName = genrePresets.presets.first { $0.id == library.selectedGenrePresetID }?.name
        let genrePrefix = (presetName ?? library.selectedGenre).map { "\($0) · " } ?? ""
        return normalizedSearch.isEmpty
            ? "\(genrePrefix)\(count)\(unit)"
            : "\(genrePrefix)「\(normalizedSearch)」の検索結果：\(count)\(unit)"
    }

    private func columnVisibilityBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { songTableColumns[visibility: id] == .visible },
            set: { songTableColumns[visibility: id] = $0 ? .visible : .hidden }
        )
    }

    private var preferenceErrorPresented: Binding<Bool> {
        Binding(
            get: { preferences.errorMessage != nil },
            set: { if !$0 { preferences.dismissError() } }
        )
    }
}

// Keep a prepared permutation between renders. Work is explicit and off the main actor.
@MainActor
@Observable
private final class RandomTrackDisplay {
    private(set) var tracks: [Track]?
    private(set) var isPreparing = false
    private(set) var presentationID = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    func randomize(_ source: [Track]) {
        reset()
        isPreparing = true
        let generation = presentationID
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { source.shuffled() }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, let self, self.presentationID == generation else { return }
            self.tracks = result
            self.isPreparing = false
            self.presentationID = UUID()
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        tracks = nil
        isPreparing = false
        presentationID = UUID()
    }
}

private struct RandomTrackDisplayControls: View {
    let display: RandomTrackDisplay
    let tracks: [Track]

    var body: some View {
        HStack(spacing: 10) {
            Button("ランダム表示", systemImage: "shuffle") { display.randomize(tracks) }
                .disabled(tracks.count < 2 || display.isPreparing)
                .help("表示中の曲をランダムに並べ替えます")
            if display.isPreparing {
                ProgressView().controlSize(.small)
                Text("並べ替え中…").font(.caption).foregroundStyle(.secondary)
            }
            if display.tracks != nil {
                Button("元の順序に戻す", systemImage: "arrow.uturn.backward") { display.reset() }
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .homeStereoThemeBar()
    }
}

private struct SongsTable: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    @Bindable var preferences: PlaybackPreferenceStore
    let tracks: [Track]
    @Binding var columnCustomization: TableColumnCustomization<Track>
    var playSource: MyMusicPlaySource = .library
    @State private var randomDisplay = RandomTrackDisplay()

    var body: some View {
        VStack(spacing: 0) {
            RandomTrackDisplayControls(display: randomDisplay, tracks: tracks)
            Table(
                randomDisplay.tracks ?? tracks,
                selection: $library.selectedTrackIDs,
                sortOrder: tableSortOrder,
                columnCustomization: $columnCustomization
            ) {
                TableColumn("") { track in
                    songActionButtons(track)
                }
                .width(156)
                TableColumn("曲名", sortUsing: LibraryTrackComparator(sort: .title)) { track in
                    HStack(spacing: 9) {
                        CachedArtwork(track: track, library: library, size: 34)
                        Image(systemName: track.scanState == .available ? "music.note" : "exclamationmark.triangle")
                            .foregroundStyle(track.scanState == .available ? Color.secondary : Color.orange)
                            .accessibilityLabel(track.scanState == .available ? "利用可能" : "ファイルが見つかりません")
                        Text(track.title).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(trackTapGesture(track))
                    .help("ダブルクリックでキューの最後に追加")
                    .contextMenu {
                        let ids = selectedTrackIDs(for: track)
                        QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: ids, startingAt: track.id)
                    }
                    .draggable(TrackDragPayload.encode(selectedTrackIDs(for: track)))
                }
                .width(min: 200, ideal: 300)
                TableColumn("アーティスト", sortUsing: LibraryTrackComparator(sort: .artist)) { track in
                    rowClickTarget(Text(track.artist ?? "—"), track: track)
                }
                TableColumn("アルバム", sortUsing: LibraryTrackComparator(sort: .album)) { track in
                    rowClickTarget(Text(track.album ?? "—"), track: track)
                }
                TableColumn("ジャンル", sortUsing: LibraryTrackComparator(sort: .genre)) { track in
                    rowClickTarget(Text(track.genre ?? "—").lineLimit(1), track: track)
                }
                    .width(min: 72, ideal: 100)
                TableColumn("年", sortUsing: LibraryTrackComparator(sort: .releaseYear)) { track in
                    rowClickTarget(Text(track.releaseYear.map(String.init) ?? "—").monospacedDigit(), track: track)
                }
                    .width(54)
                TableColumn("時間", sortUsing: LibraryTrackComparator(sort: .duration)) { track in
                    rowClickTarget(Text(formatLibraryDuration(track.duration)), track: track)
                }
                .width(64)
                TableColumn("音質") { track in
                    rowClickTarget(Text(formatAudioQuality(track)).monospacedDigit().lineLimit(1), track: track)
                }
                .width(min: 130, ideal: 180)
                .customizationID("audioQuality")
                .defaultVisibility(.hidden)
                TableColumn("サイズ") { track in
                    rowClickTarget(Text(formatFileSize(track.fileSize)).monospacedDigit(), track: track)
                }
                .width(78)
                .customizationID("fileSize")
                .defaultVisibility(.hidden)
                TableColumn("ファイルパス") { track in
                    Text(track.url.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(track.url.path)
                        .contentShape(Rectangle())
                        .simultaneousGesture(trackTapGesture(track))
                }
                .width(min: 140, ideal: 240)
                .customizationID("filePath")
                .defaultVisibility(.hidden)
            }
            // AppKit can eagerly measure thousands of inserted rows when a narrow
            // filter is cleared. Replace the native table with the prepared result.
            .id(library.browserPresentationID.uuidString + randomDisplay.presentationID.uuidString)
            .alternatingRowBackgrounds(.disabled)
        }
        .onChange(of: library.browserPresentationID) { _, _ in randomDisplay.reset() }
        .onChange(of: playSource == .favorite ? listening.favorites.map(\.trackID) : []) { _, _ in
            randomDisplay.reset()
        }
        .onDisappear { randomDisplay.reset() }
    }

    private func play(_ track: Track) {
        guard track.scanState == .available else { return }
        Task {
            await queue.playImmediately(trackID: track.id, source: playSource)
        }
    }

    private func songActionButtons(_ track: Track) -> some View {
        HStack(spacing: 4) {
            Button {
                play(track)
            } label: {
                Image(systemName: queue.nowPlaying.trackID == track.id ? "speaker.wave.2.fill" : "play.fill")
                    .foregroundStyle(queue.nowPlaying.trackID == track.id ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(track.scanState != .available || !playback.canPlaySelectedOutput)
            .help(rowPlayHelp(track))
            .accessibilityLabel(queue.nowPlaying.trackID == track.id ? "再生中：\(track.title)" : "\(track.title)を今すぐ再生")

            Button {
                append(track)
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(track.scanState != .available)
            .help(track.scanState == .available ? "再生キューの最後に追加" : "この曲のファイルが見つかりません")
            .accessibilityLabel("\(track.title)を再生キューの最後に追加")

            playlistMenu(track)

            Button {
                Task { await listening.toggleFavorite(track.id) }
            } label: {
                Image(systemName: listening.isFavorite(track.id) ? "heart.fill" : "heart")
                    .foregroundStyle(listening.isFavorite(track.id) ? Color.pink : Color.secondary)
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .help(listening.isFavorite(track.id) ? "お気に入りから削除" : "お気に入りに追加")
            .accessibilityLabel("\(track.title)を\(listening.isFavorite(track.id) ? "お気に入りから削除" : "お気に入りに追加")")

            preferenceButtons(track)
        }
    }

    private func playlistMenu(_ track: Track) -> some View {
        let compatiblePlaylists = playlists.compatiblePlaylists(for: [track.id])
        return Menu {
            if compatiblePlaylists.isEmpty {
                Text("追加できるプレイリストがありません")
            } else {
                ForEach(compatiblePlaylists) { playlist in
                    Button(playlist.name) {
                        Task { await playlists.add(trackIDs: [track.id], to: playlist.id) }
                    }
                }
            }
        } label: {
            Image(systemName: "text.badge.plus")
                .foregroundStyle(Color.secondary)
                .frame(width: 22, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("プレイリストに追加")
        .accessibilityLabel("\(track.title)をプレイリストに追加")
    }

    private func append(_ track: Track) {
        guard track.scanState == .available else { return }
        Task { await queue.append(trackIDs: [track.id]) }
    }

    private func preferenceButtons(_ track: Track) -> some View {
        let value = preferences.preference(for: track.id)
        return HStack(spacing: 6) {
            Button {
                Task { await preferences.adjustPreference(trackID: track.id, delta: 1) }
            } label: {
                preferenceIcon(
                    systemName: value > 0 ? "hand.thumbsup.fill" : "hand.thumbsup",
                    color: value > 0 ? .green : .secondary,
                    badgeValue: value > 0 ? value : nil
                )
            }
            .buttonStyle(.plain)
            .disabled(value >= 10)
            .help(value >= 10 ? "Good評価は上限の+10です" : "Good評価を1増やす（現在 \(value)）")
            .accessibilityLabel("\(track.title)のGood評価を1増やす")
            .accessibilityValue("現在 \(value)、上限 10")

            Button {
                Task { await preferences.adjustPreference(trackID: track.id, delta: -1) }
            } label: {
                preferenceIcon(
                    systemName: value < 0 ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                    color: value < 0 ? .orange : .secondary,
                    badgeValue: value < 0 ? abs(value) : nil
                )
            }
            .buttonStyle(.plain)
            .disabled(value <= -10)
            .help(value <= -10 ? "Bad評価は下限の-10です" : "Bad評価を1減らす（現在 \(value)）")
            .accessibilityLabel("\(track.title)のBad評価を1減らす")
            .accessibilityValue("現在 \(value)、下限 -10")
        }
    }

    private func preferenceIcon(systemName: String, color: Color, badgeValue: Int?) -> some View {
        Image(systemName: systemName)
            .foregroundStyle(color)
            .frame(width: 22, height: 24)
            .overlay(alignment: .topTrailing) {
                if let badgeValue {
                    Text("\(badgeValue)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 13, minHeight: 13)
                        .padding(.horizontal, badgeValue >= 10 ? 1 : 0)
                        .background(color, in: Capsule())
                        .offset(x: 5, y: -2)
                        .accessibilityHidden(true)
                }
            }
    }

    private func trackTapGesture(_ track: Track) -> some Gesture {
        TapGesture(count: 2)
            .onEnded { _ in append(track) }
    }

    private func rowClickTarget<Content: View>(_ content: Content, track: Track) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(trackTapGesture(track))
            .help("ダブルクリックでキューの最後に追加")
    }

    private func selectedTrackIDs(for track: Track) -> [Track.ID] {
        guard library.selectedTrackIDs.contains(track.id) else { return [track.id] }
        return tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
    }

    private var selectedTrackIDs: [Track.ID] {
        tracks.map(\.id).filter { library.selectedTrackIDs.contains($0) }
    }

    private var tableSortOrder: Binding<[LibraryTrackComparator]> {
        Binding(
            get: {
                if randomDisplay.tracks != nil { return [] }
                return [LibraryTrackComparator(
                    sort: library.sort,
                    order: library.sortDirection == .ascending ? .forward : .reverse
                )]
            },
            set: { order in
                guard let comparator = order.first else { return }
                randomDisplay.reset()
                library.setSort(
                    comparator.sort,
                    direction: comparator.order == .forward ? .ascending : .descending
                )
            }
        )
    }

    private func rowPlayHelp(_ track: Track) -> String {
        if track.scanState != .available { return "この曲のファイルが見つかりません" }
        if !playback.hasSelectedOutput { return "先に再生先を選んでください" }
        if !playback.canPlaySelectedOutput { return "選択した機器では再生できません" }
        return "\(track.title)を今すぐ再生"
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
                            Text(albumArtistLabel(album))
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
                    .accessibilityLabel("\(album.title)、\(albumArtistLabel(album))、\(album.tracks.count)曲")
                }
            }
            .padding(24)
        }
        .navigationDestination(for: LibraryAlbum.ID.self) { id in
            if let album = library.albums.first(where: { $0.id == id }) {
                CollectionDetail(
                    title: album.title, subtitle: albumArtistLabel(album),
                    tracks: album.tracks, artworkTrack: album.tracks.first,
                    playback: playback, library: library, queue: queue, playlists: playlists, listening: listening
                )
            }
        }
    }
}

private func albumArtistLabel(_ album: LibraryAlbum) -> String {
    if let albumArtist = album.albumArtist { return albumArtist }
    let artists = Set(album.tracks.compactMap(\.artist))
    if artists.count > 1 { return "複数のアーティスト" }
    return artists.first ?? "不明なアーティスト"
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
                albumArtist: nil,
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

    @State private var randomDisplay = RandomTrackDisplay()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                artistHeader
                Divider()
                RandomTrackDisplayControls(display: randomDisplay, tracks: artist.tracks)
                if let tracks = randomDisplay.tracks {
                    ForEach(tracks) { track in
                        ArtistTrackRow(
                            track: track, playback: playback, queue: queue,
                            playlists: playlists, listening: listening
                        )
                        .padding(.horizontal, 24)
                    }
                } else {
                    ForEach(albumGroups) { group in
                        albumSection(group)
                        Divider().padding(.leading, 24)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {  CreateQueueButton(queue: queue, trackIDs: artist.tracks.map(\.id))
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
        .navigationTitle(artist.name)
        .navigationSubtitle("アーティスト")
        .onChange(of: artist.id) { _, _ in randomDisplay.reset() }
        .onChange(of: library.revision) { _, _ in randomDisplay.reset() }
        .onDisappear { randomDisplay.reset() }
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
                    .disabled(!playback.canPlaySelectedOutput || availableTrackIDs.isEmpty)
                Button("シャッフル", systemImage: "shuffle") { play(shuffled: true) }
                    .buttonStyle(.bordered)
                    .disabled(!playback.canPlaySelectedOutput || availableTrackIDs.isEmpty)
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
                .disabled(!playback.canPlaySelectedOutput)
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
            albumArtist: nil,
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
            }
            .contentShape(Rectangle())
            .simultaneousGesture(trackTapGesture)
            .help("ダブルクリックでキューの最後に追加")
            Button("今すぐ再生", systemImage: "play.fill") {
                Task { await queue.playImmediately(trackID: track.id, source: .artist) }
            }
            .labelStyle(.iconOnly)
            .disabled(track.scanState != .available || !playback.canPlaySelectedOutput)
        }
        .padding(.vertical, 4)
        .contextMenu {
            QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: [track.id], startingAt: track.id)
        }
        .draggable(TrackDragPayload.encode([track.id]))
    }

    private var trackTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded { _ in
                guard track.scanState == .available else { return }
                Task { await queue.append(trackIDs: [track.id]) }
            }
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
    @State private var randomDisplay = RandomTrackDisplay()
    @State private var selection = Set<Track.ID>()

    var body: some View {
        VStack(spacing: 0) {
            if let artworkTrack {
                albumHeader(artworkTrack)
                Divider()
            }
            RandomTrackDisplayControls(display: randomDisplay, tracks: tracks)
            List(randomDisplay.tracks ?? tracks, selection: $selection) { track in
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
                .simultaneousGesture(trackTapGesture(track))
                .help("ダブルクリックでキューの最後に追加")
                .tag(track.id)
                .contextMenu {
                    let ids = selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]
                    QueueContextMenu(queue: queue, playlists: playlists, listening: listening, trackIDs: ids, startingAt: track.id)
                }
                .draggable(TrackDragPayload.encode(selection.contains(track.id) ? tracks.map(\.id).filter { selection.contains($0) } : [track.id]))
            }
            .id(randomDisplay.presentationID)
        }
        .onChange(of: tracks) { _, _ in randomDisplay.reset() }
        .onDisappear { randomDisplay.reset() }
        .navigationTitle(title)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {  CreateQueueButton(queue: queue, trackIDs: tracks.map(\.id))
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
        .navigationSubtitle(subtitle)
    }

    private func trackTapGesture(_ track: Track) -> some Gesture {
        TapGesture(count: 2)
            .onEnded { _ in
                guard track.scanState == .available else { return }
                Task { await queue.append(trackIDs: [track.id]) }
            }
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
                        .disabled(!playback.canPlaySelectedOutput || tracks.isEmpty)
                    Button("シャッフル", systemImage: "shuffle") { playAlbum(shuffled: true) }
                        .buttonStyle(.bordered)
                        .disabled(!playback.canPlaySelectedOutput || tracks.isEmpty)
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
        let compatiblePlaylists = playlists.compatiblePlaylists(for: trackIDs)
        if !compatiblePlaylists.isEmpty {
            Menu("プレイリストに追加") {
                ForEach(compatiblePlaylists) { playlist in
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
            Button("フォルダを追加", systemImage: "folder.badge.plus") { Task { await library.addFolder() } }
            Button("すべて再スキャン", systemImage: "arrow.clockwise") { Task { await library.scanAll() } }.disabled(library.folders.isEmpty || library.scanningFolderID != nil)
                .help(library.folders.isEmpty ? "先に音楽フォルダを追加してください" : "登録したすべてのフォルダを更新します")

                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
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
        .homeStereoThemeSurface(cornerRadius: 14)
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

struct CreateQueueButton: View {
    @Bindable var queue: QueueStore
    let trackIDs: [Track.ID]

    var body: some View {
        Button("最大100曲でキュー作成", systemImage: "text.badge.plus") {
            Task { await queue.createFromCandidates(trackIDs: trackIDs) }
        }
        .disabled(trackIDs.isEmpty || queue.isTransitioning)
        .help("表示中の曲から待ち曲を作り直します。再生中の曲は続け、合計100曲以内。候補が多い場合はGood評価が高い曲ほど抽選で選ばれやすくなります。")
    }
}
