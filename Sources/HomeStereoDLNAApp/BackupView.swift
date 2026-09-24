#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
import SwiftUI

struct BackupView: View {
    @Bindable var store: BackupStore
    var body: some View {
        Form {
            Section("JSON Backup") {
                Text("Playlist、Favorite、再生履歴、設定をversioned JSONへ保存します。音源、Library index、絶対path、bookmark、機器IPは含みません。")
                HStack {
                    Button("Export…", systemImage: "square.and.arrow.up") { Task { await store.export() } }
                    Button("Importを確認…", systemImage: "square.and.arrow.down") { Task { await store.previewImport() } }
                }
            }
            if let preview = store.pendingPreview {
                Section("Import preview") {
                    LabeledContent("Playlist", value: "追加 \(preview.addedPlaylists)／更新 \(preview.updatedPlaylists)")
                    LabeledContent("Favorite追加", value: String(preview.addedFavorites))
                    LabeledContent("再生イベント追加", value: String(preview.addedEvents))
                    LabeledContent("未解決Track", value: String(preview.unresolvedTracks))
                    LabeledContent("曖昧Track", value: String(preview.ambiguousTracks))
                    Text("既存データは削除しません。曖昧候補へ自動接続しません。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Importを適用") { Task { await store.applyImport() } }
                        Button("キャンセル", role: .cancel) { store.cancelImport() }
                    }
                }
            }
        }
        .formStyle(.grouped).navigationTitle("Backup")
        .alert("Backup", isPresented: Binding(
            get: { store.message != nil || store.lastImportResult != nil }, set: { if !$0 { store.dismissMessage() } }
        )) {
            Button("OK") { store.dismissMessage() }
        } message: {
            if let result = store.lastImportResult {
                Text("Import完了: Playlist追加 \(result.addedPlaylists)、更新 \(result.updatedPlaylists)、未解決 \(result.unresolvedTracks)、曖昧 \(result.ambiguousTracks)")
            } else { Text(store.message ?? "") }
        }
    }
}
