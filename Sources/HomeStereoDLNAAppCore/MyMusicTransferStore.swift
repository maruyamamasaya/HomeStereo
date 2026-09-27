import Foundation
import CoreFoundation
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
    public let totalPlaylistTracks: Int?
    public let conflictedPlaylistTracks: Int?

    public var hasUnresolvedEventWarning: Bool { (unresolvedEvents ?? 0) > 0 }
}

public enum MyMusicTrackLinkFilter: String, CaseIterable, Sendable {
    case all
    case linked
    case currentSnapshot
    case missingFromSnapshot
    case unlinked
}

public struct MyMusicTrackApplicationRow: Identifiable, Equatable, Sendable {
    public let id: Track.ID
    public let title: String
    public let artist: String
    public let album: String
    public let relativePath: String
    public let isAvailable: Bool
    public let myMusicTrackID: UUID?
    public let myMusicRelativePath: String?
    public let isInCurrentSnapshot: Bool?
    public let matchMethod: MyMusicTrackMatchMethod?
    public let source: MyMusicLinkSource?
    public let matchedAt: Date?
    public let lastSeenAt: Date?
    public let playbackPreference: Int?
    public let isFavorite: Bool?
    public let myMusicPlayCount: Int?
    public let playbackEventCount: Int
    public let myMusicPlaylistNames: [String]

    public var isLinked: Bool { myMusicTrackID != nil }
    public var isLibraryJSONExportable: Bool { isLinked }
}

@MainActor
@Observable
public final class MyMusicStatusStore {
    public private(set) var rows: [MyMusicTrackApplicationRow] = []
    public private(set) var myMusicPlaylistCount = 0
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public var query = ""
    public var filter: MyMusicTrackLinkFilter = .all
    public var selectedTrackID: Track.ID?

    @ObservationIgnored private let repository: any MyMusicPersisting

    public init(repository: any MyMusicPersisting) {
        self.repository = repository
    }

    public var linkedCount: Int { rows.count { $0.isLinked } }
    public var currentSnapshotCount: Int { rows.count { $0.isInCurrentSnapshot == true } }
    public var missingFromSnapshotCount: Int { rows.count { $0.isInCurrentSnapshot == false } }
    public var unlinkedCount: Int { rows.count - linkedCount }
    public var selectedRow: MyMusicTrackApplicationRow? {
        guard let selectedTrackID else { return nil }
        return rows.first { $0.id == selectedTrackID }
    }
    public var visibleRows: [MyMusicTrackApplicationRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
        return rows.filter { row in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .linked: matchesFilter = row.isLinked
            case .currentSnapshot: matchesFilter = row.isInCurrentSnapshot == true
            case .missingFromSnapshot: matchesFilter = row.isInCurrentSnapshot == false
            case .unlinked: matchesFilter = !row.isLinked
            }
            guard matchesFilter, !needle.isEmpty else { return matchesFilter }
            return [
                row.title, row.artist, row.album, row.relativePath,
                row.id.uuidString, row.myMusicTrackID?.uuidString ?? ""
            ].contains { $0.precomposedStringWithCanonicalMapping.lowercased().contains(needle) }
        }
    }

    public func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let context = try await repository.loadMyMusicPlaylistContext()
            let preferences = try await repository.loadMyMusicPreferences()
            let events = try await repository.loadMyMusicPlaybackEvents()
            let playCounts = try await repository.loadMyMusicPlayCounts()
            myMusicPlaylistCount = context.playlists.count { $0.myMusicPlaylistID != nil }
            let linksByHomeID = Dictionary(uniqueKeysWithValues: context.links.map { ($0.homeStereoTrackID, $0) })
            let preferencesByHomeID = Dictionary(uniqueKeysWithValues: preferences.map { ($0.homeStereoTrackID, $0) })
            let playCountsByHomeID = Dictionary(uniqueKeysWithValues: playCounts.compactMap {
                value in value.homeStereoTrackID.map { ($0, value.playCount) }
            })
            let eventCounts = Dictionary(grouping: events, by: \.homeStereoTrackID).mapValues(\.count)
            var playlistNamesByTrackID: [Track.ID: [String]] = [:]
            for playlist in context.playlists where playlist.myMusicPlaylistID != nil {
                for trackID in Set(playlist.items.map(\.trackID)) {
                    playlistNamesByTrackID[trackID, default: []].append(playlist.name)
                }
            }
            rows = context.tracks.map { track in
                let link = linksByHomeID[track.id]
                let preference = preferencesByHomeID[track.id]
                return MyMusicTrackApplicationRow(
                    id: track.id, title: track.title, artist: track.artist ?? "",
                    album: track.album ?? "", relativePath: track.relativePath,
                    isAvailable: track.scanState == .available,
                    myMusicTrackID: link?.myMusicTrackID,
                    myMusicRelativePath: link?.relativePath,
                    isInCurrentSnapshot: link?.isInCurrentSnapshot,
                    matchMethod: link?.matchMethod, source: link?.source,
                    matchedAt: link?.matchedAt, lastSeenAt: link?.lastSeenAt,
                    playbackPreference: preference?.playbackPreference,
                    isFavorite: preference?.favorite,
                    myMusicPlayCount: playCountsByHomeID[track.id],
                    playbackEventCount: eventCounts[track.id, default: 0],
                    myMusicPlaylistNames: (playlistNamesByTrackID[track.id] ?? []).sorted()
                )
            }.sorted {
                let artistOrder = $0.artist.localizedStandardCompare($1.artist)
                if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            if let selectedTrackID, !rows.contains(where: { $0.id == selectedTrackID }) {
                self.selectedTrackID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
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
    @ObservationIgnored private let afterImportApplied: @MainActor @Sendable (MyMusicDocumentKind) async -> Void
    @ObservationIgnored private var pendingData: Data?
    @ObservationIgnored private var pendingKind: MyMusicDocumentKind?

    public init(
        repository: any MyMusicPersisting, files: any MyMusicFileServicing,
        afterImportApplied: @escaping @MainActor @Sendable (MyMusicDocumentKind) async -> Void = { _ in }
    ) {
        self.transfer = MyMusicTransferService(repository: repository)
        self.files = files
        self.afterImportApplied = afterImportApplied
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
            await afterImportApplied(pendingKind)
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
                exportedEvents: value.exported, unresolvedEvents: value.unresolved,
                totalPlaylistTracks: value.total, conflictedPlaylistTracks: value.conflicts
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
        case .playlists:
            return " 追加プレイリスト \(preview.addedPlaylists)件、更新 \(preview.updatedPlaylists)件、登録曲 \(preview.importedTracks)件、未解決 \(preview.unresolved)件、競合 \(preview.conflicts)件。"
        }
    }
}

public enum MyMusicJSONEditorFieldKind: String, Sendable {
    case string = "文字列"
    case number = "数値"
    case boolean = "真偽値"
    case null = "null"
}

public struct MyMusicJSONEditorField: Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let kind: MyMusicJSONEditorFieldKind
    public let value: String
    fileprivate let components: [MyMusicJSONPathComponent]
    fileprivate let isRoot: Bool
}

public struct MyMusicJSONEditorRecord: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let detail: String
}

private enum MyMusicJSONPathComponent: Hashable, Sendable {
    case key(String)
    case index(Int)
}

private indirect enum MyMusicEditableJSON: Equatable, Sendable {
    case object([String: MyMusicEditableJSON])
    case array([MyMusicEditableJSON])
    case string(String)
    case number(String)
    case boolean(Bool)
    case null

    init(any value: Any) throws {
        switch value {
        case let value as [String: Any]:
            self = .object(try value.mapValues(Self.init(any:)))
        case let value as [Any]:
            self = .array(try value.map(Self.init(any:)))
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .boolean(value.boolValue)
            } else {
                self = .number(value.stringValue)
            }
        case _ as NSNull:
            self = .null
        default:
            throw MyMusicJSONEditorError.unsupportedValue
        }
    }

    func foundationValue() throws -> Any {
        switch self {
        case let .object(value): return try value.mapValues { try $0.foundationValue() }
        case let .array(value): return try value.map { try $0.foundationValue() }
        case let .string(value): return value
        case let .boolean(value): return value
        case .null: return NSNull()
        case let .number(value):
            if !value.contains("."), !value.localizedCaseInsensitiveContains("e"), let integer = Int64(value) {
                return NSNumber(value: integer)
            }
            guard let number = Double(value), number.isFinite else {
                throw MyMusicJSONEditorError.invalidNumber(value)
            }
            return NSNumber(value: number)
        }
    }

    func replacing(path: ArraySlice<MyMusicJSONPathComponent>, with value: MyMusicEditableJSON) -> Self {
        guard let component = path.first else { return value }
        let remainder = path.dropFirst()
        switch (self, component) {
        case (let .object(object), let .key(key)):
            guard let child = object[key] else { return self }
            var copy = object
            copy[key] = child.replacing(path: remainder, with: value)
            return .object(copy)
        case (let .array(array), let .index(index)) where array.indices.contains(index):
            var copy = array
            copy[index] = copy[index].replacing(path: remainder, with: value)
            return .array(copy)
        default:
            return self
        }
    }
}

private enum MyMusicJSONEditorError: LocalizedError {
    case invalidRoot
    case missingCollection(String)
    case unsupportedValue
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "JSONのルートがオブジェクトではありません。"
        case let .missingCollection(key): "JSONに\(key)配列がありません。"
        case .unsupportedValue: "JSONに編集できない値が含まれています。"
        case let .invalidNumber(value): "「\(value)」は有効な数値ではありません。"
        }
    }
}

@MainActor
@Observable
public final class MyMusicJSONEditorStore {
    public var kind: MyMusicDocumentKind = .library
    public var query = ""
    public var selectedRecordID: Int?
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var completedMessage: String?

    @ObservationIgnored private let transfer: MyMusicTransferService
    @ObservationIgnored private let files: any MyMusicFileServicing
    private var document: MyMusicEditableJSON?

    public init(repository: any MyMusicPersisting, files: any MyMusicFileServicing) {
        transfer = MyMusicTransferService(repository: repository)
        self.files = files
    }

    public var hasDocument: Bool { document != nil }

    public var records: [MyMusicJSONEditorRecord] {
        guard case let .object(root) = document,
              case let .array(values) = root[collectionKey] else { return [] }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return values.enumerated().compactMap { index, value in
            let record = Self.record(index: index, value: value)
            guard needle.isEmpty || record.title.lowercased().contains(needle)
                    || record.detail.lowercased().contains(needle) else { return nil }
            return record
        }
    }

    public var rootFields: [MyMusicJSONEditorField] {
        guard case let .object(root) = document else { return [] }
        return root.keys.sorted().filter { $0 != collectionKey }.flatMap { key in
            Self.fields(in: root[key] ?? .null, path: [.key(key)], isRoot: true)
        }
    }

    public var selectedFields: [MyMusicJSONEditorField] {
        guard let selectedRecordID,
              case let .object(root) = document,
              case let .array(values) = root[collectionKey],
              values.indices.contains(selectedRecordID) else { return [] }
        return Self.fields(in: values[selectedRecordID], path: [], isRoot: false)
    }

    public func createFromCurrentValues() async {
        await loadOperation {
            let value = try await transfer.export(kind)
            try setDocument(value.data)
        }
    }

    public func openExistingFile() async {
        guard !isBusy, let url = files.chooseImportURL() else { return }
        await loadOperation {
            let data = try files.read(from: url)
            _ = try await transfer.preview(data, as: kind)
            try setDocument(data)
        }
    }

    public func save() async {
        guard !isBusy, let document else { return }
        isBusy = true; errorMessage = nil; completedMessage = nil
        defer { isBusy = false }
        do {
            let object = try document.foundationValue()
            guard JSONSerialization.isValidJSONObject(object) else { throw MyMusicJSONEditorError.invalidRoot }
            let data = try JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            _ = try await transfer.preview(data, as: kind)
            guard let url = files.chooseExportURL(defaultFileName: kind.fileName) else { return }
            try files.write(data, to: url)
            completedMessage = "\(kind.fileName)を書き出しました。"
        } catch {
            errorMessage = "保存できませんでした。\n\(error.localizedDescription)"
        }
    }

    public func changeKind(to value: MyMusicDocumentKind) {
        guard kind != value else { return }
        kind = value; clearDocument()
    }

    public func update(_ field: MyMusicJSONEditorField, text: String) {
        let replacement: MyMusicEditableJSON
        switch field.kind {
        case .string: replacement = .string(text)
        case .number: replacement = .number(text)
        case .boolean: replacement = .boolean(text == "true")
        case .null: return
        }
        replace(field, with: replacement)
    }

    public func update(_ field: MyMusicJSONEditorField, boolean: Bool) {
        guard field.kind == .boolean else { return }
        replace(field, with: .boolean(boolean))
    }

    public func dismissMessage() {
        errorMessage = nil; completedMessage = nil
    }

    private var collectionKey: String {
        switch kind {
        case .library, .preferences: "tracks"
        case .playbackEvents: "events"
        case .playlists: "playlists"
        }
    }

    private func loadOperation(_ operation: () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil; completedMessage = nil
        defer { isBusy = false }
        do { try await operation() }
        catch { errorMessage = "JSONを準備できませんでした。\n\(error.localizedDescription)" }
    }

    private func setDocument(_ data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        let value = try MyMusicEditableJSON(any: object)
        guard case let .object(root) = value else { throw MyMusicJSONEditorError.invalidRoot }
        if kind == .playlists, root[collectionKey] == nil, root["tracks"] != nil {
            document = .object([
                "version": root["version"] ?? .number("1"),
                collectionKey: .array([value])
            ])
            selectedRecordID = 0
            query = ""
            return
        }
        guard case .array = root[collectionKey] else {
            throw MyMusicJSONEditorError.missingCollection(collectionKey)
        }
        document = value
        selectedRecordID = records.first?.id
        query = ""
    }

    private func clearDocument() {
        document = nil; selectedRecordID = nil; query = ""
        errorMessage = nil; completedMessage = nil
    }

    private func replace(_ field: MyMusicJSONEditorField, with value: MyMusicEditableJSON) {
        guard let document else { return }
        var path = field.components
        if !field.isRoot {
            guard let selectedRecordID else { return }
            path = [.key(collectionKey), .index(selectedRecordID)] + path
        }
        self.document = document.replacing(path: path[...], with: value)
        errorMessage = nil; completedMessage = nil
    }

    private static func fields(
        in value: MyMusicEditableJSON, path: [MyMusicJSONPathComponent], isRoot: Bool
    ) -> [MyMusicJSONEditorField] {
        switch value {
        case let .object(object):
            return object.keys.sorted().flatMap { key in
                fields(in: object[key] ?? .null, path: path + [.key(key)], isRoot: isRoot)
            }
        case let .array(array):
            return array.indices.flatMap { index in
                fields(in: array[index], path: path + [.index(index)], isRoot: isRoot)
            }
        case let .string(value): return [field(path, .string, value, isRoot: isRoot)]
        case let .number(value): return [field(path, .number, value, isRoot: isRoot)]
        case let .boolean(value): return [field(path, .boolean, value ? "true" : "false", isRoot: isRoot)]
        case .null: return [field(path, .null, "null", isRoot: isRoot)]
        }
    }

    private static func field(
        _ path: [MyMusicJSONPathComponent], _ kind: MyMusicJSONEditorFieldKind, _ value: String,
        isRoot: Bool
    ) -> MyMusicJSONEditorField {
        let display = displayPath(path)
        return MyMusicJSONEditorField(
            id: "\(isRoot ? "root" : "record"):\(display)", path: display,
            kind: kind, value: value, components: path, isRoot: isRoot
        )
    }

    private static func displayPath(_ path: [MyMusicJSONPathComponent]) -> String {
        path.reduce(into: "") { result, component in
            switch component {
            case let .key(key): result += result.isEmpty ? key : ".\(key)"
            case let .index(index): result += "[\(index)]"
            }
        }
    }

    private static func record(index: Int, value: MyMusicEditableJSON) -> MyMusicJSONEditorRecord {
        guard case let .object(object) = value else {
            return MyMusicJSONEditorRecord(id: index, title: "項目 \(index + 1)", detail: "")
        }
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if case let .string(value) = object[key], !value.isEmpty { return value }
            }
            return nil
        }
        let title = string(["title", "trackTitle", "name", "eventId"]) ?? "項目 \(index + 1)"
        let detail = [
            string(["artist"]), string(["album"]),
            string(["trackID", "trackId", "playlistID"])
        ].compactMap { $0 }.joined(separator: " — ")
        return MyMusicJSONEditorRecord(id: index, title: title, detail: detail)
    }
}
