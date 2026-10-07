import Foundation

public enum MyMusicLibraryMatcher {
    public static func match(
        _ records: [MyMusicTrackRecord], tracks: [Track], links: [MyMusicTrackLink], matchedAt: Date
    ) -> (result: MyMusicLibraryPersistenceResult, linksToSave: [MyMusicTrackLink]) {
        let linksByExternalID = Dictionary(uniqueKeysWithValues: links.map { ($0.myMusicTrackID, $0) })
        let linksByHomeID = Dictionary(uniqueKeysWithValues: links.map { ($0.homeStereoTrackID, $0) })
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let tracksByRelativePath = Dictionary(grouping: tracks, by: { normalizedRelativePath($0.relativePath) })
        let tracksByFingerprint = Dictionary(grouping: tracks.compactMap { track in
            track.audioFingerprint.map { ($0, track) }
        }, by: \.0).mapValues { $0.map(\.1) }
        var claimedHomeIDs = Set(linksByHomeID.keys)
        var items: [MyMusicLibraryMatchItem] = []
        var linksToSave: [MyMusicTrackLink] = []
        let importedIDs = Set(records.map(\.trackID))

        for record in records {
            guard record.duration.isFinite, record.duration >= 0,
                  record.fileSize.map({ $0 >= 0 }) ?? true else {
                items.append(item(record, nil, .invalid, nil, "不正なdurationまたはfileSize"))
                continue
            }
            if let existing = linksByExternalID[record.trackID], let track = tracksByID[existing.homeStereoTrackID] {
                let refreshed = link(record, track, matchedAt: existing.matchedAt, method: existing.matchMethod, source: existing.source)
                linksToSave.append(MyMusicTrackLink(
                    homeStereoTrackID: refreshed.homeStereoTrackID,
                    myMusicTrackID: refreshed.myMusicTrackID, relativePath: refreshed.relativePath,
                    fileSize: refreshed.fileSize, duration: refreshed.duration,
                    audioFingerprint: refreshed.audioFingerprint,
                    firstSeenAt: existing.firstSeenAt ?? record.firstSeenAt,
                    lastSeenAt: matchedAt, isInCurrentSnapshot: true,
                    matchedAt: existing.matchedAt, matchMethod: existing.matchMethod, source: existing.source
                ))
                if refreshed.relativePath == existing.relativePath,
                   refreshed.fileSize == existing.fileSize,
                   close(refreshed.duration, existing.duration),
                   refreshed.audioFingerprint == existing.audioFingerprint {
                    items.append(item(record, track.id, .unchanged, .trackID, nil))
                } else {
                    items.append(item(record, track.id, .matched, .trackID, "保存済みtrackID対応を更新"))
                }
                continue
            }

            if let relativePath = record.relativePath {
                let pathCandidates = tracksByRelativePath[normalizedRelativePath(relativePath)] ?? []
                if !pathCandidates.isEmpty {
                    let compatible = pathCandidates.filter { track in
                        (record.fileSize.map { track.fileSize == $0 } ?? true)
                            && close(track.duration, record.duration)
                    }
                    guard !compatible.isEmpty else {
                        items.append(item(record, nil, .unmatched, .relativePath, "relativePath一致候補とfileSizeまたはdurationが矛盾"))
                        continue
                    }
                    resolve(record, candidates: compatible, method: .relativePath, claimedHomeIDs: &claimedHomeIDs,
                            matchedAt: matchedAt, items: &items, linksToSave: &linksToSave)
                    continue
                }
            }

            let fingerprintCandidates: [Track]
            if let fingerprint = record.audioFingerprint {
                fingerprintCandidates = tracksByFingerprint[fingerprint] ?? []
            } else { fingerprintCandidates = [] }
            if !fingerprintCandidates.isEmpty {
                resolve(record, candidates: fingerprintCandidates, method: .fingerprint, claimedHomeIDs: &claimedHomeIDs,
                        matchedAt: matchedAt, items: &items, linksToSave: &linksToSave)
                continue
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
        let missing = links.count { !importedIDs.contains($0.myMusicTrackID) }
        return (MyMusicLibraryPersistenceResult(items: items, missingFromSnapshot: missing), linksToSave)
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
            items.append(item(record, nil, .conflict, method, "候補は別のMyMusic trackIDへ接続済み")); return
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
            relativePath: record.relativePath ?? track.relativePath,
            fileSize: record.fileSize ?? track.fileSize, duration: record.duration,
            audioFingerprint: record.audioFingerprint ?? track.audioFingerprint,
            firstSeenAt: record.firstSeenAt, lastSeenAt: matchedAt, isInCurrentSnapshot: true,
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
    private static func normalizedRelativePath(_ value: String) -> String {
        MyMusicJSONCodec.normalizedRelativePath(value) ?? value.precomposedStringWithCanonicalMapping
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
        let importedAt = clock()
        let match = MyMusicLibraryMatcher.match(
            document.tracks, tracks: context.tracks, links: context.links, matchedAt: importedAt
        )
        try await repository.applyMyMusicLibrarySnapshot(
            match.linksToSave, records: document.tracks, importedAt: importedAt
        )
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
        try await preparePreferencesExport(exportedAt: exportedAt).data
    }

    public func preparePreferencesExport(exportedAt: Date) async throws -> MyMusicPreferencesExportResult {
        let pendingChanges = try await repository.loadPendingMyMusicPreferenceExports()
        return MyMusicPreferencesExportResult(
            data: try MyMusicJSONExportService().exportPreferences(
                pendingChanges.map(\.record), exportedAt: exportedAt
            ),
            pendingChanges: pendingChanges
        )
    }

    public func acknowledgePreferencesExport(
        _ pendingChanges: [PendingMyMusicPreferenceExport]
    ) async throws {
        try await repository.acknowledgeMyMusicPreferenceExports(pendingChanges)
    }

    public func exportPlaybackEvents(
        exportedAt: Date, playedAtRange: Range<Date>? = nil
    ) async throws -> Data {
        try await exportPlaybackEventsWithReport(
            exportedAt: exportedAt, playedAtRange: playedAtRange
        ).data
    }

    public func exportPlaybackEventsWithReport(
        exportedAt: Date, playedAtRange: Range<Date>? = nil
    ) async throws -> MyMusicPlaybackEventsExportResult {
        let allPersisted = try await repository.loadMyMusicPlaybackEvents()
        let allRecords = try await repository.loadMyMusicPlaybackEventRecords()
        let persisted = allPersisted.filter { playedAtRange?.contains($0.playedAt) ?? true }
        let records = allRecords.filter { playedAtRange?.contains($0.playedAt) ?? true }
        return MyMusicPlaybackEventsExportResult(
            data: try MyMusicJSONExportService().exportPlaybackEvents(records, exportedAt: exportedAt),
            exported: records.count, unresolved: max(0, persisted.count - records.count)
        )
    }

    public func importPlaylists(_ data: Data, expectedPlaylists: [Playlist]? = nil) async throws -> MyMusicPlaylistPersistenceResult {
        let document = try MyMusicJSONImportService().importPlaylists(data)
        return try await repository.mergeMyMusicPlaylists(document.playlists, original: data, expectedPlaylists: expectedPlaylists)
    }

    public func exportPlaylists(deduplicate: Bool = false) async throws -> MyMusicPlaylistExportResult {
        let context = try await repository.loadMyMusicPlaylistContext()
        return try MyMusicJSONExportService().exportPlaylists(
            playlists: context.playlists, tracks: context.tracks, links: context.links, deduplicate: deduplicate
        )
    }
}
