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
                        title: store.messageIsError ? "バックアップ操作を完了できませんでした" : "バックアップ操作",
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
                        items: ["プレイリスト・曲順・タグ", "お気に入り・Good／Bad", "詳細再生履歴・集計", "曲ID対応・特徴量・音量解析", "ライブラリ登録・Import原本・選定設定"]
                    )
                    informationCard(
                        title: "保存されないもの", icon: "minus.circle.fill", color: .secondary,
                        items: ["音源ファイル", "Analyzerのモデル・cache", "別のMacでのアクセス権の保証", "すべての画面・スピーカー設定"]
                    )
                }

                GroupBox("使い方") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("1. 「バックアップを書き出す」で現在の保存状態をファイルに保存します。", systemImage: "1.circle.fill")
                        Label("2. 新形式は次回起動時に保存状態を置き換え、復元前の状態を退避します。", systemImage: "2.circle.fill")
                        Label("3. 音源は別途保管してください。別のMacではフォルダのアクセス権を再設定します。旧形式は従来の取り込みです。", systemImage: "3.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

            if let preview = store.pendingPreview {
                GroupBox {
                    VStack(alignment: .leading, spacing: 13) {
                        if store.pendingStateRestore {
                            Text("保存時点のライブラリ、評価、詳細履歴、タグ、曲ID対応、特徴量を次回起動時に復元します。現在の状態は退避されます。音源は含まれません。")
                        } else {
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
                        }
                        HStack {
                            Button(store.pendingStateRestore ? "復元を準備（再起動が必要）" : "この内容を復元", systemImage: "arrow.down.doc.fill") { Task { await store.applyImport() } }
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
        .disabled(store.isWorking)
        .navigationTitle("バックアップ")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
            Button("バックアップを書き出す", systemImage: "square.and.arrow.up") { Task { await store.export() } }
            Button("バックアップから復元", systemImage: "square.and.arrow.down") { Task { await store.previewImport() } }

                Spacer(minLength: 0)
            }.disabled(store.isWorking || store.restorePrepared).padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "externaldrive.fill.badge.timemachine")
                .font(.system(size: 42)).foregroundStyle(.tint)
                .frame(width: 76, height: 76).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("コレクションを安全に保存").font(.title.bold())
                Text("曲の紐付けと詳細な利用記録を、検証付きJSONに保存します。")
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
