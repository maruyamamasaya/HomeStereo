#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct PlaylistsView: View {
    @Bindable var store: PlaylistStore
    @State private var newName = ""
    @State private var renameValue = ""
    @State private var confirmsPlaylistDelete = false
    @State private var confirmsItemDelete = false

    var body: some View {
        HSplitView {
            VStack {
                List(store.playlists, selection: $store.selectedPlaylistIDs) { playlist in
                    VStack(alignment: .leading) {
                        Text(playlist.name)
                        Text("\(playlist.items.count)曲").font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(playlist.id)
                    .dropDestination(for: String.self) { values, _ in
                        let ids = values.flatMap(TrackDragPayload.decode)
                        guard !ids.isEmpty else { return false }
                        Task { await store.add(trackIDs: ids, to: playlist.id) }
                        return true
                    }
                    .contextMenu {
                        Button("先頭から再生") { Task { await store.play(playlist, shuffled: false) } }
                        Button("Queueの最後に追加") { Task { await store.appendToQueue(trackIDs: playlist.items.map(\.trackID)) } }
                        Button("Playlistを削除", role: .destructive) {
                            store.selectedPlaylistIDs = [playlist.id]
                            confirmsPlaylistDelete = true
                        }
                    }
                }
                .onChange(of: store.selectedPlaylistIDs) { _, value in
                    if let active = store.selectedPlaylistID, value.contains(active) { return }
                    store.selectedPlaylistID = value.first
                }
                HStack {
                    TextField("新しいPlaylist", text: $newName)
                    Button("作成", systemImage: "plus") {
                        let name = newName; newName = ""; Task { await store.create(name: name) }
                    }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(8)
            }.frame(minWidth: 160, idealWidth: 240)

            if let playlist = store.selectedPlaylist {
                VStack(spacing: 0) {
                    HStack {
                        TextField("Playlist名", text: $renameValue)
                            .onSubmit { Task { await store.rename(id: playlist.id, name: renameValue) } }
                        Button("名称変更") { Task { await store.rename(id: playlist.id, name: renameValue) } }
                        Button("先頭から再生", systemImage: "play.fill") { Task { await store.play(playlist, shuffled: false) } }
                        Button("Shuffle再生", systemImage: "shuffle") { Task { await store.play(playlist, shuffled: true) } }
                    }.padding()
                    List(selection: $store.selectedItemIDs) {
                        ForEach(playlist.items) { item in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                if let track = store.track(for: item) {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if track.scanState == .missing { Label("missing", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                                } else { Label("未解決の曲", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                            }
                            .tag(item.id)
                            .draggable(TrackDragPayload.encode([item.trackID]))
                            .contextMenu {
                                Button("今すぐ再生") { Task { await store.playNow(trackIDs: [item.trackID], startingAt: item.trackID) } }
                                Button("次に再生") { Task { await store.playNext(trackIDs: [item.trackID]) } }
                                Button("Queueの最後に追加") { Task { await store.appendToQueue(trackIDs: [item.trackID]) } }
                                Button("Playlistから削除", role: .destructive) {
                                    store.selectedItemIDs = [item.id]
                                    confirmsItemDelete = true
                                }
                            }
                        }
                        .onMove { source, destination in Task { await store.move(fromOffsets: source, toOffset: destination, in: playlist.id) } }
                    }
                    .onDeleteCommand { if !store.selectedItemIDs.isEmpty { confirmsItemDelete = true } }
                    .dropDestination(for: String.self) { values, _ in
                        let ids = values.flatMap(TrackDragPayload.decode)
                        guard !ids.isEmpty else { return false }
                        Task { await store.add(trackIDs: ids, to: playlist.id) }
                        return true
                    }
                    HStack {
                        Button("選択を削除", role: .destructive) { confirmsItemDelete = true }
                            .disabled(store.selectedItemIDs.isEmpty)
                        Button("現在のQueueを追加") { Task { await store.addCurrentQueue(to: playlist.id) } }
                        Button("M3U8 Export") { Task { await store.exportM3U8(playlist) } }
                        Spacer()
                        Button("Playlistを削除", role: .destructive) {
                            if store.selectedPlaylistIDs.isEmpty { store.selectedPlaylistIDs = [playlist.id] }
                            confirmsPlaylistDelete = true
                        }
                    }.padding()
                }
                .onAppear { renameValue = playlist.name }
                .onChange(of: playlist.id) { _, _ in renameValue = playlist.name }
            } else {
                ContentUnavailableView("Playlistを選択", systemImage: "music.note.list")
            }
        }
        .navigationTitle("Playlist")
        .toolbar { Button("M3U8 Import", systemImage: "square.and.arrow.down") { Task { await store.importM3U8() } } }
        .alert("Playlist", isPresented: Binding(
            get: { store.message != nil || store.lastImportResult != nil }, set: { if !$0 { store.dismissMessage() } }
        )) {
            Button("OK") { store.dismissMessage() }
        } message: {
            if let result = store.lastImportResult {
                Text("Import \(result.imported)曲、未解決 \(result.unresolved.count)件、曖昧 \(result.ambiguous.count)件")
            } else { Text(store.message ?? "") }
        }
        .confirmationDialog("選択したPlaylistを削除しますか？", isPresented: $confirmsPlaylistDelete) {
            Button("Playlistを削除", role: .destructive) { Task { await store.deleteSelectedPlaylists() } }
        } message: { Text("音源ファイルは削除されません。") }
        .confirmationDialog("選択した曲をPlaylistから削除しますか？", isPresented: $confirmsItemDelete) {
            if let playlist = store.selectedPlaylist {
                Button("Playlistから削除", role: .destructive) { Task { await store.removeSelected(from: playlist.id) } }
            }
        } message: { Text("音源ファイルは削除されません。") }
    }
}
