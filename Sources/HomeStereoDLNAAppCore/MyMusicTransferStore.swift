import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

public enum MyMusicTransferState: String, Equatable, Sendable {
    case idle, reading, validating, preview, applying, exporting, completed, failed
}

public struct MyMusicExportResult: Equatable, Sendable {
    public let kind: MyMusicDocumentKind
    public let destination: String
    public let exportedEvents: Int?
    public let unresolvedEvents: Int?

    public var hasUnresolvedEventWarning: Bool { (unresolvedEvents ?? 0) > 0 }
}

@MainActor
@Observable
public final class MyMusicTransferStore {
    public private(set) var state: MyMusicTransferState = .idle
    public private(set) var preview: MyMusicImportPreview?
    public private(set) var exportResult: MyMusicExportResult?
    public private(set) var completedMessage: String?
    public private(set) var errorMessage: String?

    @ObservationIgnored private let transfer: MyMusicTransferService
    @ObservationIgnored private let files: any MyMusicFileServicing
    @ObservationIgnored private var pendingData: Data?
    @ObservationIgnored private var pendingKind: MyMusicDocumentKind?

    public init(repository: any MyMusicPersisting, files: any MyMusicFileServicing) {
        self.transfer = MyMusicTransferService(repository: repository)
        self.files = files
    }

    public var isBusy: Bool {
        [.reading, .validating, .applying, .exporting].contains(state)
    }

    public func selectImport(_ kind: MyMusicDocumentKind) async {
        guard canStart else { return }
        guard let url = files.chooseImportURL() else { return }
        guard url.pathExtension.lowercased() == "json" else {
            fail("JSONファイル（.json）を選択してください。")
            return
        }
        state = .reading; clearOutput()
        do {
            let data = try files.read(from: url)
            await prepareImport(kind, data: data)
        } catch {
            fail("ファイルを読み込めませんでした。アクセス権とファイルの状態を確認してください。\n\(error.localizedDescription)")
        }
    }

    public func prepareImport(_ kind: MyMusicDocumentKind, data: Data) async {
        guard canStart || state == .reading else { return }
        state = .validating; clearOutput()
        do {
            let value = try await transfer.preview(data, as: kind)
            pendingData = data; pendingKind = kind; preview = value; state = .preview
        } catch { fail(Self.userMessage(for: error, phase: .validating)) }
    }

    public func applyImport() async {
        guard state == .preview, let pendingData, let pendingKind else { return }
        let appliedPreview = preview
        state = .applying; errorMessage = nil
        do {
            try await transfer.apply(pendingData, as: pendingKind)
            self.pendingData = nil; self.pendingKind = nil; preview = nil
            completedMessage = "\(pendingKind.fileName)を読み込みました。\(Self.resultSummary(appliedPreview))"
            state = .completed
        } catch { fail(Self.userMessage(for: error, phase: .applying)) }
    }

    public func cancelImport() {
        guard state == .preview else { return }
        pendingData = nil; pendingKind = nil; preview = nil; state = .idle
    }

    public func export(_ kind: MyMusicDocumentKind) async {
        guard canStart else { return }
        guard let url = files.chooseExportURL(defaultFileName: kind.fileName) else { return }
        state = .exporting; clearOutput()
        do {
            let value = try await transfer.export(kind)
            do { try files.write(value.data, to: url) }
            catch {
                fail("保存先へ書き込めませんでした。保存先のアクセス権や空き容量を確認してください。\n\(error.localizedDescription)")
                return
            }
            exportResult = MyMusicExportResult(
                kind: kind, destination: url.path,
                exportedEvents: value.exported, unresolvedEvents: value.unresolved
            )
            completedMessage = "\(kind.fileName)を書き出しました。"
            state = .completed
        } catch { fail(Self.userMessage(for: error, phase: .exporting)) }
    }

    public func dismissResult() {
        guard !isBusy else { return }
        clearOutput(); pendingData = nil; pendingKind = nil; state = .idle
    }

    private var canStart: Bool { !isBusy && state != .preview }

    private func clearOutput() {
        preview = nil; exportResult = nil; completedMessage = nil; errorMessage = nil
    }

    private func fail(_ message: String) {
        pendingData = nil; pendingKind = nil; preview = nil
        errorMessage = message; state = .failed
    }

    private static func userMessage(for error: Error, phase: MyMusicTransferState) -> String {
        if let value = error as? MyMusicTransferServiceError { return value.localizedDescription }
        if case let MyMusicJSONContractError.unsupportedVersion(version) = error {
            return "このMyMusic JSONのversion（\(version)）には対応していません。対応するversionで書き出し直してください。"
        }
        if case let MyMusicJSONContractError.invalidStructure(reason) = error {
            if reason.contains("UTF-8") { return "UTF-8のJSONファイルではありません。文字コードをUTF-8にしてください。" }
            if reason.contains("UTC") || reason.contains("日時") { return "日時の形式が不正です。UTC ISO 8601形式が必要です。\n\(reason)" }
            if reason.localizedCaseInsensitiveContains("uuid") { return "trackIDのUUID形式が不正です。\n\(reason)" }
            if reason.contains("必要") || reason.contains("0以上") || reason.contains("未対応") {
                return "JSON内の値が許容範囲外です。\n\(reason)"
            }
            return "JSONの構造または内容が不正です。選択した文書種別を確認してください。\n\(reason)"
        }
        if phase == .applying {
            return "SQLiteへ保存できませんでした。変更は反映されていません。\n\(error.localizedDescription)"
        }
        return "MyMusic JSONの処理に失敗しました。\n\(error.localizedDescription)"
    }

    private static func resultSummary(_ preview: MyMusicImportPreview?) -> String {
        guard let preview else { return "" }
        switch preview.kind {
        case .library:
            return " 接続追加 \(preview.newlyLinked)件、更新 \(preview.matched)件、未照合 \(preview.unmatched)件、曖昧 \(preview.ambiguous)件。"
        case .preferences:
            return " 更新 \(preview.pendingUpdates)件、変更なし \(preview.unchanged)件、未解決 \(preview.unresolved)件。"
        case .playbackEvents:
            return " 追加 \(preview.pendingInserts)件、重複 \(preview.duplicates)件、未解決 \(preview.unresolved)件。"
        }
    }
}
