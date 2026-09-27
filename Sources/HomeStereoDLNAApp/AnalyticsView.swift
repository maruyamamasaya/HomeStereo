#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct AnalyticsView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore
    @Bindable var store: AnalyticsStore
    @State private var section = 0
    @State private var resetAllConfirmation = false
    @State private var resetTrack: AnalyticsTrackSummary?

    var body: some View {
        VStack(spacing: 0) {
            Picker("分析", selection: $section) {
                Text("概要").tag(0)
                Text("再生履歴").tag(1)
                Text("最近の傾向").tag(2)
                Text("評価").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(14)
            Divider()
            content
        }
        .navigationTitle("分析")
        .toolbar {
            Button("再集計", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                .disabled(store.isLoading)
            Menu("管理", systemImage: "ellipsis.circle") {
                Button("すべての分析履歴を削除", role: .destructive) { resetAllConfirmation = true }
                    .disabled(store.snapshot.recentEvents.isEmpty)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.errorMessage {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Spacer()
                    Button("閉じる") { store.dismissError() }
                }
                .font(.caption).padding(10).background(.bar)
            }
        }
        .confirmationDialog(
            "すべての分析用再生履歴を削除しますか？", isPresented: $resetAllConfirmation
        ) {
            Button("履歴を削除", role: .destructive) { Task { await store.resetHistory() } }
        } message: {
            Text("お気に入り、Good／Bad評価、プレイリスト、曲情報は削除されません。")
        }
        .confirmationDialog(
            "「\(resetTrack?.title ?? "この曲")」の履歴を削除しますか？",
            isPresented: Binding(get: { resetTrack != nil }, set: { if !$0 { resetTrack = nil } })
        ) {
            Button("この曲の履歴を削除", role: .destructive) {
                guard let trackID = resetTrack?.trackID else { return }
                resetTrack = nil
                Task { await store.resetHistory(trackID: trackID) }
            }
        } message: {
            Text("お気に入り、Good／Bad評価、プレイリスト、曲情報は維持されます。")
        }
        .task { await store.activate() }
        .onDisappear { store.deactivate() }
        .onChange(of: library.revision) { _, _ in store.invalidate() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.snapshot.generatedAt == .distantPast {
            ProgressView("再生データを集計中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if section == 0 { overview }
        else if section == 1 { history }
        else if section == 2 { trends }
        else { ratings }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    metric("総再生回数", "\(store.snapshot.overview.playCount)", "play.circle")
                    metric("総再生時間", duration(store.snapshot.overview.totalPlaybackDuration), "clock")
                    metric("手動 / 自動", "\(store.snapshot.overview.manualPlayCount) / \(store.snapshot.overview.automaticPlayCount)", "hand.tap")
                    metric("再生した曲", "\(store.snapshot.overview.playedTrackCount)曲", "music.note")
                    metric("お気に入り", "\(store.snapshot.overview.favoriteTrackCount)曲", "heart")
                    metric("今日", "\(store.snapshot.overview.todayPlayCount)回 · \(duration(store.snapshot.overview.todayPlaybackDuration))", "calendar")
                    metric("直近7日", "\(store.snapshot.overview.last7DaysPlayCount)回", "7.circle")
                    metric("直近30日", "\(store.snapshot.overview.last30DaysPlayCount)回", "30.circle")
                }
                if store.snapshot.overview.usesMyMusicPlayCount {
                    Label(
                        "総再生回数・曲別回数・ランキングは、最後に取り込んだMyMusic Library JSONのplayCountです。期間別回数・再生時間・完走率・Skip率は詳細イベントから集計します。",
                        systemImage: "checkmark.seal"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Text("よく再生している曲").font(.title2.bold())
                if store.snapshot.topTracks.isEmpty {
                    ContentUnavailableView(
                        "正式再生の記録がありません", systemImage: "chart.bar",
                        description: Text("自然終了、または min(30秒, 曲長の50%) 以上聴くと集計されます。")
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.snapshot.topTracks) { trackRow($0, showsRating: false); Divider() }
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(14).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private var history: some View {
        Group {
            if store.snapshot.historyDays.isEmpty {
                ContentUnavailableView(
                    "再生履歴はありません", systemImage: "clock.arrow.circlepath",
                    description: Text("曲を実際に再生すると、ここへ日別に記録されます。")
                )
            } else {
                List {
                    ForEach(store.snapshot.historyDays) { day in
                        Section(day.date.formatted(date: .complete, time: .omitted)) {
                            ForEach(day.events) { eventRow($0) }
                        }
                    }
                }
            }
        }
    }

    private func eventRow(_ event: AnalyticsEventRow) -> some View {
        HStack(spacing: 12) {
            artwork(event.trackID, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).lineLimit(1)
                Text(event.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(event.startedAt.formatted(date: .omitted, time: .shortened)) · \(duration(event.listenedSeconds)) · \(sourceLabel(event.startSource))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            platformBadge(event)
            if event.wasFullPlayback { Label("完走", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else if event.wasEarlySkip { Label("Early Skip", systemImage: "forward.fill").foregroundStyle(.orange) }
            else if event.wasSkipped { Label("Skip", systemImage: "forward.end").foregroundStyle(.orange) }
            else { Text("途中終了").foregroundStyle(.secondary) }
        }
        .font(.caption)
    }

    private func platformBadge(_ event: AnalyticsEventRow) -> some View {
        let presentation: (label: String, icon: String) = switch event.playbackPlatform {
        case .mac: ("Mac", "desktopcomputer")
        case .app: ("App", "iphone")
        case .other(let value): (value.isEmpty ? "不明" : value, "questionmark.circle")
        }
        return Label(presentation.label, systemImage: presentation.icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .help("再生元: \(event.platform.isEmpty ? "不明" : event.platform)")
    }

    private var trends: some View {
        Group {
            if store.snapshot.trends.isEmpty {
                ContentUnavailableView(
                    "傾向を計算できる履歴がありません", systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("再生を重ねると、理由付きの傾向を表示します。")
                )
            } else {
                List(store.snapshot.trends) { value in
                    HStack(spacing: 12) {
                        Image(systemName: trendIcon(value.kind)).frame(width: 28).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(value.title).font(.headline)
                            if !value.subtitle.isEmpty { Text(value.subtitle).font(.caption).foregroundStyle(.secondary) }
                            Text(value.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var ratings: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.snapshot.ratings) { value in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(ratingLabel(value.group)).font(.headline)
                            Text("\(value.trackCount)曲 · \(value.playCount)回再生").font(.caption)
                            Text("完走率 \(percent(value.completionRate)) · Skip率 \(percent(value.skipRate))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 190, alignment: .leading).padding(12)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(14)
            }
            Divider()
            List(store.snapshot.allTracks) { trackRow($0, showsRating: true) }
        }
    }

    private func trackRow(_ value: AnalyticsTrackSummary, showsRating: Bool) -> some View {
        HStack(spacing: 12) {
            artwork(value.trackID, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(value.title).font(.headline).lineLimit(1)
                Text([value.artist, value.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("\(value.playCount)回 · \(duration(value.totalPlaybackDuration)) · 完走率 \(percent(value.completionRate)) · Skip率 \(percent(value.skipRate))")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            if showsRating { preferenceMenu(value) }
            Button("再生", systemImage: "play.fill") {
                Task { await queue.playImmediately(trackID: value.trackID, source: .history) }
            }
            .labelStyle(.iconOnly)
            .disabled(!value.isAvailable || !playback.canPlaySelectedOutput)
        }
        .padding(.vertical, 6).padding(.horizontal, showsRating ? 0 : 12)
        .contextMenu {
            Button("この曲の分析履歴を削除", role: .destructive) { resetTrack = value }
        }
    }

    private func preferenceMenu(_ value: AnalyticsTrackSummary) -> some View {
        Menu {
            Button("Good (+1)", systemImage: "hand.thumbsup") { adjustPreference(value.trackID, 1) }
                .disabled((value.playbackPreference ?? 0) >= 10)
            Button("Neutral (0)", systemImage: "minus") { setPreference(value.trackID, 0) }
            Button("Bad (-1)", systemImage: "hand.thumbsdown") { adjustPreference(value.trackID, -1) }
                .disabled((value.playbackPreference ?? 0) <= -10)
        } label: {
            Label(preferenceLabel(value.playbackPreference), systemImage: preferenceIcon(value.playbackPreference))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func artwork(_ trackID: Track.ID, size: CGFloat) -> some View {
        if let track = library.track(id: trackID) {
            CachedArtwork(track: track, library: library, size: size)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .frame(width: size, height: size).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func setPreference(_ trackID: Track.ID, _ value: Int) {
        Task { await store.setPreference(trackID: trackID, value: value) }
    }
    private func adjustPreference(_ trackID: Track.ID, _ delta: Int) {
        Task { await store.adjustPreference(trackID: trackID, delta: delta) }
    }
    private func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 3600 { return "\(value / 3600)時間\((value % 3600) / 60)分" }
        return "\(value / 60)分\(value % 60)秒"
    }
    private func percent(_ value: Double?) -> String {
        guard let value else { return "データなし" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }
    private func sourceLabel(_ source: MyMusicPlaySource) -> String {
        switch source {
        case .library: "ライブラリ"; case .album: "アルバム"; case .artist: "アーティスト"
        case .favorite: "お気に入り"; case .playlist: "プレイリスト"; case .queue: "キュー"
        case .search: "検索"; case .shuffle: "シャッフル"; case .history: "履歴"
        case .station: "ステーション"; case .unknown: "不明"
        }
    }
    private func trendIcon(_ kind: AnalyticsTrendKind) -> String {
        switch kind {
        case .recentPopular: "flame"; case .risingArtist: "chart.line.uptrend.xyaxis"
        case .comeback: "clock.arrow.circlepath"; case .lowPlay: "moon"
        case .earlySkip: "forward.end"
        }
    }
    private func ratingLabel(_ group: AnalyticsRatingGroup) -> String {
        switch group { case .good: "Good"; case .neutral: "Neutral"; case .bad: "Bad"; case .unset: "未設定" }
    }
    private func preferenceLabel(_ value: Int?) -> String {
        guard let value else { return "未設定" }
        if value > 0 { return "Good \(value)" }
        if value < 0 { return "Bad \(value)" }
        return "Neutral"
    }
    private func preferenceIcon(_ value: Int?) -> String {
        guard let value else { return "questionmark.circle" }
        if value > 0 { return "hand.thumbsup.fill" }
        if value < 0 { return "hand.thumbsdown.fill" }
        return "minus.circle"
    }
}
