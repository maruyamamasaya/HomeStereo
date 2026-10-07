#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct AnalyticsRankingsView: View {
    let snapshot: AnalyticsSnapshot
    @Bindable var presets: GenreDisplayPresetStore
    let initialPresetID: UUID?
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playback: RendererPlaybackStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("再生ランキング").font(.largeTitle.bold())
                    Text("通常曲のランキングを種類ごとのページで確認できます。各ページに再生回数と実聴時間を50位まで表示します。")
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(AnalyticsRankingKind.allCases, id: \.self) { kind in
                            NavigationLink {
                                AnalyticsRankingDetailView(snapshot: snapshot, presets: presets, initialPresetID: initialPresetID,
                                    library: library, queue: queue, playback: playback, kind: kind)
                            } label: {
                                HStack {
                                    Label(kind.title, systemImage: kind.symbol).font(.title2.bold())
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                                    .homeStereoThemeSurface(cornerRadius: 14)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(20)
            }
        }
    }
}

private struct RankingPageRequest: Equatable, Sendable {
    let summaries: [AnalyticsTrackSummary]
    let tracks: [Track]
    let kind: AnalyticsRankingKind
    let preset: GenreDisplayPreset?
}

private struct AnalyticsRankingDetailView: View {
    let snapshot: AnalyticsSnapshot
    @Bindable var presets: GenreDisplayPresetStore
    let initialPresetID: UUID?
    @Bindable var library: LibraryStore
    @Bindable var queue: QueueStore
    @Bindable var playback: RendererPlaybackStore
    let kind: AnalyticsRankingKind
    @State private var presetID: UUID?
    @State private var didInitialize = false
    @State private var page = AnalyticsRankingPage.empty
    @State private var isLoading = true
    @State private var selected: AnalyticsRankingRow?

    private var request: RankingPageRequest {
        RankingPageRequest(summaries: snapshot.allTracks, tracks: library.tracks, kind: kind,
                           preset: presets.presets.first { $0.id == presetID })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(kind.title)の再生ランキング").font(.largeTitle.bold())
                Text("通常曲のみ・50位まで。作業用BGMとハイレゾは対象外です。回数は全期間のみMyMusic累計を優先し、期間指定と時間は詳細履歴から集計します。")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("ジャンルプリセット", selection: $presetID) {
                    Text("すべて").tag(Optional<UUID>.none)
                    ForEach(presets.presets) { Text($0.name).tag(Optional($0.id)) }
                }.frame(maxWidth: 420)
                if kind != .track {
                    Text("画像は収録曲から固定で選んだ代表アートワークです。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if isLoading { ProgressView("ランキングを集計中…") }
                else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 20)], alignment: .leading, spacing: 20) {
                        rankingCard("再生回数", rows: page.byCount, byTime: false, tint: .blue)
                        rankingCard("実聴時間", rows: page.byTime, byTime: true, tint: .purple)
                    }
                }
            }.padding(20)
        }
        .navigationTitle(kind.title)
        .onAppear { if !didInitialize { presetID = initialPresetID; didInitialize = true } }
        .task(id: request) {
            let input = request
            isLoading = true
            let value = await Task.detached(priority: .userInitiated) {
                AnalyticsService.rankingPage(summaries: input.summaries, libraryTracks: input.tracks,
                                             kind: input.kind, preset: input.preset)
            }.value
            guard !Task.isCancelled else { return }
            page = value; isLoading = false
        }
        .sheet(item: $selected) { selection in
            let rows = selection.trackIDs.compactMap { library.track(id: $0) }
            VStack(alignment: .leading, spacing: 16) {
                Text(selection.title).font(.title2)
                Button("すべてキューに追加") {
                    Task { await queue.append(trackIDs: rows.filter { $0.scanState == .available }.map(\.id)) }
                }.disabled(!rows.contains { $0.scanState == .available })
                List(rows) { row in
                    HStack {
                        CachedArtwork(track: row, library: library, size: 36)
                        VStack(alignment: .leading) { Text(row.title); Text(row.artist ?? "").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("再生") { Task { await queue.playImmediately(trackID: row.id, source: .history) } }
                            .disabled(row.scanState != .available || !playback.canPlaySelectedOutput)
                        Button("キューに追加") { Task { await queue.append(trackIDs: [row.id]) } }.disabled(row.scanState != .available)
                    }
                }
                Button("閉じる") { selected = nil }
            }.padding(20).frame(minWidth: 560, minHeight: 420)
        }
    }

    private func rankingCard(_ title: String, rows: [AnalyticsRankingRow], byTime: Bool, tint: Color) -> some View {
        let maximum = rows.first.map { byTime ? $0.seconds : Double($0.playCount) } ?? 1
        return VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: byTime ? "clock" : "play.circle").font(.title2.bold()).foregroundStyle(tint)
            Text("上位\(rows.count)件").font(.caption).foregroundStyle(.secondary)
            if rows.isEmpty { Text("対象の再生データがありません").foregroundStyle(.secondary) }
            LazyVStack(spacing: 14) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let value = byTime ? row.seconds : Double(row.playCount)
                    Button { selected = row } label: {
                        HStack(spacing: 12) {
                            Text("\(index + 1)").font(.callout.bold().monospacedDigit()).frame(width: 24)
                                .foregroundStyle(index < 3 ? tint : .secondary)
                            if let id = row.artworkTrackID, let track = library.track(id: id) {
                                CachedArtwork(track: track, library: library, size: 44)
                            }
                            VStack(alignment: .leading, spacing: 7) {
                                Text(row.title).font(.callout.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                                Text(byTime ? duration(row.seconds) : "\(row.playCount)回")
                                    .font(.caption.bold().monospacedDigit()).foregroundStyle(tint)
                                GeometryReader { geometry in
                                    Capsule().fill(tint.opacity(0.12))
                                        .overlay(alignment: .leading) {
                                            Capsule().fill(tint.opacity(index < 3 ? 0.85 : 0.5))
                                                .frame(width: geometry.size.width * min(1, value / max(1, maximum)))
                                        }
                                }.frame(height: 6).accessibilityHidden(true)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .topLeading).homeStereoThemeSurface(cornerRadius: 14)
    }

    private func duration(_ value: Double) -> String {
        let minutes = Int(value / 60)
        if minutes == 0 { return "\(Int(value))秒" }
        return minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分"
    }
}
