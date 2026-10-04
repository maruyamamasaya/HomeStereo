#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct TrackFeatureView: View {
    @Bindable var store: TrackFeatureStore
    @State private var visible: [FeatureResolution] = []
    @State private var limit = 200
    @State private var matchFilter = 0
    @State private var showsAnalysis = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("音楽特徴量").font(.largeTitle)
            DisclosureGroup("読み込み・書き出し") {
            HStack {
                Button("特徴量JSONを読み込む…") { Task { await store.chooseImport() } }
                Button("照合を更新") { Task { await store.load() } }
                Button("全件保存用JSONを書き出す…") { Task { await store.exportSnapshot() } }
                    .disabled(store.exportableCount == 0 || store.preview != nil)
                if store.isBusy { ProgressView().controlSize(.small) }
            }.disabled(store.isBusy)
            HStack {
                Picker("解析版", selection: $store.selectedBatch) {
                    Text("最新の解析版").tag(Optional<FeatureBatch>.none)
                    ForEach(store.batches) { batch in
                        Text("解析版\(batch.version)").tag(Optional(batch))
                    }
                }
                Button("iPhone読み込み用JSONを書き出す…") { Task { await store.exportAnalyzer() } }
            }.disabled(store.isBusy || store.rows.isEmpty || store.preview != nil)
            Text("全件保存用はMyMusicの書き出し形式です。iPhoneへの読み込みは解析版ごとのJSONを使います。")
                .font(.caption).foregroundStyle(.secondary)
            }
            Text("保存済み \(store.rows.count)件 · 照合済み \(store.matchedCount)件 · 書き出し可能 \(store.exportableCount)件")
                .foregroundStyle(.secondary)
            DisclosureGroup("解析・音量設定", isExpanded: $showsAnalysis) {
            Text("既存の解析済み曲は維持し、未解析曲・音量未解析曲・更新対象を分けて解析します。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("同時解析数", selection: $store.analysisConcurrency) {
                Text("2曲同時（負荷を控えめに）").tag(FeatureAnalysisConcurrency.two)
                Text("3曲同時（標準）").tag(FeatureAnalysisConcurrency.three)
                Text("6曲同時（速さを優先）").tag(FeatureAnalysisConcurrency.six)
            }
            .pickerStyle(.segmented)
            .disabled(store.isBusy)
            HStack {
                Button("未解析曲を解析（\(store.missingCount)件）") { Task { await store.analyze(.missing) } }
                    .disabled(store.isBusy || store.preview != nil || store.missingCount == 0)
                Button("音量未解析を解析（\(store.missingLoudnessCount)件）") { Task { await store.analyze(.loudness) } }
                    .disabled(store.isBusy || store.preview != nil || store.missingLoudnessCount == 0)
                Button("旧版・変更曲を更新（\(store.updateCount)件）") { Task { await store.analyze(.update) } }
                    .disabled(store.isBusy || store.preview != nil || store.updateCount == 0)
            }
            if let progress = store.analysisProgress {
                HStack {
                    ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                    Text("\(progress.total)曲中 \(progress.completed)曲処理済み（\(Int(100 * Double(progress.completed) / Double(max(1, progress.total))))%）· 失敗 \(progress.failed)件")
                    if store.isBusy { Button("中断") { Task { await store.cancelAnalysis() } } }
                }
                Text("中断は新しい曲の開始を止め、処理中の曲を終えてから行います。完了分は1曲ごとに保存します。アプリを開き直しても復旧でき、残りを再実行できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("このMacで音量ノーマライズ", isOn: $store.normalizationEnabled)
            Text("音源は変更せず、再生時に曲別補正を適用します。増幅用に全曲4 dBの余裕を確保します。DLNA出力には適用しません。")
                .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let message = store.message { Text(message).textSelection(.enabled) }
            if let preview = store.preview {
                VStack(alignment: .leading) {
                    Text("読み込み確認：\(preview.count)件") .font(.headline)
                    Text("照合済み \(preview.filter { $0.localTrackID != nil }.count)件 · 未照合 \(preview.filter { $0.status == "未照合" }.count)件 · 曖昧 \(preview.filter { $0.status == "曖昧" }.count)件")
                    Text("同じ曲は統合し、古い解析版で新しい特徴量を上書きしません。未照合も保存します。")
                        .font(.caption)
                    HStack {
                        Button("読み込む") { Task { await store.applyImport() } }.buttonStyle(.borderedProminent)
                        Button("キャンセル") { store.cancelPreview() }
                    }.disabled(store.isBusy)
                }.padding().homeStereoThemeSurface(cornerRadius: 12)
            }
            HSplitView {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("曲名・アーティスト・パス", text: $store.query).textFieldStyle(.plain)
                        if !store.query.isEmpty { Button("クリア", systemImage: "xmark.circle.fill") { store.query = "" }.labelStyle(.iconOnly).buttonStyle(.plain) }
                    }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    Picker("照合状態", selection: $matchFilter) {
                        Text("すべて").tag(0); Text("照合済み").tag(1); Text("未照合・曖昧").tag(2)
                    }.pickerStyle(.segmented)
                    Text("表示対象 \(visible.count)件").font(.caption).foregroundStyle(.secondary)
                    List(selection: $store.selectedID) {
                        ForEach(visible.prefix(limit)) { row in
                            HStack {
                            Image(systemName: row.localTrackID == nil ? "questionmark.circle" : "checkmark.circle.fill").foregroundStyle(row.localTrackID == nil ? Color.orange : Color.green)
                            VStack(alignment: .leading) {
                                Text(row.record.title ?? row.record.sourceIdentity.title ?? row.record.sourceIdentity.relativePath)
                                Text("\(row.record.artist ?? row.record.sourceIdentity.artist ?? "不明") · \(row.status)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            }.tag(row.id)
                        }
                    }
                    if visible.count > limit {
                        Button("次の200件を表示（全\(visible.count)件）") { limit += 200 }
                    }
                }.frame(minWidth: 240, idealWidth: 290, maxWidth: 350)
                ScrollView {
                    if let row = store.selected { detail(row) }
                    else { Text("曲を選ぶと特徴量と解析の出所を表示します。").foregroundStyle(.secondary).padding() }
                }.frame(minWidth: 360, idealWidth: 500, maxWidth: .infinity)
            }
        }
        .padding().homeStereoThemeScreen()
        .task { await store.load() }
        .task(id: SearchRevision(query: store.query, revision: store.revision, filter: matchFilter)) {
            let rows = store.rows; let query = store.query; let filter = matchFilter
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            let result = await Task.detached {
                rows.filter {
                    (filter == 0 || (filter == 1 ? $0.localTrackID != nil : $0.localTrackID == nil)) && (query.isEmpty || [$0.record.title, $0.record.artist, $0.record.sourceIdentity.relativePath].compactMap { $0 }.contains { $0.localizedStandardContains(query) })
                }
            }.value
            guard !Task.isCancelled else { return }; visible = result; limit = 200
            if let selected = store.selectedID, !result.contains(where: { $0.id == selected }) { store.selectedID = nil }
        }
    }
    private struct SearchRevision: Equatable { let query: String; let revision: Int; let filter: Int }
    private func detail(_ row: FeatureResolution) -> some View {
        let r = row.record
        return VStack(alignment: .leading, spacing: 12) {
            Text(r.title ?? r.sourceIdentity.title ?? "曲名不明").font(.title2)
            Label(row.status, systemImage: row.localTrackID == nil ? "questionmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(row.localTrackID == nil ? Color.orange : Color.green)
            let linked = row.localTrackID.flatMap { store.linkedIDs[$0] } ?? []
            let matches = FeatureIdentityCheck.matches(featureID: r.trackID, linkedIDs: linked, canonicalHomeCount: r.trackID.flatMap { store.canonicalHomeCounts[$0] } ?? 0)
            Label(matches ? "MyMusic Track ID 一致" : (r.trackID == nil ? "MyMusic Track ID 未設定" : (linked.isEmpty ? "MyMusic 連携未確認" : "MyMusic Track ID 不一致・競合")),
                  systemImage: matches ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(matches ? Color.green : Color.orange)
            if !matches && !linked.isEmpty {
                Text("連携先 ID：" + linked.map(\.uuidString).sorted().joined(separator: ", ")).font(.caption)
            }
            GroupBox("解析の出所") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("方式・モデル名：\(r.modelDescription ?? "不明（既存JSONに記録なし）")")
                    Text("解析定義の版：\(r.analysisVersion)")
                    Text("解析日時：\(r.analyzedAt.formatted())")
                    Text("元データ取込日時：\(r.importedAt.formatted())")
                    Text("入力形式：\(r.sourceFormat)")
                    Text("入力ファイル：\(r.sourceFileName)")
                    if let origin = r.loudnessSource {
                        Text("音量項目の補完元：版\(origin.analysisVersion) · \(origin.analyzedAt.formatted()) · \(origin.sourceFileName)")
                        if let method = origin.methodName { Text("音量解析方式：\(method)") }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("対象音源") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.sourceIdentity.relativePath)
                    Text("\(r.sourceIdentity.fileSize) bytes · \(r.sourceIdentity.duration.formatted())秒")
                    if let date = r.sourceIdentity.modificationDate { Text("解析対象の更新日時：\(date.formatted())") }
                    if let id = r.trackID { Text("MyMusic ID：\(id.uuidString)") }
                    if let id = row.localTrackID { Text("HomeStereo ID：\(id.uuidString)") }
                    if let hash = r.sourceIdentity.contentHash { Text("SHA-256：\(hash)") }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("特徴量") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(r.features.values.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: r.features.values[key]!.formatted(.number.precision(.fractionLength(0...6))))
                    }
                    ForEach(r.features.additional.keys.sorted(), id: \.self) { key in
                        LabeledContent("additional.\(key)", value: r.features.additional[key]!.formatted(.number.precision(.fractionLength(0...6))))
                    }
                }
            }
            Text("特徴量スコアを分類の確率として扱いません。照合済みはパス・サイズ・曲長等の照合結果で、音源の完全一致や再解析不要を保証しません。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding().textSelection(.enabled)
    }
}
