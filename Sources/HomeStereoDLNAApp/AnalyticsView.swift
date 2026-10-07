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
    @Bindable var features: TrackFeatureStore
    @Bindable var genrePresets: GenreDisplayPresetStore
    @Environment(\.homeStereoTheme) private var theme
    @State private var section = 0
    @State private var selectedDate = Date.now
    @State private var month = Date.now
    @State private var weekly = false
    @State private var ratingSelection = 11
    @State private var voiceSelection = 0
    @State private var rateSort = 0
    @State private var resetAllConfirmation = false
    @State private var resetTrack: AnalyticsTrackSummary?

    var body: some View {
        VStack(spacing: 0) {
            Picker("分析", selection: $section) {
                Text("概要").tag(0)
                Text("ランキング").tag(5)
                Text("再生履歴").tag(1)
                Text("最近の傾向").tag(2)
                Text("評価").tag(3)
                Text("完走・スキップ").tag(4)
                Text("作業用BGM時間").tag(6)
                Text("ハイレゾ時間").tag(7)
            }
            .pickerStyle(.segmented)
            .padding(14)
            HStack {
                Picker("期間", selection: $store.period) {
                    ForEach(AnalyticsPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }.frame(maxWidth: 240)
                if store.period == .custom {
                    DatePicker("開始", selection: $store.startDate, displayedComponents: .date)
                    DatePicker("終了", selection: $store.endDate, in: store.startDate..., displayedComponents: .date)
                }
                Spacer()
                Button("再集計", systemImage: "arrow.clockwise") { Task { await store.refresh() } }.disabled(store.isLoading)
                Menu("履歴の管理", systemImage: "ellipsis.circle") {
                    Button("すべての分析履歴を削除", role: .destructive) { resetAllConfirmation = true }
                        .disabled(store.snapshot.recentEvents.isEmpty)
                }
            }.padding(.horizontal, 14).padding(.bottom, 12)
            Divider()
            content
        }
        .navigationTitle("分析")
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.errorMessage {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Spacer()
                    Button("閉じる") { store.dismissError() }
                }
                .font(.caption).padding(10).homeStereoThemeBar()
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
        .task { await store.activate(); if features.rows.isEmpty { await features.load() } }
        .onDisappear { store.deactivate() }
        .onChange(of: store.period) { _, _ in Task { await store.refresh() } }
        .onChange(of: store.startDate) { _, _ in if store.endDate < store.startDate { store.endDate = store.startDate }; Task { await store.refresh() } }
        .onChange(of: store.endDate) { _, _ in Task { await store.refresh() } }
        .onChange(of: library.revision) { _, _ in store.invalidate() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.snapshot.generatedAt == .distantPast {
            ProgressView("再生データを集計中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if section == 0 { overview }
        else if section == 1 { history }
        else if section == 2 { trends }
        else if section == 3 { ratings }
        else if section == 5 { AnalyticsRankingsView(snapshot: store.snapshot, presets: genrePresets, initialPresetID: library.selectedGenrePresetID, library: library, queue: queue, playback: playback) }
        else if section == 6 || section == 7 { categoryTime }
        else { rates }
    }

    private var overview: some View {
        let normalIDs = AnalyticsService.normalTrackIDs(library.tracks)
        let ranked = Array(store.snapshot.allTracks.filter { normalIDs.contains($0.trackID) && $0.playCount > 0 }.prefix(10))
        return ScrollView {
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
                if ranked.isEmpty {
                    ContentUnavailableView(
                        "正式再生の記録がありません", systemImage: "chart.bar",
                        description: Text("自然終了、または min(30秒, 曲長の50%) 以上聴くと集計されます。")
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(ranked) { trackRow($0, showsRating: false); Divider() }
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

    private var allEvents: [AnalyticsEventRow] { store.snapshot.historyDays.flatMap(\.events) }
    private var selectedInterval: DateInterval? {
        Calendar.current.dateInterval(of: weekly ? .weekOfYear : .day, for: selectedDate)
    }
    private var historyEvents: [AnalyticsEventRow] {
        guard let interval = selectedInterval else { return [] }
        return allEvents.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
    }
    private var monthDays: [Date?] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let days: [Date?] = Array(repeating: nil, count: offset) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: interval.start) }
        return days + Array(repeating: nil, count: (7 - days.count % 7) % 7)
    }
    private var history: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("再生カレンダー", systemImage: "calendar").font(.title2.bold())
                    Spacer()
                    Picker("表示期間", selection: $weekly) {
                        Text("日ごと").tag(false); Text("週間").tag(true)
                    }.pickerStyle(.segmented).frame(width: 170)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        calendarPanel.frame(width: 700)
                        historyDetail.frame(minWidth: 230, idealWidth: 280, maxWidth: 340)
                    }.frame(minWidth: 954)
                    VStack(spacing: 24) {
                        calendarPanel.frame(maxWidth: 680)
                        historyDetail
                    }.frame(maxWidth: .infinity)
                }
            }.padding(20)
        }
    }

    private var calendarPanel: some View {
        let counts = Dictionary(uniqueKeysWithValues: store.snapshot.historyDays.map { ($0.date, $0.events.count) })
        return VStack(spacing: 16) {
            HStack {
                Button("前月", systemImage: "chevron.left") { moveMonth(-1) }.labelStyle(.iconOnly)
                Spacer()
                Text(month.formatted(.dateTime.year().month())).font(.title2.bold()).monospacedDigit()
                Spacer()
                Button("翌月", systemImage: "chevron.right") { moveMonth(1) }.labelStyle(.iconOnly)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    let weekday = (Calendar.current.firstWeekday - 1 + index) % 7 + 1
                    Text(Calendar.current.shortWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.semibold)).foregroundStyle(calendarColor(weekday))
                        .frame(maxWidth: .infinity).padding(.bottom, 4)
                }
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date { calendarDay(date, count: counts[date, default: 0]) }
                    else {
                        Color.secondary.opacity(0.025).aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: theme.calendarCornerRadius))
                            .accessibilityHidden(true)
                    }
                }
            }
            HStack {
                Button("今日に戻る") { month = .now; selectedDate = .now }
                Spacer()
                Button("最新の履歴") {
                    if let latest = store.snapshot.historyDays.first?.date { month = latest; selectedDate = latest }
                }.disabled(store.snapshot.historyDays.isEmpty)
            }.font(.caption)
            Text("日付を押すと、その日／週の曲と再生時間を表示します。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).homeStereoThemeSurface(cornerRadius: 18)
    }

    private func calendarColor(_ weekday: Int) -> Color {
        weekday == 1 ? theme.calendarSunday : (weekday == 7 ? theme.calendarSaturday : .secondary)
    }

    private func calendarDay(_ date: Date, count: Int) -> some View {
        let weekday = Calendar.current.component(.weekday, from: date)
        let weekend = weekday == 1 || weekday == 7
        let color = calendarColor(weekday)
        let selected = selectedInterval.map { date >= $0.start && date < $0.end } == true
        let today = Calendar.current.isDateInToday(date)
        let shape = RoundedRectangle(cornerRadius: theme.calendarCornerRadius)
        return Button { selectedDate = date } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(date.formatted(.dateTime.day())).font(.system(size: 12, weight: selected || today ? .semibold : .regular))
                                .foregroundStyle(weekend ? color : .secondary)
                            Spacer(minLength: 0)
                            Circle().fill(today ? theme.accent : .clear).frame(width: 5, height: 5)
                        }
                        Spacer(minLength: 0)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(count)").font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("件").font(.system(size: 10))
                        }.foregroundStyle(count > 0 ? (selected ? theme.accent : .primary) : .secondary)
                    }.padding(10)
                }
                .background {
                    shape.fill(theme.surface)
                    shape.fill(LinearGradient(colors: [selected ? theme.accent.opacity(0.26) : (weekend ? color.opacity(0.08) : .clear), theme.accent.opacity(selected ? 0.08 : 0.015)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .overlay { shape.strokeBorder(selected || today ? theme.accent : color.opacity(weekend ? 0.35 : 0.16), lineWidth: selected ? 2 : 1) }
                .contentShape(shape)
        }.buttonStyle(.plain)
            .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))、再生履歴\(count)件\(today ? "、今日" : "")")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(today ? "今日 · \(count)件の再生履歴" : "\(count)件の再生履歴")
    }

    private var monthlyRecap: some View {
        let calendar = Calendar.current
        let current = calendar.dateInterval(of: .month, for: month)!
        let previous = calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: month)!)!
        let ids = AnalyticsService.normalTrackIDs(library.tracks)
        let events = AnalyticsService.events(in: store.fullSnapshot, interval: current, trackIDs: ids)
        let old = AnalyticsService.events(in: store.fullSnapshot, interval: previous, trackIDs: ids)
        let seconds = events.reduce(0) { $0 + $1.listenedSeconds }
        let delta = seconds - old.reduce(0) { $0 + $1.listenedSeconds }
        let top = Dictionary(grouping: events, by: \.trackID).values.sorted { a, b in
            a.count == b.count ? (a.first?.title ?? "") < (b.first?.title ?? "") : a.count > b.count
        }.first?.first?.title
        let artist = Dictionary(grouping: events, by: \.artist).sorted {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }.first?.key
        return VStack(alignment: .leading, spacing: 8) {
            Text("この月の振り返り・通常曲").font(.headline)
            Text("\(events.count)件 · \(duration(seconds))")
            Text("前月との差 \(delta >= 0 ? "+" : "−")\(duration(abs(delta)))")
            Text("代表曲：\(top ?? "履歴なし")")
            Text("代表アーティスト：\(artist ?? "履歴なし")")
            Text("保存済み詳細履歴による集計。期間選択とは独立して表示中の月を振り返ります。前月に履歴がない場合も記録上の0との差です。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).homeStereoThemeSurface(cornerRadius: 14)
    }

    private var categoryTime: some View {
        let ids = Set(library.tracks.filter { section == 6 ? $0.isEligibleForWorkPlayback : $0.isHighResolutionAudio }.map(\.id))
        let days = store.snapshot.historyDays.map { day in
            (day.date, day.events.filter { ids.contains($0.trackID) }.reduce(0) { $0 + $1.listenedSeconds })
        }.filter { $0.1 > 0 }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(section == 6 ? "作業用BGMの再生時間" : "ハイレゾの再生時間").font(.title2.bold())
                Text("\(store.period.title) · \(duration(days.reduce(0) { $0 + $1.1 }))").font(.title)
                Text("詳細履歴の実聴時間。現在のライブラリ分類を使います。両方に属する曲は両ページに含まれます。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(days, id: \.0) { day in
                    HStack { Text(day.0, style: .date); Spacer(); Text(duration(day.1)) }
                }
                if days.isEmpty { Text("この期間の再生時間の記録はありません") }
            }.padding(20)
        }
    }

    private var historyDetail: some View {
        let events = historyEvents
        return VStack(alignment: .leading, spacing: 14) {
            monthlyRecap
            VStack(alignment: .leading, spacing: 7) {
                Text(weekly ? "\(selectedInterval?.start.formatted(date: .abbreviated, time: .omitted) ?? "")からの1週間" : selectedDate.formatted(date: .complete, time: .omitted)).font(.title3.bold())
                HStack(spacing: 18) {
                    Label("\(events.count)件", systemImage: "music.note.list")
                    Label(duration(events.reduce(0) { $0 + $1.listenedSeconds }), systemImage: "clock")
                }.font(.subheadline).foregroundStyle(theme.accent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16).homeStereoThemeSurface(cornerRadius: 14)
            if events.isEmpty {
                ContentUnavailableView("この期間の履歴はありません", systemImage: "calendar")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(events) { event in
                        eventRow(event).padding(12)
                        Divider().padding(.horizontal, 12)
                    }
                }.homeStereoThemeSurface(cornerRadius: 14)
            }
        }
    }

    private func moveMonth(_ value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private func eventRow(_ event: AnalyticsEventRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                artwork(event.trackID, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                    Text(event.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Text("\(event.startedAt.formatted(date: .omitted, time: .shortened)) · \(duration(event.listenedSeconds))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                platformBadge(event)
            }
            HStack {
                Text(sourceLabel(event.startSource)).foregroundStyle(.tertiary)
                Spacer(minLength: 4)
                if event.wasFullPlayback { Label("完走", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else if event.wasEarlySkip { Label("Early Skip", systemImage: "forward.fill").foregroundStyle(.orange) }
                else if event.wasSkipped { Label("Skip", systemImage: "forward.end").foregroundStyle(.orange) }
                else { Text("途中終了").foregroundStyle(.secondary) }
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
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

    private let voiceLabels = ["すべて", "ボーカル", "インスト", "判定保留", "未解析"]
    private var trends: some View {
        let recent = allEvents.filter { $0.startedAt >= Calendar.current.date(byAdding: .day, value: -7, to: .now)! }
        var categories: [UUID: Int] = [:]
        let ordered = features.rows.sorted {
            $0.record.analysisVersion == $1.record.analysisVersion ? $0.record.analyzedAt < $1.record.analyzedAt : $0.record.analysisVersion < $1.record.analysisVersion
        }
        for row in ordered {
            if let id = row.localTrackID { categories[id] = FeatureVoiceCategory.classify(row.record.features.values).rawValue }
        }
        let grouped = Dictionary(grouping: recent, by: { categories[$0.trackID, default: 4] })
        let selected = recent.filter { voiceSelection == 0 || categories[$0.trackID, default: 4] == voiceSelection }
        let counts = Dictionary(grouping: selected, by: \.trackID).mapValues(\.count)
        let tracks = store.snapshot.allTracks.filter { counts[$0.trackID] != nil }.sorted { counts[$0.trackID, default: 0] > counts[$1.trackID, default: 0] }
        return VStack(alignment: .leading, spacing: 12) {
            Text("直近7日間の聴き方").font(.title2.bold())
            HStack {
                ForEach(1..<5) { category in
                    metric(voiceLabels[category], "\(grouped[category, default: []].count)件", category == 1 ? "mic" : "music.note")
                }
            }
            Picker("曲のタイプ", selection: $voiceSelection) { ForEach(0..<5) { Text(voiceLabels[$0]).tag($0) } }.pickerStyle(.segmented)
            Text("解析スコアの差による目安です。確率ではありません。差が小さい曲は判定保留、特徴量がない曲は未解析に分けます。").font(.caption).foregroundStyle(.secondary)
            List {
                if voiceSelection == 0 {
                    Section("傾向と理由") {
                        ForEach(store.snapshot.trends) { value in
                            VStack(alignment: .leading, spacing: 4) { Label(value.title, systemImage: trendIcon(value.kind)).font(.headline); Text(value.reason).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("この期間によく聴いた曲") {
                    ForEach(tracks) { track in
                        HStack { trackRow(track, showsRating: false); Text("直近7日 \(counts[track.trackID, default: 0])件").monospacedDigit() }
                    }
                    if tracks.isEmpty { Text("この分類の再生履歴はありません").foregroundStyle(.secondary) }
                }
            }
        }.padding(16)
    }
    private var ratings: some View {
        let groups = Dictionary(grouping: store.snapshot.allTracks, by: { $0.playbackPreference ?? 11 })
        return VStack(alignment: .leading, spacing: 12) {
            Text("Good / Bad の評価別に曲を探す").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82))], spacing: 8) {
                ForEach(Array(stride(from: 10, through: -10, by: -1)) + [11], id: \.self) { rating in
                    Button { ratingSelection = rating } label: {
                        VStack(spacing: 4) {
                            Text(rating == 11 ? "未設定" : (rating > 0 ? "+\(rating)" : "\(rating)")).font(.headline)
                            Text("\(groups[rating, default: []].count)曲").font(.caption)
                        }.frame(maxWidth: .infinity).padding(8)
                            .background(ratingSelection == rating ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
            Text(ratingSelection == 11 ? "未設定の曲" : "評価 \(ratingSelection) の曲").font(.headline)
            List(groups[ratingSelection, default: []]) { trackRow($0, showsRating: true) }
                .overlay { if groups[ratingSelection, default: []].isEmpty { ContentUnavailableView("この評価の曲はありません", systemImage: "hand.thumbsup") } }
        }.padding(16)
    }
    private var rates: some View {
        let events = allEvents
        let measured = events.filter { $0.completionRatio != nil }
        let completed = measured.filter(\.wasFullPlayback).count
        let skipped = events.filter(\.wasSkipped).count
        let tracks = store.snapshot.allTracks.filter { $0.sessionCount > 0 }.sorted {
            rateSort == 0 ? ($0.skipRate ?? -1) > ($1.skipRate ?? -1) : ($0.completionRate ?? -1) > ($1.completionRate ?? -1)
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("完走率・スキップ率").font(.title2.bold())
            HStack {
                metric("完走率", percent(measured.isEmpty ? nil : Double(completed) / Double(measured.count)), "checkmark.circle")
                metric("スキップ率", percent(events.isEmpty ? nil : Double(skipped) / Double(events.count)), "forward.end")
                metric("Early Skip", "\(events.filter(\.wasEarlySkip).count)件", "forward.fill")
            }
            Text("全期間の詳細履歴を集計。完走 \(completed) / 曲長が判明している \(measured.count)件、スキップ \(skipped) / 全 \(events.count)件。履歴を削除した期間は含みません。").font(.caption).foregroundStyle(.secondary)
            Picker("並び順", selection: $rateSort) { Text("スキップ率が高い順").tag(0); Text("完走率が高い順").tag(1) }.pickerStyle(.segmented)
            List(tracks) { trackRow($0, showsRating: false, showsRates: true) }
        }.padding(16)
    }

    private func trackRow(_ value: AnalyticsTrackSummary, showsRating: Bool, showsRates: Bool = false) -> some View {
        HStack(spacing: 12) {
            artwork(value.trackID, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(value.title).font(.headline).lineLimit(1)
                Text([value.artist, value.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(showsRates ? "\(value.sessionCount)件 · 完走率 \(percent(value.completionRate)) · スキップ率 \(percent(value.skipRate)) · Early Skip \(value.earlySkipCount)件" : "\(value.playCount)回 · \(duration(value.totalPlaybackDuration))")
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
