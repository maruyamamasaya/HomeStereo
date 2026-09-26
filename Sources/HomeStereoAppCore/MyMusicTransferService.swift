import Foundation

public enum MyMusicDocumentKind: String, CaseIterable, Sendable {
    case library, preferences, playbackEvents

    public var fileName: String {
        switch self {
        case .library: MyMusicJSONCodec.libraryFileName
        case .preferences: MyMusicJSONCodec.preferencesFileName
        case .playbackEvents: MyMusicJSONCodec.playbackEventsFileName
        }
    }
}

public struct MyMusicImportPreviewDetail: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let trackID: UUID
    public let result: String
    public let reason: String?
}

public struct MyMusicImportPreview: Equatable, Sendable {
    public let kind: MyMusicDocumentKind
    public let total: Int
    public let matched: Int
    public let newlyLinked: Int
    public let unchanged: Int
    public let unmatched: Int
    public let ambiguous: Int
    public let invalid: Int
    public let pendingUpdates: Int
    public let pendingInserts: Int
    public let duplicates: Int
    public let unresolved: Int
    public let details: [MyMusicImportPreviewDetail]
}

public enum MyMusicTransferServiceError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case malformedJSON
    case wrongDocumentType(expected: MyMusicDocumentKind)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "UTF-8で保存されたJSONファイルではありません。文字コードをUTF-8にして書き出し直してください。"
        case .malformedJSON:
            "JSONの構文が正しくありません。ファイルが途中で切れていないか確認してください。"
        case let .wrongDocumentType(expected):
            "選択したファイルは\(expected.fileName)の文書構造ではありません。"
        }
    }
}

public struct MyMusicTransferService: Sendable {
    private let repository: any MyMusicPersisting
    private let persistence: MyMusicPersistenceService
    private let clock: @Sendable () -> Date

    public init(repository: any MyMusicPersisting, clock: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository
        self.persistence = MyMusicPersistenceService(repository: repository, clock: clock)
        self.clock = clock
    }

    public func preview(_ data: Data, as kind: MyMusicDocumentKind) async throws -> MyMusicImportPreview {
        try validateRoot(data, expected: kind)
        switch kind {
        case .library: return try await previewLibrary(data)
        case .preferences: return try await previewPreferences(data)
        case .playbackEvents: return try await previewPlaybackEvents(data)
        }
    }

    public func apply(_ data: Data, as kind: MyMusicDocumentKind) async throws {
        switch kind {
        case .library: _ = try await persistence.importLibrary(data)
        case .preferences: _ = try await persistence.importPreferences(data)
        case .playbackEvents: _ = try await persistence.importPlaybackEvents(data)
        }
    }

    public func export(_ kind: MyMusicDocumentKind) async throws -> (data: Data, exported: Int?, unresolved: Int?) {
        switch kind {
        case .library:
            return (try await persistence.exportLibrary(), nil, nil)
        case .preferences:
            return (try await persistence.exportPreferences(exportedAt: clock()), nil, nil)
        case .playbackEvents:
            let result = try await persistence.exportPlaybackEventsWithReport(exportedAt: clock())
            return (result.data, result.exported, result.unresolved)
        }
    }

    private func previewLibrary(_ data: Data) async throws -> MyMusicImportPreview {
        let document = try MyMusicJSONImportService().importLibrary(data)
        let context = try await repository.loadMyMusicMatchContext()
        let match = MyMusicLibraryMatcher.match(
            document.tracks, tracks: context.tracks, links: context.links, matchedAt: clock()
        )
        let records = Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.trackID, $0) })
        return MyMusicImportPreview(
            kind: .library, total: document.tracks.count,
            matched: match.result.matched, newlyLinked: match.result.newlyLinked,
            unchanged: match.result.unchanged, unmatched: match.result.unmatched,
            ambiguous: match.result.ambiguous, invalid: match.result.invalid,
            pendingUpdates: 0, pendingInserts: 0, duplicates: 0, unresolved: 0,
            details: match.result.items.prefix(100).map { item in
                let record = records[item.myMusicTrackID]
                return MyMusicImportPreviewDetail(
                    id: item.myMusicTrackID.uuidString, title: record?.title ?? "不明な曲",
                    artist: record?.artist ?? "", trackID: item.myMusicTrackID,
                    result: item.status.rawValue, reason: item.detail
                )
            }
        )
    }

    private func previewPreferences(_ data: Data) async throws -> MyMusicImportPreview {
        let document = try MyMusicJSONImportService().importPreferences(data)
        let context = try await repository.loadMyMusicMatchContext()
        let existing = Dictionary(uniqueKeysWithValues: try await repository.loadMyMusicPreferences().map {
            ($0.myMusicTrackID, $0)
        })
        let links = Dictionary(uniqueKeysWithValues: context.links.map { ($0.myMusicTrackID, $0.homeStereoTrackID) })
        let tracks = Dictionary(uniqueKeysWithValues: context.tracks.map { ($0.id, $0) })
        var updates = 0, unchanged = 0, unresolved = 0
        let details = document.tracks.prefix(100).map { value -> MyMusicImportPreviewDetail in
            let homeID = links[value.trackID]
            let track = homeID.flatMap { tracks[$0] }
            let result: String
            let reason: String?
            if homeID == nil {
                unresolved += 1; result = "unresolved"; reason = "MyMusic trackIDに対応する曲がありません"
            } else if let old = existing[value.trackID],
                      old.playbackPreference == value.playbackPreference, old.favorite == value.favorite {
                unchanged += 1; result = "unchanged"; reason = nil
            } else {
                updates += 1; result = "update"; reason = nil
            }
            return MyMusicImportPreviewDetail(
                id: value.trackID.uuidString, title: track?.title ?? "未解決の曲",
                artist: track?.artist ?? "", trackID: value.trackID, result: result, reason: reason
            )
        }
        // Summary must cover all rows, including rows beyond the displayed first 100.
        if document.tracks.count > details.count {
            for value in document.tracks.dropFirst(details.count) {
                if links[value.trackID] == nil { unresolved += 1 }
                else if let old = existing[value.trackID],
                        old.playbackPreference == value.playbackPreference, old.favorite == value.favorite { unchanged += 1 }
                else { updates += 1 }
            }
        }
        return MyMusicImportPreview(
            kind: .preferences, total: document.tracks.count, matched: 0, newlyLinked: 0,
            unchanged: unchanged, unmatched: 0, ambiguous: 0, invalid: 0,
            pendingUpdates: updates, pendingInserts: 0, duplicates: 0, unresolved: unresolved,
            details: details
        )
    }

    private func previewPlaybackEvents(_ data: Data) async throws -> MyMusicImportPreview {
        let document = try MyMusicJSONImportService().importPlaybackEvents(data)
        let context = try await repository.loadMyMusicMatchContext()
        let linkedIDs = Set(context.links.map(\.myMusicTrackID))
        let existingIDs = Set(try await repository.loadMyMusicPlaybackEvents().map(\.eventID))
        var inserts = 0, duplicates = 0, unresolved = 0
        var details: [MyMusicImportPreviewDetail] = []
        for event in document.events {
            let result: String
            let reason: String?
            if existingIDs.contains(event.eventID) {
                duplicates += 1; result = "duplicate"; reason = "同じeventIdが保存済みです"
            } else if !linkedIDs.contains(event.trackID) {
                unresolved += 1; result = "unresolved"; reason = "MyMusic trackIDに対応する曲がありません"
            } else {
                inserts += 1; result = "insert"; reason = nil
            }
            if details.count < 100 {
                details.append(MyMusicImportPreviewDetail(
                    id: event.eventID, title: event.trackTitle, artist: event.artist,
                    trackID: event.trackID, result: result, reason: reason
                ))
            }
        }
        return MyMusicImportPreview(
            kind: .playbackEvents, total: document.events.count, matched: 0, newlyLinked: 0,
            unchanged: 0, unmatched: 0, ambiguous: 0, invalid: 0,
            pendingUpdates: 0, pendingInserts: inserts, duplicates: duplicates, unresolved: unresolved,
            details: details
        )
    }

    private func validateRoot(_ data: Data, expected: MyMusicDocumentKind) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw MyMusicTransferServiceError.invalidUTF8
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MyMusicTransferServiceError.malformedJSON
        }
        let matches: Bool
        switch expected {
        case .library: matches = object["version"] != nil && object["tracks"] is [Any]
        case .preferences:
            matches = object["schemaVersion"] != nil && object["tracks"] is [Any] && object["events"] == nil
        case .playbackEvents: matches = object["schemaVersion"] != nil && object["events"] is [Any]
        }
        guard matches else { throw MyMusicTransferServiceError.wrongDocumentType(expected: expected) }
    }
}
