import Foundation

public enum MyMusicLibraryMatcher {
    public static func match(
        _ records: [MyMusicTrackRecord], tracks: [Track], links: [MyMusicTrackLink], matchedAt: Date
    ) -> (result: MyMusicLibraryPersistenceResult, linksToSave: [MyMusicTrackLink]) {
        let linksByExternalID = Dictionary(uniqueKeysWithValues: links.map { ($0.myMusicTrackID, $0) })
        let linksByHomeID = Dictionary(uniqueKeysWithValues: links.map { ($0.homeStereoTrackID, $0) })
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        var claimedHomeIDs = Set(linksByHomeID.keys)
        var items: [MyMusicLibraryMatchItem] = []
        var linksToSave: [MyMusicTrackLink] = []

        for record in records {
            guard record.duration.isFinite, record.duration >= 0,
                  record.fileSize.map({ $0 >= 0 }) ?? true else {
                items.append(item(record, nil, .invalid, nil, "不正なdurationまたはfileSize"))
                continue
            }
            if let existing = linksByExternalID[record.trackID], let track = tracksByID[existing.homeStereoTrackID] {
                let refreshed = link(record, track, matchedAt: existing.matchedAt, method: existing.matchMethod, source: existing.source)
                if refreshed == existing {
                    items.append(item(record, track.id, .unchanged, existing.matchMethod, nil))
                } else {
                    linksToSave.append(refreshed)
                    items.append(item(record, track.id, .matched, existing.matchMethod, "保存済みtrackID対応を更新"))
                }
                continue
            }

            let fingerprintCandidates: [Track]
            if let fingerprint = record.audioFingerprint {
                fingerprintCandidates = tracks.filter { $0.audioFingerprint == fingerprint }
            } else { fingerprintCandidates = [] }
            if !fingerprintCandidates.isEmpty {
                resolve(record, candidates: fingerprintCandidates, method: .fingerprint, claimedHomeIDs: &claimedHomeIDs,
                        matchedAt: matchedAt, items: &items, linksToSave: &linksToSave)
                continue
            }

            if let relativePath = record.relativePath, let fileSize = record.fileSize {
                let candidates = tracks.filter {
                    normalized($0.relativePath) == normalized(relativePath)
                        && $0.fileSize == fileSize && close($0.duration, record.duration)
                }
                if !candidates.isEmpty {
                    resolve(record, candidates: candidates, method: .relativePath, claimedHomeIDs: &claimedHomeIDs,
                            matchedAt: matchedAt, items: &items, linksToSave: &linksToSave)
                    continue
                }
            }

            let artist = normalized(record.artist), album = normalized(record.album)
            if !artist.isEmpty, !album.isEmpty {
                let candidates = tracks.filter {
                    normalized($0.title) == normalized(record.title)
                        && normalized($0.artist) == artist && normalized($0.album) == album
                        && close($0.duration, record.duration)
                }
                if !candidates.isEmpty {
                    resolve(record, candidates: candidates, method: .metadataFallback, claimedHomeIDs: &claimedHomeIDs,
                            matchedAt: matchedAt, items: &items, linksToSave: &linksToSave)
                    continue
                }
            }
            items.append(item(record, nil, .unmatched, nil, "一意な照合候補なし"))
        }
        return (MyMusicLibraryPersistenceResult(items: items), linksToSave)
    }

    private static func resolve(
        _ record: MyMusicTrackRecord, candidates: [Track], method: MyMusicTrackMatchMethod,
        claimedHomeIDs: inout Set<Track.ID>, matchedAt: Date,
        items: inout [MyMusicLibraryMatchItem], linksToSave: inout [MyMusicTrackLink]
    ) {
        guard candidates.count == 1, let track = candidates.first else {
            items.append(item(record, nil, .ambiguous, method, "候補が\(candidates.count)件")); return
        }
        guard !claimedHomeIDs.contains(track.id) else {
            items.append(item(record, nil, .ambiguous, method, "候補は別のMyMusic trackIDへ接続済み")); return
        }
        linksToSave.append(link(record, track, matchedAt: matchedAt, method: method, source: .libraryImport))
        claimedHomeIDs.insert(track.id)
        items.append(item(record, track.id, .newlyLinked, method, nil))
    }

    private static func link(
        _ record: MyMusicTrackRecord, _ track: Track, matchedAt: Date,
        method: MyMusicTrackMatchMethod, source: MyMusicLinkSource
    ) -> MyMusicTrackLink {
        MyMusicTrackLink(
            homeStereoTrackID: track.id, myMusicTrackID: record.trackID,
            relativePath: track.relativePath, fileSize: track.fileSize, duration: track.duration,
            audioFingerprint: record.audioFingerprint ?? track.audioFingerprint,
            matchedAt: matchedAt, matchMethod: method, source: source
        )
    }

    private static func item(
        _ record: MyMusicTrackRecord, _ homeID: Track.ID?, _ status: MyMusicLibraryMatchStatus,
        _ method: MyMusicTrackMatchMethod?, _ detail: String?
    ) -> MyMusicLibraryMatchItem {
        MyMusicLibraryMatchItem(
            myMusicTrackID: record.trackID, homeStereoTrackID: homeID,
            status: status, matchMethod: method, detail: detail
        )
    }
    private static func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }
    private static func close(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) <= 0.5 }
}

public struct MyMusicPersistenceService: Sendable {
    private let repository: any MyMusicPersisting
    private let clock: @Sendable () -> Date

    public init(repository: any MyMusicPersisting, clock: @escaping @Sendable () -> Date = { .now }) {
        self.repository = repository; self.clock = clock
    }

    public func importLibrary(_ data: Data) async throws -> MyMusicLibraryPersistenceResult {
        let document = try MyMusicJSONImportService().importLibrary(data)
        let context = try await repository.loadMyMusicMatchContext()
        let match = MyMusicLibraryMatcher.match(
            document.tracks, tracks: context.tracks, links: context.links, matchedAt: clock()
        )
        try await repository.saveMyMusicTrackLinks(match.linksToSave)
        return match.result
    }

    public func importPreferences(_ data: Data) async throws -> MyMusicPreferencesPersistenceResult {
        let document = try MyMusicJSONImportService().importPreferences(data)
        return try await repository.mergeMyMusicPreferences(document.tracks, exportedAt: document.exportedAt)
    }

    public func importPlaybackEvents(_ data: Data) async throws -> MyMusicPlaybackEventsPersistenceResult {
        let document = try MyMusicJSONImportService().importPlaybackEvents(data)
        return try await repository.appendMyMusicPlaybackEvents(document.events)
    }

    public func exportLibrary() async throws -> Data {
        try MyMusicJSONExportService().exportLibrary(try await repository.loadMyMusicLibraryRecords())
    }

    public func exportPreferences(exportedAt: Date) async throws -> Data {
        let values = try await repository.loadMyMusicPreferences().map {
            MyMusicPreferenceRecord(
                trackID: $0.myMusicTrackID, playbackPreference: $0.playbackPreference, favorite: $0.favorite
            )
        }
        return try MyMusicJSONExportService().exportPreferences(values, exportedAt: exportedAt)
    }

    public func exportPlaybackEvents(exportedAt: Date) async throws -> Data {
        try await exportPlaybackEventsWithReport(exportedAt: exportedAt).data
    }

    public func exportPlaybackEventsWithReport(exportedAt: Date) async throws -> MyMusicPlaybackEventsExportResult {
        let persisted = try await repository.loadMyMusicPlaybackEvents()
        let records = try await repository.loadMyMusicPlaybackEventRecords()
        return MyMusicPlaybackEventsExportResult(
            data: try MyMusicJSONExportService().exportPlaybackEvents(records, exportedAt: exportedAt),
            exported: records.count, unresolved: max(0, persisted.count - records.count)
        )
    }
}
