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
    @SceneStorage("main.sidebar.visibility") private var sidebarVisibility = "all"
    @AppStorage("main.queueInspector.visible.compactV1") private var queueInspectorVisible = false
    var body: some View {
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
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("HomeStereo")
            .navigationSplitViewColumnWidth(min: 165, ideal: 185)
        } detail: {
            switch store.destination {
            case .devices: DevicesView(store: store) { store.destination = .songs }
            case .songs: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .songs)
            case .albums: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .albums)
            case .artists: LibraryView(playback: store, library: library, queue: queue, playlists: playlists, listening: listening, mode: .artists)
            case .folders: LibraryFoldersView(library: library)
            case .queue: QueueView(playback: store, queue: queue)
            case .playlists: PlaylistsView(store: playlists)
            case .favorites: ListeningView(store: listening, queue: queue, mode: .favorites)
            case .history: ListeningView(store: listening, queue: queue, mode: .history)
            case .backup: BackupView(store: backup)
            case .playback: PlaybackView(store: store, queue: queue)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                MainNowPlayingBar(store: store, library: library, queue: queue)
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
        }
        .inspector(isPresented: $queueInspectorVisible) {
            QueueView(playback: store, queue: queue)
                .inspectorColumnWidth(min: 260, ideal: 340, max: 480)
        }
        .toolbar {
            Button(queueInspectorVisible ? "Queueを閉じる" : "Queueを開く", systemImage: "sidebar.trailing") {
                queueInspectorVisible.toggle()
            }
            .accessibilityHint("再生QueueのInspectorを切り替えます")
        }
        .alert("再生を再開しますか？", isPresented: Binding(
            get: { recovery.shouldAskToResume }, set: { if !$0 { recovery.declineResume() } }
        )) {
            Button("再開") { Task { await recovery.resume() } }
            Button("今はしない", role: .cancel) { recovery.declineResume() }
        } message: { Text("sleepまたは通信切断前に再生中だった曲を、現在のQueue位置から再開します。音量は変更しません。") }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var recoveryStatus: String {
        switch recovery.state {
        case .connected: "接続済み"
        case .sleeping: "sleep前の状態を保存しました"
        case .waitingForNetwork: "ネットワークの復帰を待っています"
        case let .reconnecting(attempt): "SRS-HG1を再検索中（\(attempt)回目）"
        case .readyToResume: "SRS-HG1へ再接続しました"
        case let .disconnected(message): message
        }
    }
}

private struct MainNowPlayingBar: View {
    @Bindable var store: RendererPlaybackStore
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore

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
    }

    private var regularLayout: some View {
        HStack(spacing: 18) {
            trackSummary
            .frame(maxWidth: .infinity, alignment: .leading)

            playbackControls

            playbackStatus
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                trackSummary
                Spacer(minLength: 8)
                playbackStatus
            }
            HStack {
                Spacer()
                playbackControls
                Spacer()
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
                Text(nowPlaying.artist ?? emptySubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button("前の曲", systemImage: "backward.fill") { Task { await queue.previous() } }
                .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                .help(nowPlaying.isQueueTrack ? "Queueの前の曲へ移動" : "直接選択したファイルでは前の曲へ移動できません")
            Button(nowPlaying.state == .playing ? "一時停止" : "再生", systemImage: nowPlaying.state == .playing ? "pause.fill" : "play.fill") {
                Task { await queue.togglePlayback() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(playbackDisabledReason != nil)
            .help(playbackDisabledReason ?? (nowPlaying.state == .playing ? "再生を一時停止" : "選択した曲を再生"))
            Button("次の曲", systemImage: "forward.fill") { Task { await queue.next() } }
                .disabled(!nowPlaying.isQueueTrack || store.isBusy)
                .help(nowPlaying.isQueueTrack ? "Queueの次の曲へ移動" : "直接選択したファイルでは次の曲へ移動できません")
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    private var playbackStatus: some View {
        VStack(alignment: .trailing, spacing: 3) {
            rendererMenu
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
                Text(store.isDiscovering ? "Rendererを検索中…" : "Rendererが見つかりません")
            } else {
                ForEach(store.devices) { device in
                    Button {
                        store.selectDevice(device.id)
                    } label: {
                        if device.id == store.selectedDeviceID {
                            Label(device.friendlyName, systemImage: "checkmark")
                        } else {
                            Text(device.friendlyName)
                        }
                    }
                }
            }
            Divider()
            Button("Rendererを再検索", systemImage: "arrow.clockwise") {
                Task { await store.discoverRenderers() }
            }
            .disabled(store.isDiscovering)
        } label: {
            Label(store.selectedDevice?.friendlyName ?? "Rendererを選択", systemImage: "hifispeaker")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .help("再生先のDLNA Rendererを選択")
        .accessibilityLabel("出力先Renderer")
        .accessibilityValue(store.selectedDevice?.friendlyName ?? "未選択")
    }

    private var nowPlaying: NowPlayingPresentation { queue.nowPlaying }

    private var emptyTitle: String {
        nowPlaying.state == .unknown ? "再生状態を確認できません" : "再生する曲を選択"
    }

    private var emptySubtitle: String {
        if nowPlaying.state == .unknown { return "Rendererとの通信を確認してください" }
        return store.selectedDevice == nil ? "先にスピーカーを選んでください" : "ライブラリから曲を選んでください"
    }

    private var playbackDisabledReason: String? {
        if store.selectedDevice == nil { return "先に再生先のスピーカーを選んでください" }
        if store.selectedDevice?.supportsAVTransport != true { return "選択した機器は再生操作に対応していません" }
        if !nowPlaying.hasMedia { return "先にライブラリから曲を選んでください" }
        if store.isBusy { return "Rendererの応答を待っています" }
        return nil
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

private struct DevicesView: View {
    @Bindable var store: RendererPlaybackStore
    let showSongs: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: store.selectedDevice == nil ? "1.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(store.selectedDevice == nil ? Color.accentColor : Color.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedDevice == nil ? "最初に再生先のスピーカーを選択" : "\(store.selectedDevice?.friendlyName ?? "スピーカー")を再生先に選択中")
                        .font(.headline)
                    Text(store.selectedDevice == nil ? "一覧から1台選ぶと、次に曲を選べます。" : "次はライブラリから曲を選びます。")
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
            HSplitView {
                List(store.devices, selection: Binding(get: { store.selectedDeviceID }, set: { store.selectDevice($0) })) { device in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.friendlyName).font(.headline)
                        Text("\(device.modelName) · \(device.discovery.sourceAddress)").font(.caption).foregroundStyle(.secondary)
                        Label(device.supportsAVTransport ? "再生可能" : "再生操作に非対応", systemImage: device.supportsAVTransport ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.caption).foregroundStyle(device.supportsAVTransport ? .green : .orange)
                    }
                    .tag(device.id).padding(.vertical, 3)
                }
                .frame(minWidth: 180, idealWidth: 280)
                ScrollView {
                    if let device = store.selectedDevice { DeviceDiagnosticsView(device: device).padding() }
                    else { ContentUnavailableView("スピーカーを選択", systemImage: "hifispeaker", description: Text("左の一覧から再生先を選んでください。")) }
                }
                .frame(minWidth: 240, idealWidth: 420)
            }
        }
        .navigationTitle("DLNA Renderer")
        .toolbar {
            Button(store.isDiscovering ? "検索中…" : "再検索", systemImage: "arrow.clockwise") { Task { await store.discoverRenderers() } }
                .disabled(store.isDiscovering)
        }
        .overlay { if store.isDiscovering && store.devices.isEmpty { ProgressView("Rendererを検索中…") } }
    }
}

private struct DeviceDiagnosticsView: View {
    let device: RendererDevice
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Device Description").font(.title2.bold())
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
    @State private var pendingSeek: Double = 0
    @State private var pendingVolume: Double = 0
    @State private var diagnosticExportMessage: String?
    var body: some View {
        Form {
            Section("出力先") {
                LabeledContent("Renderer", value: store.selectedDevice?.friendlyName ?? "未選択")
                LabeledContent("AVTransport", value: store.selectedDevice?.supportsAVTransport == true ? "利用可能" : "利用不可")
            }
            Section("音源") {
                Button("ファイルを選択…") { store.chooseFile() }
                LabeledContent("曲名", value: store.media?.title ?? "未選択")
                LabeledContent("形式", value: store.media.map { "\($0.fileExtension) · \($0.mimeType)" } ?? "—")
            }
            Section("再生") {
                HStack {
                    Button("再生", systemImage: "play.fill") { Task { await store.play() } }
                    Button("一時停止", systemImage: "pause.fill") { Task { await store.pause() } }
                    Button("停止", systemImage: "stop.fill") { Task { await queue.stop() } }
                }
                .disabled(store.isBusy || store.selectedDevice?.supportsAVTransport != true || store.media == nil)
                LabeledContent("Transport状態", value: store.playbackState.rawValue)
                HStack {
                    Text(time(store.elapsed)).monospacedDigit()
                    Slider(value: $pendingSeek, in: 0...max(1, store.duration)) { editing in if !editing { Task { await store.seek(to: pendingSeek) } } }
                        .accessibilityLabel("再生位置")
                        .accessibilityValue(time(pendingSeek))
                        .accessibilityHint("左右キーで再生位置を変更します")
                    Text(time(store.duration)).monospacedDigit()
                }
                .onChange(of: store.elapsed) { _, value in pendingSeek = value }
            }
            Section("音量") {
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Slider(value: $pendingVolume, in: 0...100, step: 1) { editing in if !editing { Task { await store.setVolume(pendingVolume) } } }
                        .accessibilityLabel("Renderer音量")
                        .accessibilityValue("\(Int(pendingVolume))パーセント")
                    Text("\(Int(pendingVolume))").monospacedDigit()
                }
                .disabled(store.selectedDevice?.description?.renderingControl == nil)
                .onChange(of: store.volume) { _, value in pendingVolume = value }
            }
            Section("最後のエラー") {
                if let error = store.lastError {
                    LabeledContent("Action", value: error.action)
                    if let status = error.httpStatus { LabeledContent("HTTP", value: String(status)) }
                    if let code = error.upnpErrorCode { LabeledContent("UPnP code", value: String(code)) }
                    Text(error.details).foregroundStyle(.red).textSelection(.enabled)
                } else { Text("なし").foregroundStyle(.secondary) }
                Button("診断ログを書き出す…", systemImage: "doc.badge.arrow.up") {
                    do {
                        let exported = try DiagnosticExportService().export(store.diagnosticReportData())
                        if exported { diagnosticExportMessage = "個人情報・絶対path・機器IPを含まない診断ログを書き出しました。" }
                    } catch { diagnosticExportMessage = "診断ログを書き出せませんでした。" }
                }
                if let diagnosticExportMessage { Text(diagnosticExportMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped).navigationTitle("再生")
        .toolbar { Button("状態を更新", systemImage: "arrow.clockwise") { Task { await store.refreshState() } } }
    }
    private func time(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded())); return String(format: "%d:%02d", total / 60, total % 60)
    }
}
