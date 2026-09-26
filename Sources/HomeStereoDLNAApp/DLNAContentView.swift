#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif
import SwiftUI

struct DLNAContentView: View {
    @Bindable var store: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playlists: PlaylistStore
    @Bindable var listening: ListeningStore
    @Bindable var recovery: RecoveryStore
    @Bindable var backup: BackupStore
    @Bindable var myMusic: MyMusicTransferStore
    @SceneStorage("main.sidebar.visibility") private var sidebarVisibility = "all"
    @AppStorage("main.queueInspector.visible.compactV1") private var queueInspectorVisible = false
    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: Binding(
                get: { sidebarVisibility == "detail" ? .detailOnly : .all },
                set: { sidebarVisibility = $0 == .detailOnly ? "detail" : "all" }
            )) {
                List(selection: $store.destination) {
                    Section("ライブラリ") {
                        Label("曲", systemImage: "music.note").tag(DLNASidebarDestination.songs)
                        Label("アルバム", systemImage: "square.stack").tag(DLNASidebarDestination.albums)
                        Label("アーティスト", systemImage: "music.mic").tag(DLNASidebarDestination.artists)
                    }
                    Section("コレクション") {
                        Label("お気に入り", systemImage: "heart").tag(DLNASidebarDestination.favorites)
                        Label("履歴", systemImage: "clock.arrow.circlepath").tag(DLNASidebarDestination.history)
                        Label("プレイリスト", systemImage: "music.note.list").tag(DLNASidebarDestination.playlists)
                    }
                    Section("再生") {
                        Label("スピーカー", systemImage: "hifispeaker.2").tag(DLNASidebarDestination.devices)
                        Label("再生中", systemImage: "play.circle").tag(DLNASidebarDestination.playback)
                        Label("次はこちら", systemImage: "list.number").tag(DLNASidebarDestination.queue)
                    }
                    Section("管理") {
                        Label("フォルダ", systemImage: "folder").tag(DLNASidebarDestination.folders)
                        Label("バックアップ", systemImage: "externaldrive").tag(DLNASidebarDestination.backup)
                        Label("MyMusic連携", systemImage: "arrow.left.arrow.right.circle").tag(DLNASidebarDestination.myMusic)
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle("HomeStereo")
                .navigationSplitViewColumnWidth(min: 165, ideal: 185)
            } detail: {
                switch store.destination {
                case .devices: DevicesView(store: store, recovery: recovery) { store.destination = .songs }
                case .songs: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .songs)
                case .albums: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .albums)
                case .artists: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .artists)
                case .folders: LibraryFoldersView(library: library)
                case .queue: QueueView(playback: store, queue: queue, library: library)
                case .playlists:
                    PlaylistsView(playback: store, store: playlists, queue: queue, library: library)
                case .favorites:
                    ListeningView(
                        playback: store, store: listening, queue: queue,
                        library: library, playlists: playlists, mode: .favorites
                    )
                case .history:
                    ListeningView(
                        playback: store, store: listening, queue: queue,
                        library: library, playlists: playlists, mode: .history
                    )
                case .backup: BackupView(store: backup)
                case .myMusic: MyMusicTransferView(store: myMusic)
                case .playback: PlaybackView(store: store, queue: queue, library: library)
                }
            }

            Divider()
            if let error = store.lastError {
                PlaybackErrorBanner(store: store, error: error)
                Divider()
            }
            MainNowPlayingBar(store: store, library: library, queue: queue, listening: listening)
            if recovery.state != .connected {
                Divider()
                HStack {
                    Image(systemName: "wifi.exclamationmark")
                    Text(recoveryStatus)
                    Spacer()
                    Button("再接続") { recovery.reconnectManually() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .inspector(isPresented: $queueInspectorVisible) {
            QueueView(playback: store, queue: queue, library: library)
                .inspectorColumnWidth(min: 260, ideal: 340, max: 480)
        }
        .toolbar {
            Button(queueInspectorVisible ? "再生キューを閉じる" : "再生キューを開く", systemImage: "sidebar.trailing") {
                queueInspectorVisible.toggle()
            }
            .accessibilityHint("再生キューのインスペクタを切り替えます")
        }
        .alert("再生を再開しますか？", isPresented: Binding(
            get: { recovery.shouldAskToResume }, set: { if !$0 { recovery.declineResume() } }
        )) {
            Button("再開") { Task { await recovery.resume() } }
            Button("今はしない", role: .cancel) { recovery.declineResume() }
        } message: { Text("スリープまたは通信切断前に再生中だった曲を、現在の再生キュー位置から再開します。音量は変更しません。") }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var recoveryStatus: String {
        switch recovery.state {
        case .connected: "接続済み"
        case .sleeping: "スリープ前の状態を保存しました"
        case .waitingForNetwork: "ネットワークの復帰を待っています"
        case let .reconnecting(attempt): "スピーカーを再検索中（\(attempt)回目）"
        case .readyToResume: "スピーカーへ再接続しました"
        case let .disconnected(message): message
        }
    }
}

private struct PlaybackErrorBanner: View {
    @Bindable var store: RendererPlaybackStore
    let error: PlaybackDiagnostic

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("スピーカーとの操作を完了できませんでした").font(.subheadline.bold())
                Text(error.details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("再試行") {
                Task {
                    if store.selectedDevice == nil { await store.discoverRenderers() }
                    else { await store.refreshState() }
                }
            }
            Button("閉じる") { store.dismissError() }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.09))
        .accessibilityElement(children: .contain)
    }
}

private struct MainNowPlayingBar: View {
    @Bindable var store: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var listening: ListeningStore
    @State private var pendingSeek: Double = 0
    @State private var isSeeking = false
    @State private var pendingVolume: Double = 0

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
                .frame(minWidth: 820)
            compactLayout
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .onAppear {
            synchronizePendingSeek(nowPlaying.elapsed)
            pendingVolume = store.volume
        }
        .onChange(of: nowPlaying.elapsed) { _, value in synchronizePendingSeek(value) }
        .onChange(of: nowPlaying.duration) { _, _ in synchronizePendingSeek(nowPlaying.elapsed) }
        .onChange(of: store.volume) { _, value in pendingVolume = value }
    }

    private var regularLayout: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                trackSummary
                .frame(maxWidth: .infinity, alignment: .leading)

                playbackControls

                playbackStatus(showsVolume: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            seekControl
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                trackSummary
                Spacer(minLength: 8)
                playbackStatus(showsVolume: false)
            }
            seekControl
            HStack {
                Spacer()
                playbackControls
                Spacer()
                audioLevelControls
            }
        }
    }

    private var trackSummary: some View {
        HStack(spacing: 10) {
            if let track = queue.nowPlayingTrack {
                CachedArtwork(track: track, library: library, size: 44)
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel("Artworkなし")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title ?? emptyTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(trackSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            QueueModeControls(queue: queue)
            if store.isSonyStereoSelected {
                Button(
                    store.isStereoSynchronizationCheckActive ? "同期チェック中" : "遅延チェック",
                    systemImage: "waveform.path.ecg"
                ) {
                    Task { await store.playStereoSynchronizationCheck() }
                }
                .disabled(store.isBusy || store.playbackState == .playing)
                .help(synchronizationCheckHelp)
                .accessibilityHint("左右のクリックが中央で一つに聞こえるか確認します")
            }
            Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
                .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                .help(nowPlaying.isQueueTrack ? "再生キューの前の曲へ移動" : "直接選択したファイルでは前の曲へ移動できません")
            Button(nowPlaying.state == .playing ? "一時停止" : "再生", systemImage: nowPlaying.state == .playing ? "pause.fill" : "play.fill") {
                Task { await queue.togglePlayback() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(playbackDisabledReason != nil)
            .help(playbackDisabledReason ?? (nowPlaying.state == .playing ? "再生を一時停止" : "選択した曲を再生"))
            Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
                .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                .help(nowPlaying.isQueueTrack ? "再生キューの次の曲へ移動" : "直接選択したファイルでは次の曲へ移動できません")
            Button(favoriteButtonTitle, systemImage: isFavorite ? "heart.fill" : "heart") {
                guard let trackID = queue.nowPlayingTrack?.id else { return }
                Task { await listening.toggleFavorite(trackID) }
            }
            .disabled(queue.nowPlayingTrack == nil)
            .help(favoriteButtonHelp)
            .accessibilityValue(isFavorite ? "お気に入り" : "お気に入りではありません")
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    private func playbackStatus(showsVolume: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            rendererMenu
            if showsVolume { audioLevelControls }
            HStack(spacing: 5) {
                Image(systemName: stateIcon)
                Text(stateLabel)
                if nowPlaying.hasMedia {
                    Text("\(formatPlaybackTime(nowPlaying.elapsed)) / \(formatPlaybackTime(nowPlaying.duration))")
                }
            }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var rendererMenu: some View {
        Menu {
            if store.devices.isEmpty {
                Text(store.isDiscovering ? "スピーカーを検索中…" : "スピーカーが見つかりません")
            } else {
                if store.sonyStereoPair != nil {
                    Button {
                        store.selectSonyStereo()
                    } label: {
                        Label("Sonyステレオ", systemImage: store.isSonyStereoSelected ? "checkmark" : "hifispeaker.2")
                    }
                    Divider()
                    Text("個別のスピーカー")
                }
                ForEach(store.devices) { device in
                    Button {
                        store.selectDevice(device.id)
                    } label: {
                        if !store.isSonyStereoSelected && device.id == store.selectedDeviceID {
                            Label(device.friendlyName, systemImage: "checkmark")
                        } else {
                            Text(device.friendlyName)
                        }
                    }
                }
            }
            Divider()
            Button("スピーカーを再検索", systemImage: "arrow.clockwise") {
                Task { await store.discoverRenderers() }
            }
            .disabled(store.isDiscovering)
        } label: {
            Label(store.selectedOutputName, systemImage: store.isSonyStereoSelected ? "hifispeaker.2.fill" : "hifispeaker")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .help("再生先のスピーカーを選択")
        .accessibilityLabel("出力先スピーカー")
        .accessibilityValue(store.selectedOutputName)
    }

    private var audioLevelControls: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: pendingVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
                Slider(value: $pendingVolume, in: 0...100, step: 1) { editing in
                    if !editing { Task { await store.setVolume(pendingVolume) } }
                }
                .frame(width: 112)
                .accessibilityLabel("スピーカー音量")
                .accessibilityValue("\(Int(pendingVolume))パーセント")
                Text("\(Int(pendingVolume))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }
            if store.isSonyStereoSelected {
                StereoBalanceControl(store: store, sliderWidth: 112)
            }
        }
        .disabled(store.selectedDevice?.description?.renderingControl == nil || store.isBusy)
        .help(store.isSonyStereoSelected ? "マスター音量と左右バランスを変更" : "スピーカーの音量を変更")
    }

    private var seekControl: some View {
        HStack(spacing: 8) {
            Text(formatPlaybackTime(isSeeking ? pendingSeek : nowPlaying.elapsed))
                .frame(width: 42, alignment: .trailing)
            Slider(value: $pendingSeek, in: 0...seekUpperBound) { editing in
                if editing {
                    isSeeking = true
                } else {
                    let target = pendingSeek
                    Task {
                        await store.seek(to: target)
                        isSeeking = false
                        synchronizePendingSeek(nowPlaying.elapsed)
                    }
                }
            }
            .accessibilityLabel("再生位置")
            .accessibilityValue(formatPlaybackTime(pendingSeek))
            .accessibilityHint("左右キーで再生位置を変更します")
            Text(formatPlaybackTime(nowPlaying.duration))
                .frame(width: 42, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .disabled(seekDisabledReason != nil)
        .help(seekDisabledReason ?? "再生位置を変更")
    }

    private var nowPlaying: NowPlayingPresentation { queue.nowPlaying }

    private var isFavorite: Bool {
        guard let trackID = queue.nowPlayingTrack?.id else { return false }
        return listening.isFavorite(trackID)
    }

    private var favoriteButtonTitle: String {
        isFavorite ? "お気に入りから削除" : "お気に入りに追加"
    }

    private var favoriteButtonHelp: String {
        queue.nowPlayingTrack == nil
            ? "ライブラリに登録された再生中の曲だけお気に入りにできます"
            : favoriteButtonTitle
    }

    private var emptyTitle: String {
        nowPlaying.state == .unknown ? "再生状態を確認できません" : "再生する曲を選択"
    }

    private var emptySubtitle: String {
        if nowPlaying.state == .unknown { return "スピーカーとの通信を確認してください" }
        return store.selectedDevice == nil ? "先にスピーカーを選んでください" : "ライブラリから曲を選んでください"
    }

    private var trackSubtitle: String {
        if let artist = nowPlaying.artist { return artist }
        if nowPlaying.hasMedia {
            return nowPlaying.isQueueTrack ? "アーティスト情報なし" : "直接選択したファイル"
        }
        return emptySubtitle
    }

    private var playbackDisabledReason: String? {
        if store.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if store.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if !nowPlaying.hasMedia { return "先にライブラリから曲を選んでください" }
        if store.isBusy { return "スピーカーの応答を待っています" }
        return nil
    }

    private var synchronizationCheckHelp: String {
        if store.playbackState == .playing { return "再生中の曲を停止してから実行してください" }
        if store.isBusy { return "スピーカーの応答を待っています" }
        return "3連クリックが中央で一つに聞こえれば同期しています。二重打ちや左右への広がりは遅延ずれの目安です"
    }

    private var seekDisabledReason: String? {
        if !nowPlaying.hasMedia { return "再生中の曲がありません" }
        if !nowPlaying.duration.isFinite || nowPlaying.duration <= 0 { return "曲の長さを確認できないため移動できません" }
        if nowPlaying.state == .unknown { return "スピーカーとの通信状態を確認できないため移動できません" }
        if store.selectedDevice?.description?.avTransport == nil { return "選択した機器は再生位置の変更に対応していません" }
        if store.isBusy { return "スピーカーの応答を待っています" }
        return nil
    }

    private var seekUpperBound: Double {
        nowPlaying.duration.isFinite && nowPlaying.duration > 0 ? nowPlaying.duration : 1
    }

    private func synchronizePendingSeek(_ value: Double) {
        guard !isSeeking else { return }
        let finiteValue = value.isFinite ? value : 0
        pendingSeek = min(max(0, finiteValue), seekUpperBound)
    }

    private var stateLabel: String {
        switch nowPlaying.state {
        case .empty: "曲なし"
        case .loading: "読込中"
        case .stopped: "停止中"
        case .playing: "再生中"
        case .paused: "一時停止"
        case .unknown: "通信不明"
        }
    }

    private var stateIcon: String {
        switch nowPlaying.state {
        case .empty: "music.note"
        case .loading: "hourglass"
        case .stopped: "stop.fill"
        case .playing: "play.fill"
        case .paused: "pause.fill"
        case .unknown: "wifi.exclamationmark"
        }
    }
}

private func formatPlaybackTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

private struct StereoBalanceControl: View {
    @Bindable var store: RendererPlaybackStore
    let sliderWidth: CGFloat
    @State private var pendingBalance: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            Text("L").font(.caption2.bold()).foregroundStyle(.secondary)
            Slider(value: $pendingBalance, in: -1...1, step: 0.05) { editing in
                if !editing { Task { await store.setStereoBalance(pendingBalance) } }
            }
            .frame(width: sliderWidth)
            .accessibilityLabel("左右音量バランス")
            .accessibilityValue(balanceLabel)
            Text("R").font(.caption2.bold()).foregroundStyle(.secondary)
            Text("\(Int(store.stereoLeftVolume)) / \(Int(store.stereoRightVolume))")
                .font(.caption2.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
        .help("左音量 / 右音量。中央では同じ音量になります")
        .onAppear { pendingBalance = store.stereoBalance }
        .onChange(of: store.stereoBalance) { _, value in pendingBalance = value }
    }

    private var balanceLabel: String {
        let percent = Int((abs(pendingBalance) * 100).rounded())
        if percent == 0 { return "中央" }
        return pendingBalance < 0 ? "左へ\(percent)パーセント" : "右へ\(percent)パーセント"
    }
}

private struct DevicesView: View {
    @Bindable var store: RendererPlaybackStore
    @Bindable var recovery: RecoveryStore
    let showSongs: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: store.selectedDevice == nil ? "1.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(store.selectedDevice == nil ? Color.accentColor : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerTitle)
                        .font(.headline)
                    Text(headerSubtitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.selectedDevice?.supportsAVTransport == true {
                    Button("曲を選ぶ", systemImage: "music.note") { showSongs() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
            .background(.bar)
            Divider()
            if let pair = store.sonyStereoPair {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "hifispeaker.2.fill")
                            .font(.title2)
                            .foregroundStyle(store.isSonyStereoSelected ? Color.green : Color.accentColor)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sonyステレオ").font(.headline)
                            Text("LEFT  \(pair.left.friendlyName)（\(pair.left.modelName)）  •  RIGHT  \(pair.right.friendlyName)（\(pair.right.modelName)）")
                                .font(.caption).foregroundStyle(.secondary)
                            if store.isSonyStereoSelected {
                                Label(
                                    store.isStereoStreaming ? "LEFT／RIGHTの別ストリームを2台へ送信中" : "曲を左右に分離して2台へ送信します",
                                    systemImage: store.isStereoStreaming ? "waveform.badge.magnifyingglass" : "checkmark.seal.fill"
                                )
                                .font(.caption).foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        if store.isSonyStereoSelected {
                            Button("解除") { store.clearSonyStereo() }
                                .buttonStyle(.bordered)
                        } else {
                            Button("ステレオを選択") { store.selectSonyStereo() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if store.isSonyStereoSelected {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 16) {
                                Picker("出力品質", selection: Binding(
                                    get: { store.stereoOutputQuality },
                                    set: { store.setStereoOutputQuality($0) }
                                )) {
                                    ForEach(StereoOutputQuality.allCases) { quality in
                                        Text(quality.rawValue).tag(quality)
                                    }
                                }
                                .frame(width: 210)

                                Toggle("音源のL/Rを入れ替える", isOn: Binding(
                                    get: { store.stereoChannelsSwapped },
                                    set: { store.setStereoChannelsSwapped($0) }
                                ))
                                .toggleStyle(.switch)
                            }
                            HStack(spacing: 16) {
                                Picker("遅らせる側", selection: Binding(
                                    get: { store.stereoDelayedChannel },
                                    set: { store.setStereoDelayedChannel($0) }
                                )) {
                                    ForEach(StereoChannel.allCases) { channel in
                                        Text(channel.rawValue).tag(channel)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 190)

                                HStack(spacing: 6) {
                                    Text("基準遅延")
                                    TextField("0", value: Binding(
                                        get: { store.stereoDelayMilliseconds },
                                        set: { store.setStereoDelayMilliseconds($0) }
                                    ), format: .number.precision(.fractionLength(0)))
                                    .frame(width: 64)
                                    .multilineTextAlignment(.trailing)
                                    Text("ms").foregroundStyle(.secondary)
                                    Stepper("", value: Binding(
                                        get: { store.stereoDelayMilliseconds },
                                        set: { store.setStereoDelayMilliseconds($0) }
                                    ), in: 0...5_000, step: 1)
                                    .labelsHidden()
                                }
                            }
                        }
                        .disabled(store.playbackState == .playing || store.isBusy)
                        Text("\(store.stereoTimingDescription)。基準値から44.1kHz系は11/12、倍レートごとは基準値を加算します。両方の通信を事前に確立し、同じ曲の準備完了後に再生します。ハイレゾ維持は元sample rate／24-bit PCMです。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let rate = store.lastStereoSourceSampleRate,
                           let appliedDelay = store.lastStereoAppliedDelayMilliseconds {
                            Text("前回適用: \(rate / 1_000, format: .number.precision(.fractionLength(1)))kHz・\(appliedDelay, format: .number.precision(.fractionLength(0...1)))ms")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(store.isSonyStereoSelected ? Color.green.opacity(0.08) : Color.accentColor.opacity(0.06))
                Divider()
            }
            HSplitView {
                List(store.devices, selection: Binding(get: { store.selectedDeviceID }, set: { store.selectDevice($0) })) { device in
                    HStack(spacing: 12) {
                        Image(systemName: "hifispeaker.fill")
                            .font(.title2)
                            .foregroundStyle(device.id == store.selectedDeviceID ? Color.accentColor : Color.secondary)
                            .frame(width: 34, height: 34)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.friendlyName).font(.headline)
                            Text(device.modelName).font(.caption).foregroundStyle(.secondary)
                            Label(status(for: device).text, systemImage: status(for: device).icon)
                                .font(.caption).foregroundStyle(status(for: device).color)
                        }
                        Spacer()
                        if store.isSonyStereoSelected && device.id == store.selectedDeviceID {
                            Text("LEFT").font(.caption2.bold()).foregroundStyle(.green)
                        } else if store.isSonyStereoSelected && device.id == store.stereoRightDeviceID {
                            Text("RIGHT").font(.caption2.bold()).foregroundStyle(.green)
                        }
                        if device.id == store.selectedDeviceID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("選択中のスピーカー")
                        }
                    }
                    .tag(device.id).padding(.vertical, 6)
                }
                .frame(minWidth: 210, idealWidth: 300)
                ScrollView {
                    if let device = store.selectedDevice {
                        SpeakerDetailView(device: device, status: status(for: device), lastDiscoveryAt: store.lastDiscoveryAt, showSongs: showSongs)
                            .padding(28)
                    }
                    else { ContentUnavailableView("スピーカーを選択", systemImage: "hifispeaker", description: Text("左の一覧から再生先を選んでください。")) }
                }
                .frame(minWidth: 240, idealWidth: 420)
            }
        }
        .navigationTitle("スピーカー")
        .toolbar {
            Button(store.isDiscovering ? "検索中…" : "再検索", systemImage: "arrow.clockwise") { Task { await store.discoverRenderers() } }
                .disabled(store.isDiscovering)
                .help("同じネットワーク上のスピーカーをもう一度探します")
        }
        .overlay {
            if store.isDiscovering && store.devices.isEmpty {
                ProgressView("スピーカーを検索中…")
            } else if !store.isDiscovering && store.devices.isEmpty {
                ContentUnavailableView("スピーカーが見つかりません", systemImage: "hifispeaker.slash", description: Text("スピーカーとMacが同じネットワークに接続されていることを確認して、再検索してください。"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let lastDiscoveryAt = store.lastDiscoveryAt {
                HStack {
                    Text("最終検索: \(lastDiscoveryAt.formatted(date: .omitted, time: .shortened))")
                    Spacer()
                    Text("\(store.devices.count)台")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
            }
        }
    }

    private var headerTitle: String {
        if store.isSonyStereoSelected { return "Sonyステレオを再生先に選択中" }
        if let device = store.selectedDevice { return "\(device.friendlyName)を再生先に選択中" }
        return "最初に再生先のスピーカーを選択"
    }

    private var headerSubtitle: String {
        if store.isSonyStereoSelected { return "LEFT／RIGHT割り当てを確認して、ライブラリから曲を選びます。" }
        return store.selectedDevice == nil ? "一覧から1台選ぶと、次に曲を選べます。" : "次はライブラリから曲を選びます。"
    }

    private func status(for device: RendererDevice) -> SpeakerConnectionStatus {
        guard device.descriptionError == nil else {
            return SpeakerConnectionStatus(text: "機器情報を取得できません", icon: "exclamationmark.triangle.fill", color: .orange)
        }
        guard device.supportsAVTransport else {
            return SpeakerConnectionStatus(text: "再生操作に非対応", icon: "xmark.circle", color: .orange)
        }
        guard device.id == store.selectedDeviceID || device.id == store.stereoRightDeviceID else {
            return SpeakerConnectionStatus(text: "再生先に選択できます", icon: "checkmark.circle", color: .secondary)
        }
        switch recovery.state {
        case .connected:
            if store.playbackState == .unknown {
                return SpeakerConnectionStatus(text: "応答を確認できません", icon: "wifi.exclamationmark", color: .orange)
            }
            return SpeakerConnectionStatus(text: "再生先として接続中", icon: "checkmark.circle.fill", color: .green)
        case .sleeping:
            return SpeakerConnectionStatus(text: "スリープ中", icon: "moon.zzz.fill", color: .secondary)
        case .waitingForNetwork:
            return SpeakerConnectionStatus(text: "ネットワーク待機中", icon: "wifi.slash", color: .orange)
        case .reconnecting:
            return SpeakerConnectionStatus(text: "再接続中", icon: "arrow.triangle.2.circlepath", color: .orange)
        case .readyToResume:
            return SpeakerConnectionStatus(text: "再接続済み", icon: "checkmark.circle.fill", color: .green)
        case .disconnected:
            return SpeakerConnectionStatus(text: "接続できません", icon: "wifi.exclamationmark", color: .red)
        }
    }
}

private struct SpeakerConnectionStatus {
    let text: String
    let icon: String
    let color: Color
}

private struct SpeakerDetailView: View {
    let device: RendererDevice
    let status: SpeakerConnectionStatus
    let lastDiscoveryAt: Date?
    let showSongs: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 12) {
                Image(systemName: "hifispeaker.2.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .frame(width: 104, height: 104)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(device.friendlyName).font(.title.bold())
                Text(device.modelName).font(.title3).foregroundStyle(.secondary)
                Label(status.text, systemImage: status.icon).foregroundStyle(status.color)
                if device.supportsAVTransport {
                    Button("このスピーカーで曲を選ぶ", systemImage: "music.note") { showSongs() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)

            GroupBox("接続情報") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("検出したアドレス", value: device.discovery.sourceAddress)
                    LabeledContent("最終検索", value: lastDiscoveryAt?.formatted(date: .abbreviated, time: .shortened) ?? "未実行")
                    if device.description?.manufacturer.localizedCaseInsensitiveContains("sony") == true {
                        LabeledContent("Wireless Stereo構成", value: "UPnP情報からは確認できません")
                        Text("左右の役割は推測せず、検出された再生先として表示しています。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup {
                DeviceDiagnosticsView(device: device)
                    .font(.body)
                    .padding(.top, 12)
            } label: {
                Text("技術情報").font(.headline)
            }
        }
    }
}

private struct DeviceDiagnosticsView: View {
    let device: RendererDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            diagnostic("Friendly Name", device.description?.friendlyName)
            diagnostic("Manufacturer", device.description?.manufacturer)
            diagnostic("Model", [device.description?.modelName, device.description?.modelNumber].compactMap { $0 }.joined(separator: " "))
            diagnostic("UDN", device.description?.udn)
            diagnostic("IP Address", device.discovery.sourceAddress)
            diagnostic("LOCATION", device.discovery.location.absoluteString)
            diagnostic("Presentation URL", device.description?.presentationURL?.absoluteString)
            if let error = device.descriptionError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            Text("Services").font(.headline)
            ForEach(Array((device.description?.services ?? []).enumerated()), id: \.offset) { _, service in
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.serviceType).font(.subheadline.bold())
                    Text("control: \(service.controlURL.absoluteString)")
                    Text("event: \(service.eventSubscriptionURL?.absoluteString ?? "—")")
                    Text("SCPD: \(service.descriptionURL?.absoluteString ?? "—")")
                }
                .font(.caption.monospaced()).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func diagnostic(_ name: String, _ value: String?) -> some View {
        LabeledContent(name, value: value?.isEmpty == false ? value! : "—").textSelection(.enabled)
    }
}

private struct PlaybackView: View {
    @Bindable var store: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore
    @State private var pendingSeek: Double = 0
    @State private var pendingVolume: Double = 0
    @State private var diagnosticExportMessage: String?
    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack(alignment: .center, spacing: 28) {
                    artwork
                    VStack(alignment: .leading, spacing: 9) {
                        Text(stateLabel.uppercased())
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(nowPlaying.title ?? "再生中の曲はありません")
                            .font(.system(size: 30, weight: .bold))
                            .lineLimit(2)
                        Text(nowPlaying.artist ?? mediaSubtitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let album = nowPlaying.album {
                            Text(album).font(.subheadline).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        HStack(spacing: 10) {
                            Image(systemName: store.isSonyStereoSelected ? "hifispeaker.2.fill" : "hifispeaker.fill")
                            Text(store.selectedOutputName)
                            Button("変更") { store.destination = .devices }.buttonStyle(.link)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Slider(value: $pendingSeek, in: 0...max(1, nowPlaying.duration)) { editing in
                        if !editing { Task { await store.seek(to: pendingSeek) } }
                    }
                        .accessibilityLabel("再生位置")
                        .accessibilityValue(time(pendingSeek))
                        .accessibilityHint("左右キーで再生位置を変更します")
                        .disabled(!nowPlaying.hasMedia || nowPlaying.duration <= 0 || nowPlaying.state == .unknown || store.isBusy)
                    HStack {
                        Text(time(nowPlaying.elapsed))
                        Spacer()
                        Text(time(nowPlaying.duration))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    QueueModeControls(queue: queue)
                    Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
                        .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                    Button(nowPlaying.state == .playing ? "一時停止" : "再生", systemImage: nowPlaying.state == .playing ? "pause.fill" : "play.fill") {
                        Task { await queue.togglePlayback() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(playbackControlsDisabled)
                    .help(playbackControlsHelp)
                    Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
                        .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                    Button("停止", systemImage: "stop.fill") { Task { await queue.stop() } }
                        .disabled(!nowPlaying.hasMedia || store.isBusy)
                }
                .labelStyle(.iconOnly)

                GroupBox {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.wave.2")
                            Slider(value: $pendingVolume, in: 0...100, step: 1) { editing in
                                if !editing { Task { await store.setVolume(pendingVolume) } }
                            }
                            .accessibilityLabel("スピーカー音量")
                            .accessibilityValue("\(Int(pendingVolume))パーセント")
                            Text("\(Int(pendingVolume))%")
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                        }
                        if store.isSonyStereoSelected {
                            StereoBalanceControl(store: store, sliderWidth: 260)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .disabled(store.selectedDevice?.description?.renderingControl == nil)
                } label: {
                    Text(store.isSonyStereoSelected ? "音量と左右バランス" : "音量")
                }

                DisclosureGroup("接続と診断") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("スピーカー", value: store.selectedOutputName)
                        LabeledContent("再生状態", value: stateLabel)
                        LabeledContent("ファイル形式", value: store.media.map { "\($0.fileExtension) · \($0.mimeType)" } ?? "—")
                        Button("Macの音源ファイルを開く…", systemImage: "folder") { store.chooseFile() }
                        if let error = store.lastError {
                            Divider()
                            Text("最後の通信エラー").font(.headline)
                            Text(error.details).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Button("診断ログを書き出す…", systemImage: "doc.badge.arrow.up") { exportDiagnostics() }
                        if let diagnosticExportMessage { Text(diagnosticExportMessage).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("再生中")
        .toolbar { Button("状態を更新", systemImage: "arrow.clockwise") { Task { await store.refreshState() } } }
        .onAppear { pendingSeek = nowPlaying.elapsed; pendingVolume = store.volume }
        .onChange(of: nowPlaying.elapsed) { _, value in pendingSeek = value }
        .onChange(of: store.volume) { _, value in pendingVolume = value }
    }

    @ViewBuilder private var artwork: some View {
        if let track = queue.nowPlayingTrack {
            CachedArtwork(track: track, library: library, size: 210)
                .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
                .frame(width: 210, height: 210)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Artworkなし")
        }
    }

    private var nowPlaying: NowPlayingPresentation { queue.nowPlaying }

    private var mediaSubtitle: String {
        if nowPlaying.hasMedia { return nowPlaying.isQueueTrack ? "アーティスト情報なし" : "直接選択したファイル" }
        return "ライブラリから曲を選んでください"
    }

    private var stateLabel: String {
        switch nowPlaying.state {
        case .empty: "曲なし"
        case .loading: "読み込み中"
        case .stopped: "停止中"
        case .playing: "再生中"
        case .paused: "一時停止"
        case .unknown: "通信状態不明"
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", total / 60, total % 60)
    }
    private var playbackControlsDisabled: Bool {
        !nowPlaying.hasMedia || store.selectedDevice?.supportsAVTransport != true || store.isBusy
    }
    private var playbackControlsHelp: String {
        if store.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if store.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if store.media == nil { return "先に音源ファイルまたはライブラリの曲を選んでください" }
        if store.isBusy { return "スピーカーの応答を待っています" }
        return "再生または一時停止"
    }
    private func exportDiagnostics() {
        do {
            let exported = try DiagnosticExportService().export(store.diagnosticReportData())
            if exported { diagnosticExportMessage = "個人情報・ファイルの場所・機器IPを含まない診断ログを書き出しました。" }
        } catch { diagnosticExportMessage = "診断ログを書き出せませんでした。" }
    }
}
