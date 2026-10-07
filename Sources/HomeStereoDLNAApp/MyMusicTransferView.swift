#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct MyMusicTransferView: View {
    @Bindable var store: MyMusicTransferStore
    @Bindable var features: TrackFeatureStore
    @State private var limitsPlaybackEventRange = true
    @State private var playbackEventsStartDate = Calendar.current.date(
        byAdding: .month, value: -1, to: .now
    ) ?? .now
    @State private var playbackEventsEndDate = Date.now

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
                GroupBox("音楽特徴量の受け渡し") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("iPhone読み込み用は解析版ごと、全件保存用はMyMusic Track IDがある曲を書き出します。").font(.caption).foregroundStyle(.secondary)
                        Picker("解析版", selection: $features.selectedBatch) {
                            Text("最新の解析版").tag(Optional<FeatureBatch>.none)
                            ForEach(features.batches) { Text("解析版\($0.version)").tag(Optional($0)) }
                        }
                        HStack {
                            Button("iPhone読み込み用JSON…") { Task { await features.exportAnalyzer() } }.disabled(features.rows.isEmpty)
                            Button("全件保存用JSON…") { Task { await features.exportSnapshot() } }.disabled(features.exportableCount == 0)
                            Button("特徴量JSONを読み込む…") { Task { await features.chooseImport() } }
                        }.disabled(features.isBusy || features.preview != nil)
                        if let preview = features.preview {
                            Text("読み込み候補 \(preview.count)件 · 照合済み \(preview.filter { $0.localTrackID != nil }.count)件")
                            HStack {
                                Button("確認して読み込む") { Task { await features.applyImport() } }
                                Button("キャンセル") { features.cancelPreview() }
                            }.disabled(features.isBusy)
                        }
                        if let message = features.message { Text(message).font(.caption) }
                        if let error = features.errorMessage { Text(error).foregroundStyle(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let preview = store.preview { previewCard(preview) }
                if let preview = store.preferencesExportPreview { preferencesExportPreviewCard(preview) }
            }
            .padding(24).frame(maxWidth: 920).frame(maxWidth: .infinity)
        }
        .confirmationDialog("重複する曲をまとめて書き出しますか？", isPresented: Binding(
            get: { store.duplicatePlaylistExportCount != nil },
            set: { if !$0 { store.duplicatePlaylistExportCount = nil } }
        )) {
            Button("JSON内の重複をまとめて書き出す") {
                Task { await store.export(.playlists, deduplicatePlaylists: true) }
            }
            Button("キャンセル", role: .cancel) { store.duplicatePlaylistExportCount = nil }
        } message: {
            Text("同じ曲の重複が\(store.duplicatePlaylistExportCount ?? 0)件あります。各プレイリストで最初の1回だけをJSONに出力します。元のプレイリストの曲順や重複は変更しません。")
        }
        .navigationTitle("MyMusic連携")
        .task { if features.rows.isEmpty { await features.load() } }
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
                transferRow(
                    .preferences,
                    description: importing ? "お気に入りと再生の好み" : "Macで変更したお気に入りとGood／Badだけ",
                    buttonTitle: importing ? "選択…" : "対象を確認…"
                ) {
                    importing ? await store.selectImport(.preferences) : await store.preparePreferencesExport()
                }
                Divider()
                if importing {
                    transferRow(.playbackEvents, description: "再生日時・実聴時間・完了状態", buttonTitle: "選択…") {
                        await store.selectImport(.playbackEvents)
                    }
                } else {
                    playbackEventsExportRow
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
            .disabled(store.isBusy)
        }
        .padding(.vertical, 11)
    }

    private var playbackEventsExportRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 24).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MyMusicDocumentKind.playbackEvents.fileName).font(.headline)
                    Text("再生日時・実聴時間・完了状態").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.isBusy ? "処理中…" : "保存先…") {
                    Task { await store.export(.playbackEvents, playbackEventsRange: playbackEventsRange) }
                }
                .disabled(store.isBusy)
            }
            Picker("書き出す期間", selection: $limitsPlaybackEventRange) {
                Text("期間指定").tag(true)
                Text("全期間").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            if limitsPlaybackEventRange {
                HStack(spacing: 12) {
                    DatePicker(
                        "開始", selection: $playbackEventsStartDate,
                        in: ...playbackEventsEndDate, displayedComponents: .date
                    )
                    DatePicker(
                        "終了", selection: $playbackEventsEndDate,
                        in: playbackEventsStartDate..., displayedComponents: .date
                    )
                    Text("両日を含む").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("保存済みの再生イベントをすべて書き出します。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 11)
    }

    private var playbackEventsRange: Range<Date>? {
        guard limitsPlaybackEventRange else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let lowerBound = calendar.startOfDay(for: playbackEventsStartDate)
        guard let upperBound = calendar.date(
            byAdding: .day, value: 1, to: calendar.startOfDay(for: playbackEventsEndDate)
        ) else { return nil }
        return lowerBound..<upperBound
    }

    @ViewBuilder
    private func previewCard(_ preview: MyMusicImportPreview) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("読み込み前の確認 — \(preview.kind.fileName)", systemImage: "doc.text.magnifyingglass")
                    .font(.title3.bold())
                summary(preview)
                if preview.kind == .playlists {
                    Text("同じIDのプレイリストは名前・タグ・曲順を受信内容へ更新します。更新前のデータと受信原本をアプリ内に保管します。")
                        .font(.callout).foregroundStyle(.secondary)
                    if preview.unresolved > 0 || preview.conflicts > 0 {
                        Text("未照合またはID競合の曲があります。Library JSONの照合後に元のJSONを再読み込みしてください。")
                            .foregroundStyle(.orange)
                    }
                }
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
                    .buttonStyle(.borderedProminent).disabled(store.isBusy || (preview.kind == .playlists && (preview.unresolved > 0 || preview.conflicts > 0)))
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

    @ViewBuilder
    private func preferencesExportPreviewCard(_ preview: MyMusicPreparedPreferencesExport) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("書き出し前の確認 — \(MyMusicDocumentKind.preferences.fileName)", systemImage: "doc.text.magnifyingglass")
                    .font(.title3.bold())
                HStack(spacing: 8) {
                    Text("Macで変更した対象")
                    Text("\(preview.pendingChanges.count)曲").font(.headline.monospacedDigit())
                }
                Text("MyMusicから読み込んだだけの曲や、Macで変更していない曲は含みません。")
                    .font(.caption).foregroundStyle(.secondary)
                if preview.items.isEmpty {
                    ContentUnavailableView(
                        "未送信の変更はありません", systemImage: "checkmark.circle",
                        description: Text("Macでお気に入りまたはGood／Badを変更すると対象になります。")
                    )
                    .frame(maxWidth: .infinity).frame(height: 150)
                } else {
                    Divider()
                    Text("対象一覧（先頭\(preview.items.count)件）").font(.headline)
                    LazyVStack(spacing: 0) {
                        ForEach(preview.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(1)
                                    if !item.artist.isEmpty {
                                        Text(item.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Text(item.myMusicTrackID.uuidString)
                                        .font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Label(item.favorite ? "お気に入り" : "お気に入り解除",
                                          systemImage: item.favorite ? "heart.fill" : "heart.slash")
                                    Text("Good／Bad: \(item.playbackPreference)")
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 7)
                            Divider()
                        }
                    }
                }
                HStack {
                    Button("保存先を選ぶ…", systemImage: "square.and.arrow.up") {
                        Task { await store.confirmPreferencesExport() }
                    }
                    .buttonStyle(.borderedProminent).disabled(store.isBusy)
                    Button("キャンセル", role: .cancel) { store.cancelPreferencesExport() }
                        .disabled(store.isBusy)
                    if store.isBusy { ProgressView().controlSize(.small) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                if let range = result.playbackEventsRange {
                    Text("対象期間: \(range.lowerBound.formatted(date: .numeric, time: .omitted))〜\(range.upperBound.addingTimeInterval(-1).formatted(date: .numeric, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("対象期間: 全期間").font(.caption).foregroundStyle(.secondary)
                }
                Text("保存先: \(result.destination)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if result.hasUnresolvedEventWarning {
                    Text("MyMusicと未接続の曲に対する再生記録は今回のJSONに含まれていません。ライブラリJSONを読み込んで曲を接続すると、次回以降に書き出せます。")
                        .font(.caption).foregroundStyle(.orange)
                }
            } else if let result = store.exportResult, result.kind == .playlists {
                Text("総曲数: \(result.totalPlaylistTracks ?? 0)件　書き出し: \(result.exportedEvents ?? 0)件　MyMusic ID未設定: \(result.unresolvedEvents ?? 0)件　ID競合: \(result.conflictedPlaylistTracks ?? 0)件")
                Text("保存先: \(result.destination)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else if let result = store.exportResult, result.kind == .preferences {
                Text("Macで変更した曲: \(result.exportedEvents ?? 0)件")
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
    @Bindable var features: TrackFeatureStore
    @State private var fieldQuery = ""
    @State private var featureFieldsOnly = false

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
        .navigationTitle("JSON加工ツール")
        .task { if features.rows.isEmpty { await features.load() } }
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
            Text("1. 種類を選ぶ → 2. 現在値から作成／既存JSONを開く → 3. 曲と項目を編集 → 4. 検証して保存").font(.caption).foregroundStyle(.secondary)
            Picker("対象", selection: Binding(get: { store.editsFeatures }, set: { store.changeFeatureMode($0) })) {
                Text("ライブラリ・コレクション").tag(false); Text("音楽特徴量").tag(true)
            }.pickerStyle(.segmented)
            HStack(spacing: 10) {
                if !store.editsFeatures {
                Picker("文書", selection: Binding(
                    get: { store.kind }, set: { store.changeKind(to: $0) }
                )) {
                    ForEach(MyMusicDocumentKind.allCases, id: \.self) { kind in
                        Text(label(kind)).tag(kind)
                    }
                }
                .frame(width: 200)
                }
                Button("現在値から作成", systemImage: "wand.and.stars") {
                    Task { if store.editsFeatures { await store.createFeatures(features.rows.map(\.record)) } else { await store.createFromCurrentValues() } }
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
            if store.editsFeatures {
                Text("ID付き曲の全件保存用JSONを作成できます。既存のiPhone読み込み用JSONも編集できます。編集はファイルのみへ保存します。ライブラリへの反映は音楽特徴量ページから読み込んでください。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(store.isBusy)
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
                    DisclosureGroup("文書設定（形式・日時）") {
                        fieldSection("文書設定", fields: store.rootFields).frame(height: 170)
                    }.padding(10)
                    Divider()
                }
                if store.selectedRecordID != nil {
                    HStack {
                        TextField("項目名で絞り込む", text: $fieldQuery).textFieldStyle(.roundedBorder)
                        if store.editsFeatures { Toggle("特徴量のみ", isOn: $featureFieldsOnly) }
                    }.padding(10)
                    fieldSection("選択項目", fields: store.selectedFields.filter {
                        (fieldQuery.isEmpty || $0.path.localizedStandardContains(fieldQuery)) && (!store.editsFeatures || !featureFieldsOnly || $0.path.hasPrefix("features."))
                    })
                } else {
                    ContentUnavailableView(
                        "項目を選択してください", systemImage: "sidebar.left",
                        description: Text("左の一覧から編集対象を選びます。")
                    )
                }
            }
            .frame(minWidth: 360)
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fieldLabel(field.path)).font(.callout)
                        Text(field.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }.textSelection(.enabled)
                }
                .width(min: 110, ideal: 190)
                TableColumn("型") { field in
                    Text(field.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .width(min: 45, ideal: 55, max: 65)
                TableColumn("値") { field in
                    fieldEditor(field)
                }
                .width(min: 150, ideal: 320)
            }
        }
    }

    private func fieldLabel(_ path: String) -> String {
        let key = path.split(separator: ".").last.map(String.init) ?? path
        return ["trackID": "MyMusic Track ID", "title": "曲名", "artist": "アーティスト", "album": "アルバム",
                "playbackPreference": "Good / Bad 評価（−10〜＋10）", "favorite": "お気に入り",
                "vocal": "ボーカルスコア", "instrumental": "インストスコア", "energy": "エネルギー",
                "duration": "曲長（秒）", "fileSize": "ファイルサイズ（bytes）", "relativePath": "音源の相対パス",
                "analysisVersion": "解析版", "analyzedAt": "解析日時", "integratedLoudness": "統合ラウドネス" ][key] ?? key
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
            Button("再読み込み", systemImage: "arrow.clockwise") {
                Task { await store.load() }
            }
            .disabled(store.isLoading)

                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
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
