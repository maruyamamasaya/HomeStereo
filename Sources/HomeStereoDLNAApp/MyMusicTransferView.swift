#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct MyMusicTransferView: View {
    @Bindable var store: MyMusicTransferStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GroupBox("推奨する読み込み順序") {
                    Text("1. ライブラリ　→　2. お気に入り・好み　→　3. 再生イベント")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
                if let error = store.errorMessage { banner(error, error: true) }
                else if let message = store.completedMessage { completion(message) }
                transferSection(title: "MyMusicから読み込む", importing: true)
                transferSection(title: "MyMusic向けに書き出す", importing: false)
                if let preview = store.preview { previewCard(preview) }
            }
            .padding(24).frame(maxWidth: 920).frame(maxWidth: .infinity)
        }
        .navigationTitle("MyMusic連携")
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 42)).foregroundStyle(.tint)
                .frame(width: 76, height: 76).background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text("MyMusic JSONを手動で受け渡す").font(.title.bold())
                Text("ファイルを選んで内容を確認してから読み込みます。自動同期は行いません。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func transferSection(title: String, importing: Bool) -> some View {
        GroupBox(title) {
            VStack(spacing: 0) {
                transferRow(.library, description: "曲情報とMyMusic trackIDの対応", buttonTitle: importing ? "選択…" : "保存先…") {
                    importing ? await store.selectImport(.library) : await store.export(.library)
                }
                Divider()
                transferRow(.preferences, description: "お気に入りと再生の好み", buttonTitle: importing ? "選択…" : "保存先…") {
                    importing ? await store.selectImport(.preferences) : await store.export(.preferences)
                }
                Divider()
                transferRow(.playbackEvents, description: "再生日時・実聴時間・完了状態", buttonTitle: importing ? "選択…" : "保存先…") {
                    importing ? await store.selectImport(.playbackEvents) : await store.export(.playbackEvents)
                }
            }
        }
    }

    private func transferRow(
        _ kind: MyMusicDocumentKind, description: String, buttonTitle: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind == .playbackEvents ? "clock.arrow.circlepath" : "doc.text")
                .frame(width: 24).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.fileName).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.isBusy ? "処理中…" : buttonTitle) {
                Task { await action() }
            }
            .disabled(store.isBusy || store.state == .preview)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func previewCard(_ preview: MyMusicImportPreview) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("読み込み前の確認 — \(preview.kind.fileName)", systemImage: "doc.text.magnifyingglass")
                    .font(.title3.bold())
                summary(preview)
                if !preview.details.isEmpty {
                    Divider()
                    Text("明細（先頭\(preview.details.count)件）").font(.headline)
                    LazyVStack(spacing: 0) {
                        ForEach(preview.details) { detail in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(detail.title).lineLimit(1)
                                    Text(detail.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    Text(detail.trackID.uuidString).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(detail.result).font(.caption.bold())
                                    if let reason = detail.reason {
                                        Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                HStack {
                    Button("読み込む", systemImage: "arrow.down.doc.fill") {
                        Task { await store.applyImport() }
                    }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy)
                    Button("キャンセル", role: .cancel) { store.cancelImport() }.disabled(store.isBusy)
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ value: MyMusicImportPreview) -> some View {
        let fields: [(String, Int)]
        switch value.kind {
        case .library:
            fields = [("全件", value.total), ("matched", value.matched), ("newlyLinked", value.newlyLinked),
                      ("unchanged", value.unchanged), ("unmatched", value.unmatched),
                      ("ambiguous", value.ambiguous), ("invalid", value.invalid)]
        case .preferences:
            fields = [("全件", value.total), ("更新予定", value.pendingUpdates),
                      ("変更なし", value.unchanged), ("未解決", value.unresolved), ("invalid", value.invalid)]
        case .playbackEvents:
            fields = [("全件", value.total), ("追加予定", value.pendingInserts),
                      ("重複eventId", value.duplicates), ("未解決", value.unresolved), ("invalid", value.invalid)]
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 22) { ForEach(fields, id: \.0) { metric($0.0, $0.1) } }
            VStack(alignment: .leading, spacing: 7) { ForEach(fields, id: \.0) { metric($0.0, $0.1) } }
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func completion(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            banner(message, error: false)
            if let result = store.exportResult, result.kind == .playbackEvents {
                Text("書き出したイベント: \(result.exportedEvents ?? 0)件　未解決のため除外: \(result.unresolvedEvents ?? 0)件")
                Text("保存先: \(result.destination)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if result.hasUnresolvedEventWarning {
                    Text("MyMusicと未接続の曲に対する再生記録は今回のJSONに含まれていません。ライブラリJSONを読み込んで曲を接続すると、次回以降に書き出せます。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private func banner(_ message: String, error: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(error ? .orange : .green)
            Text(message).font(.subheadline)
            Spacer()
            Button("閉じる") { store.dismissResult() }.buttonStyle(.borderless)
        }
        .padding(12).background((error ? Color.orange : Color.green).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}
