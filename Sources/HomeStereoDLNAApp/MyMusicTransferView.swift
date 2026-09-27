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
                    Text("1. ライブラリ　→　2. プレイリスト　→　3. お気に入り・好み　→　4. 再生イベント")
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
                transferRow(.playlists, description: "統合版／通常版／作業用版をkindで分けて取り込む", buttonTitle: importing ? "選択…" : "保存先…") {
                    importing ? await store.selectImport(.playlists) : await store.export(.playlists)
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
            fields = [("全件", value.total), ("Track ID一致", value.matched + value.unchanged),
                      ("相対パス一致", value.relativePathMatches), ("Fingerprint一致", value.fingerprintMatches),
                      ("metadata一致", value.metadataMatches), ("新規登録/関連付け", value.newlyLinked),
                      ("未解決", value.unmatched),
                      ("曖昧", value.ambiguous), ("ID競合", value.conflicts),
                      ("snapshot外", value.missingFromSnapshot), ("不正", value.invalid)]
        case .preferences:
            fields = [("全件", value.total), ("更新予定", value.pendingUpdates),
                      ("変更なし", value.unchanged), ("未解決", value.unresolved), ("invalid", value.invalid)]
        case .playbackEvents:
            fields = [("全件", value.total), ("追加予定", value.pendingInserts),
                      ("重複eventId", value.duplicates), ("未解決", value.unresolved), ("invalid", value.invalid)]
        case .playlists:
            fields = [("全件", value.total), ("追加", value.addedPlaylists),
                      ("更新", value.updatedPlaylists), ("登録曲", value.importedTracks),
                      ("未解決曲", value.unresolved), ("ID競合", value.conflicts)]
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
            } else if let result = store.exportResult, result.kind == .playlists {
                Text("総曲数: \(result.totalPlaylistTracks ?? 0)件　書き出し: \(result.exportedEvents ?? 0)件　MyMusic ID未設定: \(result.unresolvedEvents ?? 0)件　ID競合: \(result.conflictedPlaylistTracks ?? 0)件")
                Text("保存先: \(result.destination)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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

struct MyMusicJSONEditorView: View {
    @Bindable var store: MyMusicJSONEditorStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let message = store.errorMessage {
                banner(message, color: .orange, icon: "exclamationmark.triangle.fill")
            } else if let message = store.completedMessage {
                banner(message, color: .green, icon: "checkmark.circle.fill")
            }
            if store.hasDocument {
                editor
            } else {
                ContentUnavailableView(
                    "編集するJSONを準備してください",
                    systemImage: "tablecells",
                    description: Text("HomeStereoの現在値から作るか、既存のMyMusic JSONを開きます。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("開発者")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MyMusic JSON 加工ツール").font(.title2.bold())
                    Text("DBは変更せず、書き出すJSONの値だけを項目単位で編集します。保存前にMyMusic形式を検証します。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isBusy { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 10) {
                Picker("文書", selection: Binding(
                    get: { store.kind }, set: { store.changeKind(to: $0) }
                )) {
                    ForEach(MyMusicDocumentKind.allCases, id: \.self) { kind in
                        Text(label(kind)).tag(kind)
                    }
                }
                .frame(width: 230)
                Button("現在値から作成", systemImage: "wand.and.stars") {
                    Task { await store.createFromCurrentValues() }
                }
                Button("既存JSONを開く…", systemImage: "folder") {
                    Task { await store.openExistingFile() }
                }
                Spacer()
                Button("JSONを書き出す…", systemImage: "square.and.arrow.up") {
                    Task { await store.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.hasDocument || store.isBusy)
            }
        }
        .padding(20)
    }

    private var editor: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("項目を検索", text: $store.query)
                    .textFieldStyle(.roundedBorder)
                    .padding(10)
                Divider()
                List(store.records, selection: $store.selectedRecordID) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.title).lineLimit(1)
                        if !record.detail.isEmpty {
                            Text(record.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(record.id)
                    .padding(.vertical, 3)
                }
                .overlay {
                    if store.records.isEmpty {
                        ContentUnavailableView.search(text: store.query)
                    }
                }
            }
            .frame(minWidth: 230, idealWidth: 300, maxWidth: 420)

            VStack(spacing: 0) {
                if !store.rootFields.isEmpty {
                    fieldSection("文書設定", fields: store.rootFields)
                    Divider()
                }
                if store.selectedRecordID != nil {
                    fieldSection("選択項目", fields: store.selectedFields)
                } else {
                    ContentUnavailableView(
                        "項目を選択してください", systemImage: "sidebar.left",
                        description: Text("左の一覧から編集対象を選びます。")
                    )
                }
            }
            .frame(minWidth: 480)
        }
    }

    private func fieldSection(_ title: String, fields: [MyMusicJSONEditorField]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(fields.count)項目").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            Divider()
            Table(fields) {
                TableColumn("項目") { field in
                    Text(field.path).font(.callout.monospaced()).textSelection(.enabled)
                }
                .width(min: 160, ideal: 240)
                TableColumn("型") { field in
                    Text(field.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .width(min: 55, ideal: 70, max: 80)
                TableColumn("値") { field in
                    fieldEditor(field)
                }
                .width(min: 220, ideal: 420)
            }
        }
    }

    @ViewBuilder
    private func fieldEditor(_ field: MyMusicJSONEditorField) -> some View {
        switch field.kind {
        case .boolean:
            Toggle("", isOn: Binding(
                get: { field.value == "true" },
                set: { store.update(field, boolean: $0) }
            ))
            .labelsHidden()
        case .null:
            Text("null").foregroundStyle(.secondary)
        case .string, .number:
            TextField("値", text: Binding(
                get: { field.value },
                set: { store.update(field, text: $0) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(field.kind == .number ? .body.monospacedDigit() : .body)
        }
    }

    private func label(_ kind: MyMusicDocumentKind) -> String {
        switch kind {
        case .library: "ライブラリ"
        case .playlists: "プレイリスト"
        case .preferences: "お気に入り・好み"
        case .playbackEvents: "再生イベント"
        }
    }

    private func banner(_ message: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message).font(.subheadline)
            Spacer()
            Button("閉じる") { store.dismissMessage() }.buttonStyle(.borderless)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(color.opacity(0.09))
    }
}

struct MyMusicStatusView: View {
    @Bindable var store: MyMusicStatusStore

    var body: some View {
        let visibleRows = store.visibleRows
        VStack(spacing: 0) {
            statusHeader
            Divider()
            controls(visibleRowCount: visibleRows.count)
            Divider()
            if let errorMessage = store.errorMessage, store.rows.isEmpty {
                ContentUnavailableView(
                    "適用状況を読み込めません", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if store.isLoading && store.rows.isEmpty {
                ProgressView("MyMusic適用状況を読み込み中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.rows.isEmpty {
                ContentUnavailableView(
                    "ライブラリに曲がありません", systemImage: "music.note",
                    description: Text("音楽フォルダを追加してスキャンした後に確認できます。")
                )
            } else {
                applicationTable(visibleRows)
                Divider()
                selectedDetail
            }
        }
        .navigationTitle("MyMusic適用状況")
        .toolbar {
            Button("再読み込み", systemImage: "arrow.clockwise") {
                Task { await store.load() }
            }
            .disabled(store.isLoading)
        }
        .task { await store.load() }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("曲ごとのTrack IDとJSON適用結果").font(.title2.bold())
                    Text("HomeStereoのローカルTrack IDは保持したまま、MyMusic TrackIDとの1対1対応を表示します。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) { summaryMetrics }
                VStack(alignment: .leading, spacing: 7) { summaryMetrics }
            }
            if let errorMessage = store.errorMessage, !store.rows.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var summaryMetrics: some View {
        metric("HomeStereo全曲", store.rows.count)
        metric("TrackID接続済み", store.linkedCount)
        metric("最新JSON内", store.currentSnapshotCount)
        metric("snapshot外", store.missingFromSnapshotCount)
        metric("未接続", store.unlinkedCount)
        metric("MyMusic Playlist", store.myMusicPlaylistCount)
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)").font(.headline.monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func controls(visibleRowCount: Int) -> some View {
        HStack(spacing: 12) {
            TextField("曲名、アーティスト、パス、Track IDで検索", text: $store.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 430)
            Picker("表示", selection: $store.filter) {
                Text("すべて").tag(MyMusicTrackLinkFilter.all)
                Text("接続済み").tag(MyMusicTrackLinkFilter.linked)
                Text("最新JSON内").tag(MyMusicTrackLinkFilter.currentSnapshot)
                Text("snapshot外").tag(MyMusicTrackLinkFilter.missingFromSnapshot)
                Text("未接続").tag(MyMusicTrackLinkFilter.unlinked)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)
            Spacer()
            Text("\(visibleRowCount)曲")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func applicationTable(_ rows: [MyMusicTrackApplicationRow]) -> some View {
        Table(rows, selection: $store.selectedTrackID) {
            TableColumn("曲") { row in
                HStack(spacing: 8) {
                    Text(row.title).lineLimit(1)
                    Text([row.artist, row.album].filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(height: 34, alignment: .leading)
            }
            .width(min: 180, ideal: 260)
            TableColumn("適用") { row in
                Label(linkStatus(row), systemImage: linkStatusIcon(row))
                    .foregroundStyle(linkStatusColor(row))
                    .font(.caption)
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 90, ideal: 110)
            TableColumn("MyMusic TrackID") { row in
                Text(row.myMusicTrackID?.uuidString ?? "—")
                    .font(.caption.monospaced()).lineLimit(1)
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 190, ideal: 240)
            TableColumn("HomeStereo TrackID") { row in
                Text(row.id.uuidString)
                    .font(.caption.monospaced()).lineLimit(1)
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 190, ideal: 240)
            TableColumn("Library JSON") { row in
                Text(row.isLibraryJSONExportable ? "出力対象" : "対象外")
                    .font(.caption)
                    .foregroundStyle(row.isLibraryJSONExportable ? .primary : .secondary)
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 76, ideal: 90)
            TableColumn("照合方法") { row in
                Text(matchMethodLabel(row.matchMethod)).font(.caption)
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 90, ideal: 110)
            TableColumn("MyMusic再生") { row in
                Text(row.myMusicPlayCount.map { "\($0)回" } ?? "—")
                    .font(.caption).monospacedDigit()
                    .frame(height: 34, alignment: .leading)
            }
            .width(min: 80, ideal: 90)
        }
        // Replacing the native table avoids an AppKit diff that eagerly measures
        // thousands of inserted rows when a narrow filter or search is cleared.
        .id("\(store.filter.rawValue)\u{0}\(store.query)")
        .overlay {
            if rows.isEmpty {
                ContentUnavailableView.search(text: store.query)
            }
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        if let row = store.selectedRow {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    detailGroup("HomeStereo現在値", values: [
                        ("Track ID", row.id.uuidString),
                        ("relativePath", row.relativePath),
                        ("音源", row.isAvailable ? "利用可能" : "利用不可")
                    ])
                    detailGroup("MyMusic適用情報", values: [
                        ("TrackID", row.myMusicTrackID?.uuidString ?? "未接続"),
                        ("JSON relativePath", row.myMusicRelativePath ?? "—"),
                        ("最新snapshot", snapshotLabel(row.isInCurrentSnapshot)),
                        ("照合 / source", "\(matchMethodLabel(row.matchMethod)) / \(sourceLabel(row.source))"),
                        ("最終確認", row.lastSeenAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    ])
                    detailGroup("関連データ", values: [
                        ("再生の好み", row.playbackPreference.map(String.init) ?? "未適用"),
                        ("お気に入り", favoriteLabel(row.isFavorite)),
                        ("MyMusic再生回数", row.myMusicPlayCount.map { "\($0)回" } ?? "未適用"),
                        ("再生イベント", "\(row.playbackEventCount)件"),
                        ("MyMusic Playlist", row.myMusicPlaylistNames.isEmpty ? "なし" : row.myMusicPlaylistNames.joined(separator: ", "))
                    ])
                }
                .padding(16)
            }
            .frame(minHeight: 126, idealHeight: 150, maxHeight: 180)
        } else {
            Text("曲を選択すると、HomeStereo現在値とMyMusic適用情報を比較できます。")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .padding(.horizontal, 20)
        }
    }

    private func detailGroup(_ title: String, values: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value.0).foregroundStyle(.secondary).frame(width: 112, alignment: .trailing)
                    Text(value.1).textSelection(.enabled)
                }
                .font(.caption)
            }
        }
    }

    private func linkStatus(_ row: MyMusicTrackApplicationRow) -> String {
        if row.isInCurrentSnapshot == true { return "接続済み" }
        if row.isInCurrentSnapshot == false { return "snapshot外" }
        return "未接続"
    }
    private func linkStatusIcon(_ row: MyMusicTrackApplicationRow) -> String {
        if row.isInCurrentSnapshot == true { return "checkmark.circle.fill" }
        if row.isInCurrentSnapshot == false { return "clock.badge.exclamationmark" }
        return "minus.circle"
    }
    private func linkStatusColor(_ row: MyMusicTrackApplicationRow) -> Color {
        if row.isInCurrentSnapshot == true { return .green }
        if row.isInCurrentSnapshot == false { return .orange }
        return .secondary
    }
    private func snapshotLabel(_ value: Bool?) -> String {
        guard let value else { return "TrackID未接続" }
        return value ? "含まれる" : "含まれない（接続は保持）"
    }
    private func favoriteLabel(_ value: Bool?) -> String {
        guard let value else { return "未適用" }
        return value ? "はい" : "いいえ"
    }
    private func matchMethodLabel(_ value: MyMusicTrackMatchMethod?) -> String {
        switch value {
        case .trackID: "保存済みTrackID"
        case .relativePath: "相対パス"
        case .fingerprint: "Fingerprint"
        case .metadataFallback: "metadata"
        case .manual: "手動"
        case nil: "—"
        }
    }
    private func sourceLabel(_ value: MyMusicLinkSource?) -> String {
        switch value {
        case .libraryImport: "Library Import"
        case .homeStereoExport: "HomeStereo Export"
        case .manual: "手動"
        case nil: "—"
        }
    }
}
