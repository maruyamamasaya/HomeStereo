#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
import SwiftUI

struct BackupView: View {
    @Bindable var store: BackupStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let message = store.message {
                    resultBanner(
                        title: store.messageIsError ? "バックアップ操作を完了できませんでした" : "バックアップを書き出しました",
                        message: message,
                        icon: store.messageIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        color: store.messageIsError ? .orange : .green
                    )
                } else if let result = store.lastImportResult {
                    resultBanner(
                        title: "復元が完了しました",
                        message: "プレイリスト追加 \(result.addedPlaylists)件、更新 \(result.updatedPlaylists)件。未解決 \(result.unresolvedTracks)件、候補が複数ある曲 \(result.ambiguousTracks)件。",
                        icon: "checkmark.circle.fill", color: .green
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    informationCard(
                        title: "保存されるもの", icon: "checkmark.circle.fill", color: .green,
                        items: ["プレイリスト", "お気に入り", "再生履歴", "フォルダの自動更新設定"]
                    )
                    informationCard(
                        title: "保存されないもの", icon: "minus.circle.fill", color: .secondary,
                        items: ["音源ファイル", "フォルダの場所とアクセス権", "スピーカーのIPアドレス", "ライブラリの索引"]
                    )
                }

                GroupBox("使い方") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("1. 「バックアップを書き出す」で設定とコレクションをファイルに保存します。", systemImage: "1.circle.fill")
                        Label("2. 復元時は内容を確認してから適用します。既存データは削除されません。", systemImage: "2.circle.fill")
                        Label("3. 音楽フォルダは別途追加してください。曲は安全に照合されます。", systemImage: "3.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

            if let preview = store.pendingPreview {
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        Label("復元する内容を確認", systemImage: "doc.text.magnifyingglass")
                            .font(.title3.bold())
                        HStack(spacing: 24) {
                            previewValue("プレイリスト", "追加 \(preview.addedPlaylists)・更新 \(preview.updatedPlaylists)")
                            previewValue("お気に入り", "追加 \(preview.addedFavorites)")
                            previewValue("再生履歴", "追加 \(preview.addedEvents)")
                        }
                        Divider()
                        HStack(spacing: 20) {
                            Label("見つからない曲 \(preview.unresolvedTracks)件", systemImage: preview.unresolvedTracks == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                            Label("候補が複数ある曲 \(preview.ambiguousTracks)件", systemImage: preview.ambiguousTracks == 0 ? "checkmark.circle" : "exclamationmark.triangle")
                        }
                        .font(.subheadline)
                        Text("見つからない曲や候補が複数ある曲は、別の曲へ勝手に接続しません。既存データも削除しません。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("この内容を復元", systemImage: "arrow.down.doc.fill") { Task { await store.applyImport() } }
                                .buttonStyle(.borderedProminent)
                            Button("キャンセル", role: .cancel) { store.cancelImport() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            }
            .padding(24)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("バックアップ")
        .toolbar {
            Button("バックアップを書き出す", systemImage: "square.and.arrow.up") { Task { await store.export() } }
            Button("バックアップから復元", systemImage: "square.and.arrow.down") { Task { await store.previewImport() } }
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "externaldrive.fill.badge.timemachine")
                .font(.system(size: 42)).foregroundStyle(.tint)
                .frame(width: 76, height: 76).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("コレクションを安全に保存").font(.title.bold())
                Text("プレイリストやお気に入りを、移行しやすいバックアップファイルにまとめます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func informationCard(title: String, icon: String, color: Color, items: [String]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(color)
                ForEach(items, id: \.self) { item in
                    Text(item).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func previewValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resultBanner(title: String, message: String, icon: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("閉じる") { store.dismissMessage() }.buttonStyle(.borderless)
        }
        .padding(12).background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}
