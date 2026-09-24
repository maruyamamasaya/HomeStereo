#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct ContentView: View {
    @Bindable var store: PlaybackStore

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                List(selection: $store.destination) {
                    Label("曲", systemImage: "music.note.list")
                        .tag(SidebarDestination.songs)
                    Label("設定", systemImage: "gearshape")
                        .tag(SidebarDestination.settings)
                }
                .navigationTitle("HomeStereo")
                .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            } detail: {
                switch store.destination {
                case .songs:
                    SongsView(store: store)
                case .settings:
                    SettingsView(store: store)
                }
            }

            Divider()
            PlayerBar(store: store)
        }
        .alert("HomeStereo", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.dismissMessage() } }
        )) {
            Button("OK") { store.dismissMessage() }
        } message: {
            Text(store.message ?? "")
        }
    }
}

private struct SongsView: View {
    @Bindable var store: PlaybackStore

    var body: some View {
        Group {
            if store.folderURL == nil {
                ContentUnavailableView {
                    Label("音楽フォルダを選択", systemImage: "folder.badge.plus")
                } description: {
                    Text("Mac上の音源を読み取り専用で表示します。")
                } actions: {
                    Button("フォルダを選択…") { Task { await store.chooseFolder() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Table(store.tracks, selection: $store.selectedTrackID) {
                    TableColumn("曲名") { track in
                        HStack(spacing: 10) {
                            ArtworkView(data: track.artworkData, size: 34, cornerRadius: 5)
                            Text(track.title)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 210, ideal: 300)
                    TableColumn("アーティスト") { Text($0.artist ?? "—") }
                    TableColumn("アルバム") { Text($0.album ?? "—") }
                    TableColumn("時間") { Text(formatTime($0.duration)) }
                        .width(70)
                }
                .onChange(of: store.selectedTrackID) { _, id in store.selectTrack(id: id) }
            }
        }
        .navigationTitle(store.folderURL?.lastPathComponent ?? "曲")
        .toolbar {
            Button("フォルダを選択", systemImage: "folder") {
                Task { await store.chooseFolder() }
            }
            .help("音楽フォルダを選択（⌘O）")
        }
    }
}

private struct SettingsView: View {
    let store: PlaybackStore

    var body: some View {
        Form {
            LabeledContent("音楽フォルダ", value: store.folderURL?.path ?? "未選択")
            LabeledContent("対応候補", value: "m4a, mp3, aac, wav, aiff, flac")
            Text("出力先はプレイヤーバーのAirPlayボタンからApple標準UIで選択します。転送形式やサンプルレートはmacOSと受信機に依存します。")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .navigationTitle("設定")
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
