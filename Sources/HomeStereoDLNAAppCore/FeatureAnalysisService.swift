import AppKit
import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif

@MainActor
public protocol FeatureAnalysisRunning: AnyObject {
    func run(tasks: [FeatureAnalysisTask], concurrency: Int, progress: @escaping @MainActor (FeatureAnalysisProgress) -> Void) async throws -> [FeatureRecord]
    func cancel() async throws
    func recover() async throws -> [FeatureRecord]
}

public extension FeatureAnalysisRunning {
    func recover() async throws -> [FeatureRecord] { [] }
}

actor FeatureRunFiles {
    struct Request: Encodable { let version = 1; let tasks: [FeatureAnalysisTask]; let concurrency: Int }
    struct Results: Decodable { let version: Int; let records: [FeatureRecord] }
    func create(tasks: [FeatureAnalysisTask], concurrency: Int) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("HomeStereo/AnalysisRuns/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FeatureCodec.encoder().encode(Request(tasks: tasks, concurrency: concurrency)).write(to: directory.appendingPathComponent("request.json"), options: .atomic)
        return directory
    }
    func status(_ directory: URL) throws -> FeatureAnalysisProgress? {
        let url = directory.appendingPathComponent("status.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(FeatureAnalysisProgress.self, from: Data(contentsOf: url))
    }
    func results(_ directory: URL) throws -> [FeatureRecord] {
        let result = try FeatureCodec.decoder().decode(Results.self, from: Data(contentsOf: directory.appendingPathComponent("results.json")))
        guard result.version == 1 else { throw FeatureError.invalid("解析結果の版が不正です。") }
        for record in result.records { try FeatureCodec.validate(record) }
        return result.records
    }
    func partial(_ directory: URL) throws -> [FeatureRecord] {
        let url = directory.appendingPathComponent("completed.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        // Ignore an incomplete final line left by an interrupted write.
        let lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        return try lines.filter { !$0.isEmpty }.map {
            let record = try FeatureCodec.decoder().decode(FeatureRecord.self, from: Data($0))
            try FeatureCodec.validate(record)
            return record
        }
    }
    func recover() throws -> [FeatureRecord] {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("HomeStereo/AnalysisRuns")
        guard FileManager.default.fileExists(atPath: base.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            .flatMap { try partial($0) }
    }
    func cancel(_ directory: URL) throws { try Data().write(to: directory.appendingPathComponent("cancel"), options: .atomic) }
    func remove(_ directory: URL) throws { try FileManager.default.removeItem(at: directory) }
}

@MainActor
public final class FeatureAnalysisService: FeatureAnalysisRunning {
    private let files = FeatureRunFiles()
    private var directory: URL?
    public init() {}
    public func run(tasks: [FeatureAnalysisTask], concurrency: Int = 3, progress: @escaping @MainActor (FeatureAnalysisProgress) -> Void) async throws -> [FeatureRecord] {
        guard FeatureAnalysisConcurrency(rawValue: concurrency) != nil else { throw FeatureError.invalid("同時解析数は2曲・3曲・6曲から選んでください。") }
        guard directory == nil else { throw FeatureError.invalid("解析が実行中です。") }
        let app = URL(fileURLWithPath: "/Applications/HomeStereoAnalyzer.app")
        guard FileManager.default.fileExists(atPath: app.path) else { throw FeatureError.invalid("解析用補助アプリが未導入です。HomeStereo Analyzerをインストールしてください。") }
        let runDirectory = try await files.create(tasks: tasks, concurrency: concurrency)
        directory = runDirectory
        defer { directory = nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        do {
            let application = try await NSWorkspace.shared.open([runDirectory.appendingPathComponent("request.json")], withApplicationAt: app, configuration: configuration)
            let started = Date()
            var terminatedPolls = 0
            while true {
                if let state = try await files.status(runDirectory) {
                    progress(state)
                    if state.state == "failed" { throw FeatureError.invalid("解析を開始できませんでした：\(state.message)") }
                    if state.state == "completed" || state.state == "cancelled" {
                        let records = try await files.results(runDirectory)
                        try await files.remove(runDirectory)
                        return records
                    }
                } else if Date().timeIntervalSince(started) > 30 {
                    throw FeatureError.invalid("解析用補助アプリが応答しません。")
                }
                terminatedPolls = application.isTerminated ? terminatedPolls + 1 : 0
                if terminatedPolls > 2 { throw FeatureError.invalid("解析用補助アプリが途中で終了しました。完了済みのキャッシュを保持しています。") }
                try await Task.sleep(for: .seconds(1))
            }
        } catch {
            try? await files.cancel(runDirectory)
            // Keep interrupted results for diagnosis/recovery; the independent SQLite cache retains completed work.
            let records = try await files.partial(runDirectory)
            if !records.isEmpty {
                progress(FeatureAnalysisProgress(state: "interrupted", completed: records.count, total: tasks.count, failed: 0, message: error.localizedDescription))
                return records
            }
            throw error
        }
    }
    public func recover() async throws -> [FeatureRecord] { try await files.recover() }
    public func cancel() async throws {
        if let directory { try await files.cancel(directory) }
    }
}
