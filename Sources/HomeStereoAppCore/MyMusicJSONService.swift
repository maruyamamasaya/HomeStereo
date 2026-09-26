import Foundation

/// 文書全体のdecode・検証が成功してから内部交換モデルを返す。永続化は呼び出し側のtransactionで行う。
public struct MyMusicJSONImportService: Sendable {
    public init() {}

    public func importLibrary(_ data: Data) throws -> MyMusicLibraryImport {
        let document = try MyMusicJSONCodec.decodeLibrary(data)
        return MyMusicLibraryImport(tracks: document.tracks.map {
            MyMusicTrackRecord(
                trackID: $0.trackID, title: $0.title, artist: $0.artist, album: $0.album,
                genre: $0.genre, year: $0.year, duration: $0.duration, format: $0.format,
                favorite: $0.favorite, playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt,
                audioFingerprint: $0.audioFingerprint, firstSeenAt: $0.firstSeenAt
            )
        })
    }

    public func importPreferences(_ data: Data) throws -> MyMusicPreferencesImport {
        let document = try MyMusicJSONCodec.decodePreferences(data)
        return MyMusicPreferencesImport(exportedAt: document.exportedAt, tracks: document.tracks.map {
            MyMusicPreferenceRecord(trackID: $0.trackId, playbackPreference: $0.playbackPreference, favorite: $0.favorite)
        })
    }

    public func importPlaybackEvents(_ data: Data) throws -> MyMusicPlaybackEventsImport {
        let document = try MyMusicJSONCodec.decodePlaybackEvents(data)
        return MyMusicPlaybackEventsImport(exportedAt: document.exportedAt, events: document.events.map {
            MyMusicPlaybackEventRecord(
                eventID: $0.eventId, trackID: $0.trackId, trackTitle: $0.trackTitle, artist: $0.artist,
                album: $0.album, playedAt: $0.playedAt, playDuration: $0.playDuration,
                trackDuration: $0.trackDuration, completed: $0.completed, skipped: $0.skipped,
                playSource: $0.playSource, selectionType: $0.selectionType, platform: $0.platform,
                schemaVersion: $0.schemaVersion
            )
        })
    }
}

public struct MyMusicJSONExportService: Sendable {
    public init() {}

    public func exportLibrary(_ tracks: [MyMusicTrackRecord]) throws -> Data {
        try MyMusicJSONCodec.encodeLibrary(MyMusicLibraryDocumentDTO(
            version: MyMusicLibraryDocumentDTO.currentVersion,
            tracks: tracks.map {
                MyMusicLibraryTrackDTO(
                    trackID: $0.trackID, title: $0.title, artist: $0.artist, album: $0.album,
                    genre: $0.genre, year: $0.year, duration: $0.duration, format: $0.format,
                    favorite: $0.favorite, playCount: $0.playCount, lastPlayedAt: $0.lastPlayedAt,
                    audioFingerprint: $0.audioFingerprint, firstSeenAt: $0.firstSeenAt
                )
            }
        ))
    }

    /// 現行Library/Listening modelから互換用の派生値を組み立てる。
    public func exportLibrary(tracks: [Track], favorites: [Favorite], events: [PlaybackEvent]) throws -> Data {
        let favoriteIDs = Set(favorites.map(\.trackID))
        let eventsByTrack = Dictionary(grouping: events, by: \.trackID)
        return try exportLibrary(tracks.map { track in
            let trackEvents = eventsByTrack[track.id] ?? []
            return MyMusicTrackRecord(
                trackID: track.id, title: track.title, artist: track.artist ?? "",
                album: track.album, genre: track.genre, year: track.releaseYear, duration: track.duration,
                format: Self.compatibleFormat(codec: track.codec, fileExtension: track.fileExtension),
                favorite: favoriteIDs.contains(track.id), playCount: trackEvents.count,
                lastPlayedAt: trackEvents.map(\.startedAt).max()
            )
        })
    }

    public func exportPreferences(_ tracks: [MyMusicPreferenceRecord], exportedAt: Date) throws -> Data {
        try MyMusicJSONCodec.encodePreferences(MyMusicPreferencesDocumentDTO(
            schemaVersion: MyMusicPreferencesDocumentDTO.currentSchemaVersion, exportedAt: exportedAt,
            tracks: tracks.map { MyMusicPreferenceTrackDTO(
                trackId: $0.trackID, playbackPreference: $0.playbackPreference, favorite: $0.favorite
            ) }
        ))
    }

    public func exportPlaybackEvents(_ events: [MyMusicPlaybackEventRecord], exportedAt: Date) throws -> Data {
        try MyMusicJSONCodec.encodePlaybackEvents(MyMusicPlaybackEventsDocumentDTO(
            schemaVersion: MyMusicPlaybackEventsDocumentDTO.currentSchemaVersion, exportedAt: exportedAt,
            events: events.map {
                MyMusicPlaybackEventDTO(
                    eventId: $0.eventID, trackId: $0.trackID, trackTitle: $0.trackTitle, artist: $0.artist,
                    album: $0.album, playedAt: $0.playedAt, playDuration: $0.playDuration,
                    trackDuration: $0.trackDuration, completed: $0.completed, skipped: $0.skipped,
                    playSource: $0.playSource, selectionType: $0.selectionType, platform: $0.platform,
                    schemaVersion: $0.schemaVersion
                )
            }
        ))
    }

    /// 現行の再生履歴をMyMusic eventへ変換する。Macで生成するIDとplatformはこの境界で固定する。
    public func playbackEventRecord(
        event: PlaybackEvent, track: Track, skipped: Bool,
        playSource: String, selectionType: String
    ) -> MyMusicPlaybackEventRecord {
        let completed = event.outcome == .completed
        return MyMusicPlaybackEventRecord(
            eventID: "mac-\(event.id.uuidString.lowercased())", trackID: event.trackID,
            trackTitle: track.title, artist: track.artist ?? "", album: track.album,
            playedAt: event.startedAt, playDuration: event.playedSeconds, trackDuration: track.duration,
            completed: completed, skipped: completed ? false : skipped,
            playSource: playSource, selectionType: selectionType, platform: "macOS"
        )
    }

    private static func compatibleFormat(codec: String?, fileExtension: String) -> String? {
        if let codec = codec?.uppercased() {
            if codec.contains("FLAC") { return "FLAC" }
            if codec.contains("ALAC") || codec.contains("APPLE LOSSLESS") { return "ALAC" }
            if codec.contains("AAC") { return "AAC" }
            if codec.contains("MP3") || codec.contains("MPEG LAYER 3") { return "MP3" }
            if codec.contains("WAV") { return "WAV" }
            if codec.contains("AIFF") { return "AIFF" }
        }
        let fileFormat = fileExtension.uppercased()
        return ["FLAC", "ALAC", "AAC", "MP3", "WAV", "AIFF"].contains(fileFormat) ? fileFormat : nil
    }
}

/// 検証済みの交換modelを文書ごとの規則でmergeする純粋関数。実際の保存は単一transactionで行う。
public enum MyMusicImportMergeService {
    public static func mergeLibrary(
        imported: [MyMusicTrackRecord], into existing: [MyMusicTrackRecord]
    ) -> [MyMusicTrackRecord] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.trackID, $0) })
        for track in imported { byID[track.trackID] = track }
        return byID.values.sorted { $0.trackID.uuidString < $1.trackID.uuidString }
    }

    public static func mergePreferences(
        imported: [MyMusicPreferenceRecord], into existing: [MyMusicPreferenceRecord]
    ) -> [MyMusicPreferenceRecord] {
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.trackID, $0) })
        for preference in imported { byID[preference.trackID] = preference }
        return byID.values.sorted { $0.trackID.uuidString < $1.trackID.uuidString }
    }

    public static func appendEvents(
        imported: [MyMusicPlaybackEventRecord], to existing: [MyMusicPlaybackEventRecord]
    ) -> [MyMusicPlaybackEventRecord] {
        var result = existing
        var eventIDs = Set(existing.map(\.eventID))
        for event in imported where eventIDs.insert(event.eventID).inserted { result.append(event) }
        return result
    }
}
