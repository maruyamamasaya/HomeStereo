import Foundation
import Observation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif

public struct FeatureBatch: Hashable, Identifiable, Sendable {
    public let version: Int
    public let date: Date
    public var id: String { "\(version):\(date.timeIntervalSince1970)" }
}

@MainActor
@Observable
public final class TrackFeatureStore {
    public private(set) var revision = 0
    public private(set) var rows: [FeatureResolution] = [] { didSet { revision += 1 } }
    public private(set) var preview: [FeatureResolution]?
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var message: String?
    public private(set) var analysisProgress: FeatureAnalysisProgress?
    public private(set) var missingCount = 0
    public private(set) var missingLoudnessCount = 0
    public private(set) var updateCount = 0
    public var analysisConcurrency: FeatureAnalysisConcurrency {
        didSet { defaults.set(analysisConcurrency.rawValue, forKey: "analysis.concurrency") }
    }
    public var normalizationEnabled: Bool {
        didSet { defaults.set(normalizationEnabled, forKey: "audio.normalization.enabled"); publishPlaybackFeatures() }
    }
    @ObservationIgnored public var onPlaybackFeatures: (@MainActor ([UUID: FeatureValues], Bool) -> Void)?
    public private(set) var canonicalHomeCounts: [UUID: Int] = [:]
    public private(set) var linkedIDs: [UUID: Set<UUID>] = [:]
    public var query = ""
    public var selectedID: UUID?
    public var selectedBatch: FeatureBatch?
    public var batches: [FeatureBatch] {
        Dictionary(grouping: rows, by: { $0.record.analysisVersion }).map { version, rows in
            FeatureBatch(version: version, date: rows.map { $0.record.analyzedAt }.max() ?? .distantPast)
        }.sorted { $0.version > $1.version }
    }
    @ObservationIgnored private let library: any MyMusicPersisting
    @ObservationIgnored private let archive: FeatureRepository
    @ObservationIgnored private let files: any MyMusicFileServicing
    @ObservationIgnored private let analyzer: any FeatureAnalysisRunning
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var pending: [FeatureRecord]?

    public init(library: any MyMusicPersisting, archive: FeatureRepository, files: any MyMusicFileServicing, analyzer: (any FeatureAnalysisRunning)? = nil, defaults: UserDefaults = .standard) {
        self.library = library; self.archive = archive; self.files = files
        self.analyzer = analyzer ?? FeatureAnalysisService(); self.defaults = defaults
        self.analysisConcurrency = FeatureAnalysisConcurrency(rawValue: defaults.integer(forKey: "analysis.concurrency")) ?? .three
        self.normalizationEnabled = defaults.bool(forKey: "audio.normalization.enabled")
    }
    public var exportableCount: Int { rows.filter { $0.record.trackID != nil }.count }
    public var matchedCount: Int { rows.filter { $0.localTrackID != nil }.count }
    public var selected: FeatureResolution? { rows.first { $0.id == selectedID } }

    public func load() async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let recovered = try await analyzer.recover()
            if !recovered.isEmpty {
                let context = try await library.loadMyMusicMatchContext()
                _ = try await archive.merge(recovered, tracks: context.tracks, links: context.links)
            }
            rows = try await resolve(archive.load()); try await refreshCounts(); publishPlaybackFeatures()
        }
        catch { errorMessage = error.localizedDescription }
    }
    private func resolve(_ records: [FeatureRecord]) async throws -> [FeatureResolution] {
        let context = try await library.loadMyMusicMatchContext()
        canonicalHomeCounts = Dictionary(grouping: context.links, by: \.myMusicTrackID).mapValues { Set($0.map(\.homeStereoTrackID)).count }
        linkedIDs = Dictionary(grouping: context.links, by: \.homeStereoTrackID).mapValues { Set($0.map(\.myMusicTrackID)) }
        return await Task.detached(priority: .userInitiated) {
            let resolver = FeatureResolver(tracks: context.tracks, links: context.links)
            return records.map { resolver.resolve($0) }.sorted {
                ($0.record.title ?? $0.record.sourceIdentity.relativePath).localizedStandardCompare($1.record.title ?? $1.record.sourceIdentity.relativePath) == .orderedAscending
            }
        }.value
    }
    public func chooseImport() async {
        guard !isBusy, let url = files.chooseImportURL() else { return }
        isBusy = true; errorMessage = nil; message = nil; pending = nil; preview = nil
        defer { isBusy = false }
        do {
            let records = try await Task.detached(priority: .userInitiated) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try FeatureCodec.decode(Data(contentsOf: url), fileName: url.lastPathComponent)
            }.value
            preview = try await resolve(records); pending = records
        } catch { errorMessage = error.localizedDescription }
    }
    public func cancelPreview() { guard !isBusy else { return }; pending = nil; preview = nil }
    public func applyImport() async {
        guard !isBusy, let pending else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            let context = try await library.loadMyMusicMatchContext()
            let records = try await archive.merge(pending, tracks: context.tracks, links: context.links)
            rows = try await resolve(records)
            try await refreshCounts(); publishPlaybackFeatures()
            self.pending = nil; preview = nil
            message = "取り込み完了：保存済み \(records.count)件。未照合データも保持しています。"
        } catch { errorMessage = error.localizedDescription }
    }
    public func publishPlaybackFeatures() {
        var values: [UUID: FeatureValues] = [:]
        for row in rows { if let id = row.localTrackID { values[id] = row.record.features } }
        onPlaybackFeatures?(values, normalizationEnabled)
    }
    private func refreshCounts() async throws {
        let context = try await library.loadMyMusicMatchContext()
        let records = rows.map(\.record)
        let counts = await Task.detached {
            [FeatureAnalysisMode.missing, .loudness, .update].map {
                FeatureAnalysisPlanner.tasks(mode: $0, tracks: context.tracks, links: context.links, records: records).count
            }
        }.value
        missingCount = counts[0]; missingLoudnessCount = counts[1]; updateCount = counts[2]
    }
    public func analyze(_ mode: FeatureAnalysisMode) async {
        guard !isBusy, preview == nil else { return }
        isBusy = true; errorMessage = nil; message = nil; analysisProgress = nil
        defer { isBusy = false }
        let concurrency = analysisConcurrency.rawValue
        do {
            let context = try await library.loadMyMusicMatchContext()
            let records = try await archive.load()
            let tasks = await Task.detached {
                FeatureAnalysisPlanner.tasks(mode: mode, tracks: context.tracks, links: context.links, records: records)
            }.value
            guard !tasks.isEmpty else { message = "解析対象はありません。"; return }
            let result = try await analyzer.run(tasks: tasks, concurrency: concurrency) { [weak self] progress in self?.analysisProgress = progress }
            let saved = try await archive.merge(result, tracks: context.tracks, links: context.links)
            rows = try await resolve(saved); try await refreshCounts(); publishPlaybackFeatures()
            message = "解析完了：保存 \(result.count)件、失敗 \(analysisProgress?.failed ?? 0)件。完了済みの処理は次回再利用します。"
            if analysisProgress?.state == "interrupted" { message = "解析が途中で終了しました。完了済み \(result.count)件を保存しました。残りは再実行できます。" }
            if analysisProgress?.state == "cancelled" { message = "中断しました。完了済み \(result.count)件を保存しました。" }
        } catch { errorMessage = error.localizedDescription }
    }
    public func cancelAnalysis() async {
        do { try await analyzer.cancel() }
        catch { errorMessage = error.localizedDescription }
    }
    public func exportAnalyzer() async {
        guard !isBusy, let batch = selectedBatch ?? batches.first,
              let url = files.chooseExportURL(defaultFileName: "music_features_v\(batch.version).json") else { return }
        isBusy = true; errorMessage = nil; message = nil
        defer { isBusy = false }
        let records = rows.map(\.record).filter { $0.analysisVersion == batch.version }
        do {
            let data = try await Task.detached { try FeatureCodec.exportAnalyzer(records) }.value
            try files.write(data, to: url)
            message = "iPhone読み込み用JSONを書き出しました：\(records.count)件。"
        } catch { errorMessage = error.localizedDescription }
    }
    public func exportSnapshot() async {
        guard !isBusy, exportableCount > 0, let url = files.chooseExportURL(defaultFileName: "MyMusic-Track-Features.json") else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        let records = rows.map(\.record)
        do {
            let data = try await Task.detached { try FeatureCodec.exportSnapshot(records) }.value
            try files.write(data, to: url)
            message = "書き出し完了：\(exportableCount)件。MyMusic IDのない \(rows.count - exportableCount)件は対象外です。"
        } catch { errorMessage = error.localizedDescription }
    }
}
