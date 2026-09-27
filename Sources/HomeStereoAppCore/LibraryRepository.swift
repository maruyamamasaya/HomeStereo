import Foundation
import SQLite3

public final class SQLiteLibraryRepository: LibraryPersisting, MyMusicPersisting, AnalyticsPersisting, TrackPreferencePersisting, GenreDisplayPresetPersisting, @unchecked Sendable {
    public static let currentSchemaVersion = 13
    private let lock = NSRecursiveLock()
    private var database: OpaquePointer?

    public convenience init() throws {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("HomeStereo", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try self.init(databaseURL: base.appendingPathComponent("Library.sqlite3"))
    }

    public init(databaseURL: URL) throws {
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
            throw UserFacingError.persistenceFailed("SQLite databaseを開けません。")
        }
        try execute("PRAGMA foreign_keys = ON")
        try migrate()
    }

    deinit { sqlite3_close(database) }

    public func schemaVersion() async throws -> Int {
        try withLock { Int(try scalarInt("PRAGMA user_version")) }
    }

    public func loadGenreDisplayPresets() async throws -> [GenreDisplayPreset] {
        try withLock {
            try query("SELECT id, name, enabled_genre_names, includes_unassigned_genre_setting FROM genre_display_presets ORDER BY position") { statement in
                let genresData = Data(text(statement, 2).utf8)
                let setting: Bool? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil : sqlite3_column_int(statement, 3) != 0
                return GenreDisplayPreset(
                    id: UUID(uuidString: text(statement, 0))!, name: text(statement, 1),
                    enabledGenreNames: try JSONDecoder().decode([String].self, from: genresData),
                    includesUnassignedGenreSetting: setting
                )
            }
        }
    }

    public func replaceGenreDisplayPresets(_ presets: [GenreDisplayPreset]) async throws {
        try GenreDisplayPresetCodec.validate(GenreDisplayPresetDocument(presets: presets))
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM genre_display_presets")
                for (position, preset) in presets.enumerated() {
                    let genres = String(decoding: try JSONEncoder().encode(preset.enabledGenreNames), as: UTF8.self)
                    try update("INSERT INTO genre_display_presets(id, name, normalized_name, enabled_genre_names, includes_unassigned_genre_setting, position) VALUES(?, ?, ?, ?, ?, ?)") { statement in
                        bind(preset.id.uuidString, to: statement, at: 1)
                        bind(preset.name.trimmingCharacters(in: .whitespacesAndNewlines), to: statement, at: 2)
                        bind(GenreDisplayPresetCodec.normalized(preset.name), to: statement, at: 3)
                        bind(genres, to: statement, at: 4)
                        if let setting = preset.includesUnassignedGenreSetting { bind(setting ? 1 : 0, to: statement, at: 5) }
                        else { sqlite3_bind_null(statement, 5) }
                        bind(position, to: statement, at: 6)
                    }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func loadFolders() async throws -> [LibraryFolder] {
        try withLock {
            let sql = """
            SELECT f.id, f.display_name, f.path, f.access_state, f.last_scanned_at,
                   COUNT(CASE WHEN t.scan_state != 'missing' THEN 1 END)
            FROM library_folders f LEFT JOIN tracks t ON t.folder_id = f.id
            GROUP BY f.id ORDER BY f.display_name COLLATE NOCASE
            """
            return try query(sql) { statement in
                LibraryFolder(
                    id: UUID(uuidString: text(statement, 0))!,
                    displayName: text(statement, 1), path: text(statement, 2),
                    accessState: LibraryFolder.AccessState(rawValue: text(statement, 3)) ?? .needsReselection,
                    lastScannedAt: optionalDate(statement, 4), trackCount: Int(sqlite3_column_int64(statement, 5))
                )
            }
        }
    }

    public func loadFolder(id: UUID) async throws -> PersistedFolder? {
        try withLock {
            let rows = try query(
                "SELECT id, display_name, path, access_state, last_scanned_at, bookmark FROM library_folders WHERE id = ?",
                binds: { bind(id.uuidString, to: $0, at: 1) }
            ) { statement in
                let folder = LibraryFolder(
                    id: id, displayName: text(statement, 1), path: text(statement, 2),
                    accessState: LibraryFolder.AccessState(rawValue: text(statement, 3)) ?? .needsReselection,
                    lastScannedAt: optionalDate(statement, 4)
                )
                let bytes = sqlite3_column_blob(statement, 5)
                let count = Int(sqlite3_column_bytes(statement, 5))
                return PersistedFolder(folder: folder, bookmarkData: bytes.map { Data(bytes: $0, count: count) } ?? Data())
            }
            return rows.first
        }
    }

    public func addFolder(_ folder: LibraryFolder, bookmarkData: Data) async throws {
        try withLock {
            try update(
                "INSERT INTO library_folders(id, display_name, path, normalized_path, bookmark, access_state) VALUES(?, ?, ?, ?, ?, ?)",
                binds: { statement in
                    bind(folder.id.uuidString, to: statement, at: 1)
                    bind(folder.displayName, to: statement, at: 2)
                    bind(folder.path, to: statement, at: 3)
                    bind(Self.normalizedPath(folder.path), to: statement, at: 4)
                    _ = bookmarkData.withUnsafeBytes { sqlite3_bind_blob(statement, 5, $0.baseAddress, Int32($0.count), sqliteTransient) }
                    bind(folder.accessState.rawValue, to: statement, at: 6)
                }
            )
        }
    }

    public func updateBookmark(folderID: UUID, bookmarkData: Data, path: String, displayName: String) async throws {
        try withLock {
            try update(
                "UPDATE library_folders SET bookmark = ?, path = ?, normalized_path = ?, display_name = ?, access_state = 'available' WHERE id = ?",
                binds: { statement in
                    _ = bookmarkData.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), sqliteTransient) }
                    bind(path, to: statement, at: 2); bind(Self.normalizedPath(path), to: statement, at: 3)
                    bind(displayName, to: statement, at: 4); bind(folderID.uuidString, to: statement, at: 5)
                }
            )
        }
    }

    public func setFolderAccessState(id: UUID, state: LibraryFolder.AccessState) async throws {
        try withLock { try update("UPDATE library_folders SET access_state = ? WHERE id = ?") {
            bind(state.rawValue, to: $0, at: 1); bind(id.uuidString, to: $0, at: 2)
        } }
    }

    public func removeFolder(id: UUID) async throws {
        try withLock { try update("DELETE FROM library_folders WHERE id = ?") { bind(id.uuidString, to: $0, at: 1) } }
    }

    public func loadTracks(folderID: UUID?) async throws -> [Track] {
        try withLock {
            var sql = """
            SELECT t.id, t.folder_id, t.relative_path, f.path, t.file_size, t.modification_date,
                   t.title, t.artist, t.album_artist, t.album, t.genre, t.composer, t.release_year,
                   t.track_number, t.track_total, t.disc_number, t.disc_total, t.duration,
                   t.file_extension, t.codec, t.sample_rate, t.bit_depth, t.channel_count,
                   t.has_artwork, t.scan_state, t.metadata_version, t.last_scanned_at,
                   t.file_resource_identifier, t.audio_fingerprint, t.bit_rate
            FROM tracks t JOIN library_folders f ON f.id = t.folder_id
            """
            if folderID != nil { sql += " WHERE t.folder_id = ?" }
            sql += " ORDER BY t.title COLLATE NOCASE, t.relative_path COLLATE NOCASE"
            return try query(sql, binds: { statement in
                if let folderID { bind(folderID.uuidString, to: statement, at: 1) }
            }) { statement in
                let root = URL(fileURLWithPath: text(statement, 3), isDirectory: true)
                let relative = text(statement, 2)
                return Track(
                    id: UUID(uuidString: text(statement, 0))!, libraryFolderID: UUID(uuidString: text(statement, 1))!,
                    relativePath: relative, url: root.appendingPathComponent(relative),
                    fileSize: sqlite3_column_int64(statement, 4), modificationDate: date(statement, 5),
                    fileResourceIdentifier: optionalData(statement, 27), audioFingerprint: optionalText(statement, 28),
                    title: text(statement, 6), artist: optionalText(statement, 7), albumArtist: optionalText(statement, 8),
                    album: optionalText(statement, 9), genre: optionalText(statement, 10), composer: optionalText(statement, 11),
                    releaseYear: optionalInt(statement, 12), trackNumber: optionalInt(statement, 13),
                    trackTotal: optionalInt(statement, 14), discNumber: optionalInt(statement, 15), discTotal: optionalInt(statement, 16),
                    duration: sqlite3_column_double(statement, 17), codec: optionalText(statement, 19),
                    sampleRate: optionalDouble(statement, 20), bitRate: optionalDouble(statement, 29),
                    bitDepth: optionalInt(statement, 21),
                    channelCount: optionalInt(statement, 22), hasArtwork: sqlite3_column_int(statement, 23) != 0,
                    scanState: TrackScanState(rawValue: text(statement, 24)) ?? .unreadable,
                    metadataSchemaVersion: Int(sqlite3_column_int(statement, 25)), lastScannedAt: date(statement, 26)
                )
            }
        }
    }

    public func applySuccessfulScan(folderID: UUID, tracks: [Track], scannedAt: Date) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let ids = Set(tracks.map(\.id))
                let paths = Set(tracks.map { LibraryService.normalizedRelativePath($0.relativePath) })
                guard ids.count == tracks.count, paths.count == tracks.count,
                      tracks.allSatisfy({ $0.libraryFolderID == folderID }) else {
                    throw UserFacingError.persistenceFailed("scan結果のTrack IDまたはrelative pathが重複しています。")
                }
                let existing = try query(
                    "SELECT normalized_path, file_size, modification_date, scan_state, metadata_version, file_resource_identifier, audio_fingerprint FROM tracks WHERE folder_id = ?",
                    binds: { bind(folderID.uuidString, to: $0, at: 1) }
                ) { statement in
                    (
                        text(statement, 0),
                        TrackFingerprint(
                            fileSize: sqlite3_column_int64(statement, 1), modificationDate: sqlite3_column_double(statement, 2),
                            scanState: text(statement, 3), metadataVersion: Int(sqlite3_column_int(statement, 4)),
                            fileResourceIdentifier: optionalData(statement, 5), audioFingerprint: optionalText(statement, 6)
                        )
                    )
                }
                let fingerprints = Dictionary(uniqueKeysWithValues: existing)
                let existingLocations = Dictionary(uniqueKeysWithValues: try query(
                    "SELECT id, normalized_path FROM tracks WHERE folder_id = ?",
                    binds: { bind(folderID.uuidString, to: $0, at: 1) }
                ) { (UUID(uuidString: text($0, 0))!, text($0, 1)) })
                for track in tracks {
                    let key = LibraryService.normalizedRelativePath(track.relativePath)
                    let value = TrackFingerprint(
                        fileSize: track.fileSize, modificationDate: track.modificationDate.timeIntervalSince1970,
                        scanState: track.scanState.rawValue, metadataVersion: track.metadataSchemaVersion,
                        fileResourceIdentifier: track.fileResourceIdentifier, audioFingerprint: track.audioFingerprint
                    )
                    if let previousKey = existingLocations[track.id], previousKey != key {
                        try update(
                            "UPDATE tracks SET relative_path = ?, normalized_path = ? WHERE id = ? AND folder_id = ?"
                        ) {
                            bind(track.relativePath, to: $0, at: 1); bind(key, to: $0, at: 2)
                            bind(track.id.uuidString, to: $0, at: 3); bind(folderID.uuidString, to: $0, at: 4)
                        }
                    }
                    if fingerprints[key] != value { try upsert(track) }
                }
                try update("UPDATE library_folders SET last_scanned_at = ?, access_state = 'available' WHERE id = ?") {
                    bind(scannedAt.timeIntervalSince1970, to: $0, at: 1); bind(folderID.uuidString, to: $0, at: 2)
                }
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
    }

    public func loadQueue() async throws -> QueueSnapshot {
        try withLock {
            let items = try query("SELECT id, track_id FROM playback_queue ORDER BY position") { statement in
                QueueItem(id: UUID(uuidString: text(statement, 0))!, trackID: UUID(uuidString: text(statement, 1))!)
            }
            let states = try query("SELECT current_index, repeat_mode, shuffle_enabled, position FROM queue_state WHERE singleton = 1") { statement in
                QueueSnapshot(
                    items: items,
                    currentIndex: sqlite3_column_type(statement, 0) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 0)),
                    repeatMode: QueueRepeatMode(rawValue: text(statement, 1)) ?? .off,
                    shuffleEnabled: sqlite3_column_int(statement, 2) != 0,
                    position: sqlite3_column_double(statement, 3)
                )
            }
            return states.first ?? QueueSnapshot(items: items)
        }
    }

    public func saveQueue(_ snapshot: QueueSnapshot) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("DELETE FROM playback_queue")
                for (position, item) in snapshot.items.enumerated() {
                    try update("INSERT INTO playback_queue(position, id, track_id) VALUES(?, ?, ?)") {
                        bind(position, to: $0, at: 1); bind(item.id.uuidString, to: $0, at: 2); bind(item.trackID.uuidString, to: $0, at: 3)
                    }
                }
                try update("""
                    INSERT INTO queue_state(singleton, current_index, repeat_mode, shuffle_enabled, position)
                    VALUES(1, ?, ?, ?, ?)
                    ON CONFLICT(singleton) DO UPDATE SET current_index=excluded.current_index,
                    repeat_mode=excluded.repeat_mode, shuffle_enabled=excluded.shuffle_enabled, position=excluded.position
                    """) {
                    bind(snapshot.currentIndex, to: $0, at: 1); bind(snapshot.repeatMode.rawValue, to: $0, at: 2)
                    bind(snapshot.shuffleEnabled ? 1 : 0, to: $0, at: 3); bind(snapshot.position, to: $0, at: 4)
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func saveQueuePosition(_ position: TimeInterval) async throws {
        try withLock {
            try update("UPDATE queue_state SET position = ? WHERE singleton = 1") {
                bind(max(0, position), to: $0, at: 1)
            }
        }
    }

    public func loadPlaylists() async throws -> [Playlist] {
        try withLock {
            let rows = try query("SELECT id, mymusic_playlist_id, name, created_at, updated_at, kind, tags_json FROM playlists ORDER BY name COLLATE NOCASE") { statement in
                (UUID(uuidString: text(statement, 0))!, optionalText(statement, 1).flatMap(UUID.init(uuidString:)),
                 text(statement, 2), date(statement, 3), date(statement, 4), text(statement, 5), Self.decodeTags(text(statement, 6)))
            }
            return try rows.map { id, myMusicPlaylistID, name, createdAt, updatedAt, kind, tags in
                let items = try query("SELECT id, track_id FROM playlist_items WHERE playlist_id = ? ORDER BY position", binds: {
                    bind(id.uuidString, to: $0, at: 1)
                }) { statement in
                    PlaylistItem(id: UUID(uuidString: text(statement, 0))!, trackID: UUID(uuidString: text(statement, 1))!)
                }
                return Playlist(
                    id: id, myMusicPlaylistID: myMusicPlaylistID, name: name,
                    createdAt: createdAt, updatedAt: updatedAt, kind: kind, tags: tags, items: items
                )
            }
        }
    }

    public func savePlaylist(_ playlist: Playlist) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try savePlaylistStatements(playlist)
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func deletePlaylist(id: UUID) async throws {
        try withLock { try update("DELETE FROM playlists WHERE id = ?") { bind(id.uuidString, to: $0, at: 1) } }
    }

    public func loadFavorites() async throws -> [Favorite] {
        try withLock {
            try query("SELECT track_id, added_at FROM favorites ORDER BY added_at DESC") {
                Favorite(trackID: UUID(uuidString: text($0, 0))!, addedAt: date($0, 1))
            }
        }
    }

    public func saveFavorite(_ favorite: Favorite) async throws {
        try withLock {
            try update("INSERT OR IGNORE INTO favorites(track_id, added_at) VALUES(?, ?)") {
                bind(favorite.trackID.uuidString, to: $0, at: 1)
                bind(favorite.addedAt.timeIntervalSince1970, to: $0, at: 2)
            }
        }
    }

    public func deleteFavorite(trackID: Track.ID) async throws {
        try withLock { try update("DELETE FROM favorites WHERE track_id = ?") { bind(trackID.uuidString, to: $0, at: 1) } }
    }

    public func deleteAllFavorites() async throws { try withLock { try execute("DELETE FROM favorites") } }

    public func loadPlaybackEvents() async throws -> [PlaybackEvent] {
        try withLock {
            try query("SELECT id, track_id, started_at, played_seconds, outcome FROM playback_events ORDER BY started_at DESC") {
                PlaybackEvent(
                    id: UUID(uuidString: text($0, 0))!, trackID: UUID(uuidString: text($0, 1))!,
                    startedAt: date($0, 2), playedSeconds: sqlite3_column_double($0, 3),
                    outcome: PlaybackEventOutcome(rawValue: text($0, 4)) ?? .stopped
                )
            }
        }
    }

    public func savePlaybackEvent(_ event: PlaybackEvent) async throws {
        try withLock {
            try update("""
                INSERT INTO playback_events(id, track_id, started_at, played_seconds, outcome) VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET played_seconds=excluded.played_seconds, outcome=excluded.outcome
                """) {
                bind(event.id.uuidString, to: $0, at: 1); bind(event.trackID.uuidString, to: $0, at: 2)
                bind(event.startedAt.timeIntervalSince1970, to: $0, at: 3); bind(max(0, event.playedSeconds), to: $0, at: 4)
                bind(event.outcome.rawValue, to: $0, at: 5)
            }
        }
    }

    public func deleteAllPlaybackEvents() async throws { try withLock { try execute("DELETE FROM playback_events") } }

    public func mergeBackup(playlists: [Playlist], favorites: [Favorite], events: [PlaybackEvent]) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for playlist in playlists { try savePlaylistStatements(playlist) }
                for favorite in favorites {
                    try update("INSERT OR IGNORE INTO favorites(track_id, added_at) VALUES(?, ?)") {
                        bind(favorite.trackID.uuidString, to: $0, at: 1); bind(favorite.addedAt.timeIntervalSince1970, to: $0, at: 2)
                    }
                }
                for event in events {
                    try update("INSERT OR IGNORE INTO playback_events(id, track_id, started_at, played_seconds, outcome) VALUES(?, ?, ?, ?, ?)") {
                        bind(event.id.uuidString, to: $0, at: 1); bind(event.trackID.uuidString, to: $0, at: 2)
                        bind(event.startedAt.timeIntervalSince1970, to: $0, at: 3); bind(event.playedSeconds, to: $0, at: 4)
                        bind(event.outcome.rawValue, to: $0, at: 5)
                    }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func loadMyMusicMatchContext() async throws -> (tracks: [Track], links: [MyMusicTrackLink]) {
        let tracks = try await loadTracks(folderID: nil)
        let links = try await loadMyMusicTrackLinks()
        return (tracks, links)
    }

    public func loadMyMusicTrackLinks() async throws -> [MyMusicTrackLink] {
        try withLock {
            try query("""
                SELECT home_track_id, mymusic_track_id, relative_path, file_size, duration,
                       audio_fingerprint, first_seen_at, last_seen_at, in_current_snapshot,
                       matched_at, match_method, source
                FROM mymusic_track_links ORDER BY mymusic_track_id
                """) { statement in
                MyMusicTrackLink(
                    homeStereoTrackID: UUID(uuidString: text(statement, 0))!,
                    myMusicTrackID: UUID(uuidString: text(statement, 1))!,
                    relativePath: text(statement, 2), fileSize: sqlite3_column_int64(statement, 3),
                    duration: sqlite3_column_double(statement, 4), audioFingerprint: optionalText(statement, 5),
                    firstSeenAt: optionalDate(statement, 6), lastSeenAt: date(statement, 7),
                    isInCurrentSnapshot: sqlite3_column_int(statement, 8) != 0,
                    matchedAt: date(statement, 9),
                    matchMethod: MyMusicTrackMatchMethod(rawValue: text(statement, 10)) ?? .manual,
                    source: MyMusicLinkSource(rawValue: text(statement, 11)) ?? .manual
                )
            }
        }
    }

    public func applyMyMusicLibrarySnapshot(
        _ links: [MyMusicTrackLink], records: [MyMusicTrackRecord], importedAt: Date
    ) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                try execute("UPDATE mymusic_track_links SET in_current_snapshot = 0")
                for link in links { try saveMyMusicTrackLinkStatement(link) }
                for id in records.map(\.trackID) {
                    try update("UPDATE mymusic_track_links SET in_current_snapshot = 1 WHERE mymusic_track_id = ?") {
                        bind(id.uuidString, to: $0, at: 1)
                    }
                }
                try execute("DELETE FROM mymusic_library_play_counts")
                for record in records {
                    guard let playCount = record.playCount else { continue }
                    try update("""
                        INSERT INTO mymusic_library_play_counts(
                            mymusic_track_id, play_count, last_played_at, imported_at
                        ) VALUES(?, ?, ?, ?)
                        """) {
                        bind(record.trackID.uuidString, to: $0, at: 1)
                        bind(playCount, to: $0, at: 2)
                        bind(record.lastPlayedAt?.timeIntervalSince1970, to: $0, at: 3)
                        bind(importedAt.timeIntervalSince1970, to: $0, at: 4)
                    }
                }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func saveMyMusicTrackLinks(_ links: [MyMusicTrackLink]) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for link in links { try saveMyMusicTrackLinkStatement(link) }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func mergeMyMusicPreferences(
        _ preferences: [MyMusicPreferenceRecord], exportedAt: Date
    ) async throws -> MyMusicPreferencesPersistenceResult {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let links = Dictionary(uniqueKeysWithValues: try query(
                    "SELECT mymusic_track_id, home_track_id FROM mymusic_track_links"
                ) { (UUID(uuidString: text($0, 0))!, UUID(uuidString: text($0, 1))!) })
                let existing = Dictionary(uniqueKeysWithValues: try query(
                    "SELECT mymusic_track_id, playback_preference, favorite FROM mymusic_preferences"
                ) { (UUID(uuidString: text($0, 0))!, (Int(sqlite3_column_int64($0, 1)), sqlite3_column_int($0, 2) != 0)) })
                var favoriteIDs = Set(try query("SELECT track_id FROM favorites") { UUID(uuidString: text($0, 0))! })
                var updated = 0, unchanged = 0
                var unresolved: [UUID] = []
                for preference in preferences {
                    guard let homeID = links[preference.trackID] else { unresolved.append(preference.trackID); continue }
                    let favoriteIsCurrent = favoriteIDs.contains(homeID) == preference.favorite
                    if existing[preference.trackID]?.0 == preference.playbackPreference,
                       existing[preference.trackID]?.1 == preference.favorite, favoriteIsCurrent {
                        unchanged += 1; continue
                    }
                    try update("""
                        INSERT INTO mymusic_preferences(
                            home_track_id, mymusic_track_id, playback_preference, favorite, exported_at
                        ) VALUES(?, ?, ?, ?, ?)
                        ON CONFLICT(home_track_id) DO UPDATE SET
                            mymusic_track_id=excluded.mymusic_track_id,
                            playback_preference=excluded.playback_preference,
                            favorite=excluded.favorite, exported_at=excluded.exported_at
                        """) { statement in
                        bind(homeID.uuidString, to: statement, at: 1); bind(preference.trackID.uuidString, to: statement, at: 2)
                        bind(preference.playbackPreference, to: statement, at: 3); bind(preference.favorite ? 1 : 0, to: statement, at: 4)
                        bind(exportedAt.timeIntervalSince1970, to: statement, at: 5)
                    }
                    try update("""
                        INSERT INTO track_preferences(home_track_id, playback_preference, updated_at)
                        VALUES(?, ?, ?)
                        ON CONFLICT(home_track_id) DO UPDATE SET
                            playback_preference=excluded.playback_preference, updated_at=excluded.updated_at
                        """) {
                        bind(homeID.uuidString, to: $0, at: 1)
                        bind(preference.playbackPreference, to: $0, at: 2)
                        bind(exportedAt.timeIntervalSince1970, to: $0, at: 3)
                    }
                    if preference.favorite {
                        try update("INSERT OR IGNORE INTO favorites(track_id, added_at) VALUES(?, ?)") {
                            bind(homeID.uuidString, to: $0, at: 1); bind(exportedAt.timeIntervalSince1970, to: $0, at: 2)
                        }
                        favoriteIDs.insert(homeID)
                    } else {
                        try update("DELETE FROM favorites WHERE track_id = ?") { bind(homeID.uuidString, to: $0, at: 1) }
                        favoriteIDs.remove(homeID)
                    }
                    updated += 1
                }
                try execute("COMMIT")
                return MyMusicPreferencesPersistenceResult(
                    updated: updated, unchanged: unchanged, unresolvedTrackIDs: unresolved
                )
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func loadMyMusicPreferences() async throws -> [PersistedMyMusicPreference] {
        try withLock {
            try query("""
                SELECT home_track_id, mymusic_track_id, playback_preference, favorite, exported_at
                FROM mymusic_preferences ORDER BY mymusic_track_id
                """) {
                PersistedMyMusicPreference(
                    homeStereoTrackID: UUID(uuidString: text($0, 0))!, myMusicTrackID: UUID(uuidString: text($0, 1))!,
                    playbackPreference: Int(sqlite3_column_int64($0, 2)), favorite: sqlite3_column_int($0, 3) != 0,
                    exportedAt: date($0, 4)
                )
            }
        }
    }

    public func appendMyMusicPlaybackEvents(
        _ events: [MyMusicPlaybackEventRecord]
    ) async throws -> MyMusicPlaybackEventsPersistenceResult {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let links = Dictionary(uniqueKeysWithValues: try query(
                    "SELECT mymusic_track_id, home_track_id FROM mymusic_track_links"
                ) { (UUID(uuidString: text($0, 0))!, UUID(uuidString: text($0, 1))!) })
                var existingIDs = Set(try query("SELECT event_id FROM mymusic_playback_events") { text($0, 0) })
                var inserted = 0, duplicates = 0
                var unresolved: [UUID] = []
                for event in events {
                    if existingIDs.contains(event.eventID) { duplicates += 1; continue }
                    guard let homeID = links[event.trackID] else { unresolved.append(event.trackID); continue }
                    try update("""
                        INSERT INTO mymusic_playback_events(
                            event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                            track_duration, completed, skipped, play_source, selection_type, platform, schema_version,
                            ended_at, end_kind
                        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """) { statement in
                        bind(event.eventID, to: statement, at: 1); bind(homeID.uuidString, to: statement, at: 2)
                        bind(event.trackID.uuidString, to: statement, at: 3); bind(event.playedAt.timeIntervalSince1970, to: statement, at: 4)
                        bind(event.playDuration, to: statement, at: 5); bind(event.trackDuration, to: statement, at: 6)
                        bind(event.completed ? 1 : 0, to: statement, at: 7); bind(event.skipped ? 1 : 0, to: statement, at: 8)
                        bind(event.playSource, to: statement, at: 9); bind(event.selectionType, to: statement, at: 10)
                        bind(event.platform, to: statement, at: 11); bind(event.schemaVersion, to: statement, at: 12)
                        bind(event.playedAt.addingTimeInterval(event.playDuration).timeIntervalSince1970, to: statement, at: 13)
                        bind(event.completed ? PlaybackAnalyticsEndKind.natural.rawValue : (event.skipped ? PlaybackAnalyticsEndKind.userSkipped.rawValue : PlaybackAnalyticsEndKind.other.rawValue), to: statement, at: 14)
                    }
                    if sqlite3_changes(database) > 0 {
                        try updatePlaybackSummaryStatements(LocalMyMusicPlaybackEvent(
                            eventID: event.eventID, homeStereoTrackID: homeID,
                            myMusicTrackID: event.trackID, playedAt: event.playedAt,
                            endedAt: event.playedAt.addingTimeInterval(event.playDuration),
                            playDuration: event.playDuration, trackDuration: event.trackDuration,
                            completed: event.completed, skipped: event.skipped,
                            playSource: MyMusicPlaySource(rawValue: event.playSource) ?? .unknown,
                            selectionType: MyMusicSelectionType(rawValue: event.selectionType) ?? .automatic,
                            endKind: event.completed ? .natural : (event.skipped ? .userSkipped : .other),
                            platform: event.platform, schemaVersion: event.schemaVersion
                        ))
                    }
                    existingIDs.insert(event.eventID); inserted += 1
                }
                try execute("COMMIT")
                return MyMusicPlaybackEventsPersistenceResult(
                    inserted: inserted, duplicates: duplicates, unresolvedTrackIDs: unresolved
                )
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    @discardableResult
    public func appendLocalMyMusicPlaybackEvent(_ event: LocalMyMusicPlaybackEvent) async throws -> Bool {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let linkedID = try query(
                    "SELECT mymusic_track_id FROM mymusic_track_links WHERE home_track_id = ?",
                    binds: { bind(event.homeStereoTrackID.uuidString, to: $0, at: 1) }
                ) { optionalText($0, 0) }.first ?? nil
                let externalID = event.myMusicTrackID?.uuidString ?? linkedID
                try update("""
                    INSERT OR IGNORE INTO mymusic_playback_events(
                        event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                        track_duration, completed, skipped, play_source, selection_type, platform, schema_version,
                        ended_at, end_kind
                    ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """) { statement in
                    bind(event.eventID, to: statement, at: 1)
                    bind(event.homeStereoTrackID.uuidString, to: statement, at: 2)
                    bind(externalID, to: statement, at: 3)
                    bind(event.playedAt.timeIntervalSince1970, to: statement, at: 4)
                    bind(event.playDuration, to: statement, at: 5)
                    bind(event.trackDuration, to: statement, at: 6)
                    bind(event.completed ? 1 : 0, to: statement, at: 7)
                    bind(event.skipped ? 1 : 0, to: statement, at: 8)
                    bind(event.playSource.rawValue, to: statement, at: 9)
                    bind(event.selectionType.rawValue, to: statement, at: 10)
                    bind(event.platform, to: statement, at: 11)
                    bind(event.schemaVersion, to: statement, at: 12)
                    bind(event.endedAt.timeIntervalSince1970, to: statement, at: 13)
                    bind(event.endKind.rawValue, to: statement, at: 14)
                }
                let inserted = sqlite3_changes(database) > 0
                if inserted { try updatePlaybackSummaryStatements(event) }
                try execute("COMMIT")
                return inserted
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func loadMyMusicPlaybackEvents() async throws -> [PersistedMyMusicPlaybackEvent] {
        try withLock {
            try query("""
                SELECT event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                       track_duration, completed, skipped, play_source, selection_type, platform, schema_version,
                       ended_at, end_kind
                FROM mymusic_playback_events ORDER BY played_at, event_id
                """) {
                PersistedMyMusicPlaybackEvent(
                    eventID: text($0, 0), homeStereoTrackID: UUID(uuidString: text($0, 1))!,
                    myMusicTrackID: optionalText($0, 2).flatMap(UUID.init(uuidString:)), playedAt: date($0, 3),
                    endedAt: date($0, 12),
                    playDuration: sqlite3_column_double($0, 4), trackDuration: sqlite3_column_double($0, 5),
                    completed: sqlite3_column_int($0, 6) != 0, skipped: sqlite3_column_int($0, 7) != 0,
                    playSource: text($0, 8), selectionType: text($0, 9),
                    endKind: PlaybackAnalyticsEndKind(rawValue: text($0, 13)) ?? .other,
                    platform: text($0, 10),
                    schemaVersion: Int(sqlite3_column_int64($0, 11))
                )
            }
        }
    }

    public func loadAnalyticsContext() async throws -> AnalyticsContext {
        async let tracks = loadTracks(folderID: nil)
        async let events = loadMyMusicPlaybackEvents()
        async let favorites = loadFavorites()
        async let playlists = loadPlaylists()
        async let preferences = loadTrackPreferences()
        async let myMusicPlayCounts = loadMyMusicPlayCounts()
        return try await AnalyticsContext(
            tracks: tracks, events: events, favorites: favorites,
            preferences: preferences, playlists: playlists,
            myMusicPlayCounts: myMusicPlayCounts
        )
    }

    public func loadMyMusicPlayCounts() async throws -> [PersistedMyMusicPlayCount] {
        try withLock {
            try query("""
                SELECT c.mymusic_track_id, l.home_track_id, c.play_count,
                       c.last_played_at, c.imported_at
                FROM mymusic_library_play_counts c
                LEFT JOIN mymusic_track_links l
                  ON l.mymusic_track_id = c.mymusic_track_id
                 AND l.in_current_snapshot = 1
                ORDER BY c.mymusic_track_id
                """) {
                PersistedMyMusicPlayCount(
                    myMusicTrackID: UUID(uuidString: text($0, 0))!,
                    homeStereoTrackID: optionalText($0, 1).flatMap(UUID.init(uuidString:)),
                    playCount: Int(sqlite3_column_int64($0, 2)),
                    lastPlayedAt: optionalDate($0, 3), importedAt: date($0, 4)
                )
            }
        }
    }

    public func saveTrackPreference(_ preference: TrackPreference) async throws {
        try withLock {
            try update("""
                INSERT INTO track_preferences(home_track_id, playback_preference, updated_at)
                VALUES(?, ?, ?)
                ON CONFLICT(home_track_id) DO UPDATE SET
                    playback_preference=excluded.playback_preference, updated_at=excluded.updated_at
                """) {
                bind(preference.trackID.uuidString, to: $0, at: 1)
                bind(preference.playbackPreference, to: $0, at: 2)
                bind(preference.updatedAt.timeIntervalSince1970, to: $0, at: 3)
            }
        }
    }

    public func deleteAnalyticsHistory(trackID: Track.ID?) async throws {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                if let trackID {
                    try update("DELETE FROM mymusic_playback_events WHERE home_track_id = ?") {
                        bind(trackID.uuidString, to: $0, at: 1)
                    }
                    try update("DELETE FROM playback_events WHERE track_id = ?") {
                        bind(trackID.uuidString, to: $0, at: 1)
                    }
                } else {
                    try execute("DELETE FROM mymusic_playback_events")
                    try execute("DELETE FROM playback_events")
                }
                try rebuildPlaybackSummariesStatements()
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    public func loadTrackPreferences() async throws -> [TrackPreference] {
        try withLock {
            try query("SELECT home_track_id, playback_preference, updated_at FROM track_preferences ORDER BY home_track_id") {
                TrackPreference(
                    trackID: UUID(uuidString: text($0, 0))!,
                    playbackPreference: Int(sqlite3_column_int64($0, 1)), updatedAt: date($0, 2)
                )
            }
        }
    }

    public func loadMyMusicLibraryRecords() async throws -> [MyMusicTrackRecord] {
        let context = try await loadMyMusicMatchContext()
        let tracks = Dictionary(uniqueKeysWithValues: context.tracks.map { ($0.id, $0) })
        return context.links.compactMap { link in
            guard let track = tracks[link.homeStereoTrackID] else { return nil }
            let fileFormat = track.fileExtension.uppercased()
            return MyMusicTrackRecord(
                trackID: link.myMusicTrackID, title: track.title, artist: track.artist ?? "",
                album: track.album, genre: track.genre, year: track.releaseYear, duration: track.duration,
                format: ["FLAC", "ALAC", "AAC", "MP3", "WAV", "AIFF"].contains(fileFormat) ? fileFormat : nil,
                audioFingerprint: link.audioFingerprint,
                relativePath: track.relativePath, fileSize: track.fileSize
            )
        }
    }

    public func loadMyMusicPlaybackEventRecords() async throws -> [MyMusicPlaybackEventRecord] {
        let persisted = try await loadMyMusicPlaybackEvents()
        let tracks = Dictionary(uniqueKeysWithValues: try await loadTracks(folderID: nil).map { ($0.id, $0) })
        let links = Dictionary(uniqueKeysWithValues: try await loadMyMusicTrackLinks().map {
            ($0.homeStereoTrackID, $0.myMusicTrackID)
        })
        return persisted.compactMap { event in
            guard let track = tracks[event.homeStereoTrackID],
                  let externalID = event.myMusicTrackID ?? links[event.homeStereoTrackID] else { return nil }
            return MyMusicPlaybackEventRecord(
                eventID: event.eventID, trackID: externalID, trackTitle: track.title,
                artist: track.artist ?? "", album: track.album, playedAt: event.playedAt,
                playDuration: event.playDuration, trackDuration: event.trackDuration,
                completed: event.completed, skipped: event.skipped, playSource: event.playSource,
                selectionType: event.selectionType, platform: event.platform, schemaVersion: event.schemaVersion
            )
        }
    }

    public func loadMyMusicPlaylistContext() async throws -> (
        playlists: [Playlist], tracks: [Track], links: [MyMusicTrackLink]
    ) {
        (try await loadPlaylists(), try await loadTracks(folderID: nil), try await loadMyMusicTrackLinks())
    }

    public func mergeMyMusicPlaylists(
        _ imported: [MyMusicPlaylistRecord]
    ) async throws -> MyMusicPlaylistPersistenceResult {
        try withLock {
            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                let links = Dictionary(grouping: try query(
                    "SELECT mymusic_track_id, home_track_id FROM mymusic_track_links"
                ) { (UUID(uuidString: text($0, 0))!, UUID(uuidString: text($0, 1))!) }, by: \.0)
                var existing = try query(
                    "SELECT id, mymusic_playlist_id, name, created_at, updated_at, kind, tags_json FROM playlists"
                ) { statement in
                    (id: UUID(uuidString: text(statement, 0))!,
                     externalID: optionalText(statement, 1).flatMap(UUID.init(uuidString:)),
                     name: text(statement, 2), createdAt: date(statement, 3), updatedAt: date(statement, 4),
                     kind: text(statement, 5), tags: Self.decodeTags(text(statement, 6)))
                }
                var added = 0, updated = 0, unchanged = 0, importedTracks = 0
                var unresolved: [UUID] = [], conflicts: [UUID] = []
                var processedPlaylistIDs = Set<UUID>()
                for value in imported {
                    guard processedPlaylistIDs.insert(value.playlistID).inserted else {
                        throw UserFacingError.persistenceFailed("playlistIDが重複しています。")
                    }
                    let candidates = existing.filter {
                        $0.externalID == value.playlistID || ($0.externalID == nil && $0.id == value.playlistID)
                    }
                    guard candidates.count <= 1 else {
                        throw UserFacingError.persistenceFailed("同じMyMusic playlistIDのプレイリストが複数あります。")
                    }
                    let localID = candidates.first?.id ?? UUID()
                    var trackIDs: [Track.ID] = []
                    for track in value.tracks {
                        guard let matches = links[track.trackID], !matches.isEmpty else {
                            unresolved.append(track.trackID); continue
                        }
                        guard matches.count == 1, let homeID = matches.first?.1 else {
                            conflicts.append(track.trackID); continue
                        }
                        trackIDs.append(homeID); importedTracks += 1
                    }
                    let oldTrackIDs = try query(
                        "SELECT track_id FROM playlist_items WHERE playlist_id = ? ORDER BY position",
                        binds: { bind(localID.uuidString, to: $0, at: 1) }
                    ) { UUID(uuidString: text($0, 0))! }
                    let old = candidates.first
                    let isUnchanged = old?.externalID == value.playlistID && old?.name == value.name
                        && old?.createdAt == value.createdAt && old?.updatedAt == value.updatedAt
                        && old?.kind == value.kind && old?.tags == value.tags && oldTrackIDs == trackIDs
                    if isUnchanged { unchanged += 1; continue }
                    try update("""
                        INSERT INTO playlists(id, mymusic_playlist_id, name, created_at, updated_at, kind, tags_json)
                        VALUES(?, ?, ?, ?, ?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET mymusic_playlist_id=excluded.mymusic_playlist_id,
                            name=excluded.name, created_at=excluded.created_at, updated_at=excluded.updated_at,
                            kind=excluded.kind, tags_json=excluded.tags_json
                        """) { statement in
                        bind(localID.uuidString, to: statement, at: 1); bind(value.playlistID.uuidString, to: statement, at: 2)
                        bind(value.name, to: statement, at: 3); bind(value.createdAt.timeIntervalSince1970, to: statement, at: 4)
                        bind(value.updatedAt.timeIntervalSince1970, to: statement, at: 5); bind(value.kind, to: statement, at: 6)
                        bind(Self.encodeTags(value.tags), to: statement, at: 7)
                    }
                    try update("DELETE FROM playlist_items WHERE playlist_id = ?") { bind(localID.uuidString, to: $0, at: 1) }
                    for (position, trackID) in trackIDs.enumerated() {
                        try update("INSERT INTO playlist_items(playlist_id, position, id, track_id) VALUES(?, ?, ?, ?)") {
                            bind(localID.uuidString, to: $0, at: 1); bind(position, to: $0, at: 2)
                            bind(UUID().uuidString, to: $0, at: 3); bind(trackID.uuidString, to: $0, at: 4)
                        }
                    }
                    if old == nil {
                        added += 1
                        existing.append((localID, value.playlistID, value.name, value.createdAt, value.updatedAt, value.kind, value.tags))
                    } else { updated += 1 }
                }
                try execute("COMMIT")
                return MyMusicPlaylistPersistenceResult(
                    addedPlaylists: added, updatedPlaylists: updated, unchangedPlaylists: unchanged,
                    importedTracks: importedTracks, unresolvedTrackIDs: unresolved,
                    conflictedTrackIDs: conflicts
                )
            } catch { try? execute("ROLLBACK"); throw error }
        }
    }

    private func savePlaylistStatements(_ playlist: Playlist) throws {
        let persistedUpdatedAt = try query(
            "SELECT updated_at FROM playlists WHERE id = ?", binds: { bind(playlist.id.uuidString, to: $0, at: 1) }
        ) { sqlite3_column_double($0, 0) }.first
        guard persistedUpdatedAt.map({ $0 <= playlist.updatedAt.timeIntervalSince1970 }) ?? true else { return }
        try update("""
            INSERT INTO playlists(id, mymusic_playlist_id, name, created_at, updated_at, kind, tags_json)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET mymusic_playlist_id=excluded.mymusic_playlist_id,
                name=excluded.name, updated_at=excluded.updated_at, kind=excluded.kind, tags_json=excluded.tags_json
            """) {
            bind(playlist.id.uuidString, to: $0, at: 1); bind(playlist.myMusicPlaylistID?.uuidString, to: $0, at: 2)
            bind(playlist.name, to: $0, at: 3); bind(playlist.createdAt.timeIntervalSince1970, to: $0, at: 4)
            bind(playlist.updatedAt.timeIntervalSince1970, to: $0, at: 5); bind(playlist.kind, to: $0, at: 6)
            bind(Self.encodeTags(playlist.tags), to: $0, at: 7)
        }
        try update("DELETE FROM playlist_items WHERE playlist_id = ?") { bind(playlist.id.uuidString, to: $0, at: 1) }
        for (position, item) in playlist.items.enumerated() {
            try update("INSERT INTO playlist_items(playlist_id, position, id, track_id) VALUES(?, ?, ?, ?)") {
                bind(playlist.id.uuidString, to: $0, at: 1); bind(position, to: $0, at: 2)
                bind(item.id.uuidString, to: $0, at: 3); bind(item.trackID.uuidString, to: $0, at: 4)
            }
        }
    }

    private func rebuildPlaybackSummariesStatements() throws {
        try execute("DELETE FROM playback_track_summaries")
        try execute("DELETE FROM playback_daily_summaries")
        try execute("DELETE FROM playback_source_summaries")
        let events = try query("""
            SELECT event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                   track_duration, completed, skipped, play_source, selection_type, platform,
                   schema_version, ended_at, end_kind
            FROM mymusic_playback_events ORDER BY played_at, event_id
            """) { statement in
            LocalMyMusicPlaybackEvent(
                eventID: text(statement, 0), homeStereoTrackID: UUID(uuidString: text(statement, 1))!,
                myMusicTrackID: optionalText(statement, 2).flatMap(UUID.init(uuidString:)),
                playedAt: date(statement, 3), endedAt: date(statement, 12),
                playDuration: sqlite3_column_double(statement, 4),
                trackDuration: sqlite3_column_double(statement, 5),
                completed: sqlite3_column_int(statement, 6) != 0,
                skipped: sqlite3_column_int(statement, 7) != 0,
                playSource: MyMusicPlaySource(rawValue: text(statement, 8)) ?? .unknown,
                selectionType: MyMusicSelectionType(rawValue: text(statement, 9)) ?? .automatic,
                endKind: PlaybackAnalyticsEndKind(rawValue: text(statement, 13)) ?? .other,
                platform: text(statement, 10), schemaVersion: Int(sqlite3_column_int64(statement, 11))
            )
        }
        for event in events { try updatePlaybackSummaryStatements(event) }
    }

    private func updatePlaybackSummaryStatements(_ event: LocalMyMusicPlaybackEvent) throws {
        let played = MyMusicPlaybackPolicy.countsAsPlay(
            listenedSeconds: event.playDuration, trackDuration: event.trackDuration
        )
        let earlySkip = MyMusicPlaybackPolicy.isEarlySkip(
            skipped: event.skipped, listenedSeconds: event.playDuration
        )
        let previousTrackID = try query("""
            SELECT home_track_id FROM mymusic_playback_events
            WHERE played_at < ? OR (played_at = ? AND event_id < ?)
            ORDER BY played_at DESC, event_id DESC LIMIT 1
            """, binds: {
            bind(event.playedAt.timeIntervalSince1970, to: $0, at: 1)
            bind(event.playedAt.timeIntervalSince1970, to: $0, at: 2)
            bind(event.eventID, to: $0, at: 3)
        }) { text($0, 0) }.first
        let repeated = previousTrackID == event.homeStereoTrackID.uuidString
        let duration = event.playDuration.isFinite ? max(0, event.playDuration) : 0
        let manual = event.selectionType == .manual ? 1 : 0
        let automatic = event.selectionType == .automatic ? 1 : 0
        let advanced = event.selectionType == .userAdvanced ? 1 : 0

        try update("""
            INSERT INTO playback_track_summaries(
                home_track_id, play_count, first_played_at, last_played_at,
                manual_play_count, automatic_play_count, user_advanced_play_count,
                total_playback_duration, full_playback_count, skip_count, early_skip_count,
                consecutive_play_count, repeat_playback_count
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(home_track_id) DO UPDATE SET
                play_count=play_count+excluded.play_count,
                first_played_at=MIN(first_played_at, excluded.first_played_at),
                last_played_at=MAX(last_played_at, excluded.last_played_at),
                manual_play_count=manual_play_count+excluded.manual_play_count,
                automatic_play_count=automatic_play_count+excluded.automatic_play_count,
                user_advanced_play_count=user_advanced_play_count+excluded.user_advanced_play_count,
                total_playback_duration=total_playback_duration+excluded.total_playback_duration,
                full_playback_count=full_playback_count+excluded.full_playback_count,
                skip_count=skip_count+excluded.skip_count,
                early_skip_count=early_skip_count+excluded.early_skip_count,
                consecutive_play_count=consecutive_play_count+excluded.consecutive_play_count,
                repeat_playback_count=repeat_playback_count+excluded.repeat_playback_count
            """) { statement in
            bind(event.homeStereoTrackID.uuidString, to: statement, at: 1)
            bind(played ? 1 : 0, to: statement, at: 2)
            bind(event.playedAt.timeIntervalSince1970, to: statement, at: 3)
            bind(event.playedAt.timeIntervalSince1970, to: statement, at: 4)
            bind(manual, to: statement, at: 5); bind(automatic, to: statement, at: 6)
            bind(advanced, to: statement, at: 7); bind(duration, to: statement, at: 8)
            bind(event.completed ? 1 : 0, to: statement, at: 9)
            bind(event.skipped ? 1 : 0, to: statement, at: 10)
            bind(earlySkip ? 1 : 0, to: statement, at: 11)
            bind(repeated ? 1 : 0, to: statement, at: 12)
            bind(repeated && event.selectionType == .automatic ? 1 : 0, to: statement, at: 13)
        }

        let day = Self.analyticsDayKey(event.playedAt)
        try update("""
            INSERT INTO playback_daily_summaries(
                day, play_count, manual_play_count, automatic_play_count,
                user_advanced_play_count, full_playback_count, skip_count,
                early_skip_count, total_playback_duration
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(day) DO UPDATE SET
                play_count=play_count+excluded.play_count,
                manual_play_count=manual_play_count+excluded.manual_play_count,
                automatic_play_count=automatic_play_count+excluded.automatic_play_count,
                user_advanced_play_count=user_advanced_play_count+excluded.user_advanced_play_count,
                full_playback_count=full_playback_count+excluded.full_playback_count,
                skip_count=skip_count+excluded.skip_count,
                early_skip_count=early_skip_count+excluded.early_skip_count,
                total_playback_duration=total_playback_duration+excluded.total_playback_duration
            """) { statement in
            bind(day, to: statement, at: 1); bind(played ? 1 : 0, to: statement, at: 2)
            bind(manual, to: statement, at: 3); bind(automatic, to: statement, at: 4)
            bind(advanced, to: statement, at: 5); bind(event.completed ? 1 : 0, to: statement, at: 6)
            bind(event.skipped ? 1 : 0, to: statement, at: 7); bind(earlySkip ? 1 : 0, to: statement, at: 8)
            bind(duration, to: statement, at: 9)
        }

        try update("""
            INSERT INTO playback_source_summaries(day, home_track_id, source, session_count, play_count)
            VALUES(?, ?, ?, 1, ?)
            ON CONFLICT(day, home_track_id, source) DO UPDATE SET
                session_count=session_count+1, play_count=play_count+excluded.play_count
            """) {
            bind(day, to: $0, at: 1); bind(event.homeStereoTrackID.uuidString, to: $0, at: 2)
            bind(event.playSource.rawValue, to: $0, at: 3); bind(played ? 1 : 0, to: $0, at: 4)
        }
    }

    private static func analyticsDayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func migrate() throws {
        let startingSchemaVersion = Int(try scalarInt("PRAGMA user_version"))
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try execute("""
        CREATE TABLE IF NOT EXISTS library_folders(
            id TEXT PRIMARY KEY, display_name TEXT NOT NULL, path TEXT NOT NULL,
            normalized_path TEXT NOT NULL UNIQUE, bookmark BLOB NOT NULL,
            access_state TEXT NOT NULL, last_scanned_at REAL
        );
        CREATE TABLE IF NOT EXISTS tracks(
            id TEXT PRIMARY KEY, folder_id TEXT NOT NULL REFERENCES library_folders(id) ON DELETE CASCADE,
            relative_path TEXT NOT NULL, normalized_path TEXT NOT NULL, file_size INTEGER NOT NULL,
            modification_date REAL NOT NULL, title TEXT NOT NULL, artist TEXT, album_artist TEXT,
            album TEXT, genre TEXT, composer TEXT, release_year INTEGER, track_number INTEGER,
            track_total INTEGER, disc_number INTEGER, disc_total INTEGER, duration REAL NOT NULL,
            file_extension TEXT NOT NULL, codec TEXT, sample_rate REAL, bit_depth INTEGER,
            channel_count INTEGER, has_artwork INTEGER NOT NULL, scan_state TEXT NOT NULL,
            metadata_version INTEGER NOT NULL, last_scanned_at REAL NOT NULL,
            file_resource_identifier BLOB, bit_rate REAL,
            UNIQUE(folder_id, normalized_path)
        );
        CREATE TABLE IF NOT EXISTS library_metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS playback_queue(
            position INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE, track_id TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS queue_state(
            singleton INTEGER PRIMARY KEY CHECK(singleton = 1), current_index INTEGER,
            repeat_mode TEXT NOT NULL, shuffle_enabled INTEGER NOT NULL, position REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS playlists(
            id TEXT PRIMARY KEY, mymusic_playlist_id TEXT UNIQUE, name TEXT NOT NULL,
            created_at REAL NOT NULL, updated_at REAL NOT NULL,
            kind TEXT NOT NULL DEFAULT 'regular', tags_json TEXT NOT NULL DEFAULT '[]'
        );
        CREATE TABLE IF NOT EXISTS playlist_items(
            playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            position INTEGER NOT NULL, id TEXT NOT NULL UNIQUE, track_id TEXT NOT NULL,
            PRIMARY KEY(playlist_id, position)
        );
        CREATE TABLE IF NOT EXISTS favorites(
            track_id TEXT PRIMARY KEY, added_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS playback_events(
            id TEXT PRIMARY KEY, track_id TEXT NOT NULL, started_at REAL NOT NULL,
            played_seconds REAL NOT NULL CHECK(played_seconds >= 0), outcome TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS mymusic_track_links(
            home_track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            mymusic_track_id TEXT NOT NULL UNIQUE, relative_path TEXT NOT NULL,
            file_size INTEGER NOT NULL CHECK(file_size >= 0), duration REAL NOT NULL CHECK(duration >= 0),
            audio_fingerprint TEXT, first_seen_at REAL, last_seen_at REAL NOT NULL DEFAULT 0,
            in_current_snapshot INTEGER NOT NULL DEFAULT 1 CHECK(in_current_snapshot IN (0, 1)),
            matched_at REAL NOT NULL, match_method TEXT NOT NULL, source TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS mymusic_preferences(
            home_track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            mymusic_track_id TEXT NOT NULL UNIQUE, playback_preference INTEGER NOT NULL,
            favorite INTEGER NOT NULL, exported_at REAL NOT NULL,
            CHECK(playback_preference BETWEEN -10 AND 10), CHECK(favorite IN (0, 1))
        );
        CREATE TABLE IF NOT EXISTS mymusic_library_play_counts(
            mymusic_track_id TEXT PRIMARY KEY,
            play_count INTEGER NOT NULL CHECK(play_count >= 0),
            last_played_at REAL, imported_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS mymusic_playback_events(
            event_id TEXT PRIMARY KEY, home_track_id TEXT NOT NULL,
            mymusic_track_id TEXT, played_at REAL NOT NULL,
            play_duration REAL NOT NULL CHECK(play_duration >= 0),
            track_duration REAL NOT NULL CHECK(track_duration >= 0),
            completed INTEGER NOT NULL CHECK(completed IN (0, 1)),
            skipped INTEGER NOT NULL CHECK(skipped IN (0, 1)),
            play_source TEXT NOT NULL, selection_type TEXT NOT NULL,
            platform TEXT NOT NULL, schema_version INTEGER NOT NULL,
            ended_at REAL NOT NULL, end_kind TEXT NOT NULL DEFAULT 'other',
            CHECK(NOT(completed = 1 AND skipped = 1))
        );
        CREATE TABLE IF NOT EXISTS track_preferences(
            home_track_id TEXT PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            playback_preference INTEGER NOT NULL CHECK(playback_preference BETWEEN -10 AND 10),
            updated_at REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS playback_track_summaries(
            home_track_id TEXT PRIMARY KEY,
            play_count INTEGER NOT NULL DEFAULT 0,
            first_played_at REAL, last_played_at REAL,
            manual_play_count INTEGER NOT NULL DEFAULT 0,
            automatic_play_count INTEGER NOT NULL DEFAULT 0,
            user_advanced_play_count INTEGER NOT NULL DEFAULT 0,
            total_playback_duration REAL NOT NULL DEFAULT 0,
            full_playback_count INTEGER NOT NULL DEFAULT 0,
            skip_count INTEGER NOT NULL DEFAULT 0,
            early_skip_count INTEGER NOT NULL DEFAULT 0,
            consecutive_play_count INTEGER NOT NULL DEFAULT 0,
            repeat_playback_count INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS playback_daily_summaries(
            day TEXT PRIMARY KEY,
            play_count INTEGER NOT NULL DEFAULT 0,
            manual_play_count INTEGER NOT NULL DEFAULT 0,
            automatic_play_count INTEGER NOT NULL DEFAULT 0,
            user_advanced_play_count INTEGER NOT NULL DEFAULT 0,
            full_playback_count INTEGER NOT NULL DEFAULT 0,
            skip_count INTEGER NOT NULL DEFAULT 0,
            early_skip_count INTEGER NOT NULL DEFAULT 0,
            total_playback_duration REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS playback_source_summaries(
            day TEXT NOT NULL,
            home_track_id TEXT NOT NULL,
            source TEXT NOT NULL,
            session_count INTEGER NOT NULL DEFAULT 0,
            play_count INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(day, home_track_id, source)
        );
        CREATE TABLE IF NOT EXISTS genre_display_presets(
            id TEXT PRIMARY KEY, name TEXT NOT NULL, normalized_name TEXT NOT NULL UNIQUE,
            enabled_genre_names TEXT NOT NULL,
            includes_unassigned_genre_setting INTEGER,
            position INTEGER NOT NULL UNIQUE,
            CHECK(includes_unassigned_genre_setting IS NULL OR includes_unassigned_genre_setting IN (0, 1))
        );
        CREATE INDEX IF NOT EXISTS idx_tracks_folder_relative ON tracks(folder_id, relative_path);
        CREATE INDEX IF NOT EXISTS idx_tracks_artist ON tracks(artist COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_tracks_album ON tracks(album_artist COLLATE NOCASE, album COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_tracks_title ON tracks(title COLLATE NOCASE);
        CREATE INDEX IF NOT EXISTS idx_mymusic_events_home_played ON mymusic_playback_events(home_track_id, played_at DESC);
        CREATE INDEX IF NOT EXISTS idx_mymusic_events_played ON mymusic_playback_events(played_at DESC);
        """)
            let columns = try query("PRAGMA table_info(tracks)") { text($0, 1) }
            if !columns.contains("file_resource_identifier") {
                try execute("ALTER TABLE tracks ADD COLUMN file_resource_identifier BLOB")
            }
            if !columns.contains("audio_fingerprint") {
                try execute("ALTER TABLE tracks ADD COLUMN audio_fingerprint TEXT")
            }
            if !columns.contains("bit_rate") {
                try execute("ALTER TABLE tracks ADD COLUMN bit_rate REAL")
            }
            let playlistColumns = try query("PRAGMA table_info(playlists)") { text($0, 1) }
            if !playlistColumns.contains("mymusic_playlist_id") {
                try execute("ALTER TABLE playlists ADD COLUMN mymusic_playlist_id TEXT")
            }
            if !playlistColumns.contains("kind") {
                try execute("ALTER TABLE playlists ADD COLUMN kind TEXT NOT NULL DEFAULT 'regular'")
            }
            if !playlistColumns.contains("tags_json") {
                try execute("ALTER TABLE playlists ADD COLUMN tags_json TEXT NOT NULL DEFAULT '[]'")
            }
            let linkColumns = try query("PRAGMA table_info(mymusic_track_links)") { text($0, 1) }
            if !linkColumns.contains("first_seen_at") {
                try execute("ALTER TABLE mymusic_track_links ADD COLUMN first_seen_at REAL")
            }
            if !linkColumns.contains("last_seen_at") {
                try execute("ALTER TABLE mymusic_track_links ADD COLUMN last_seen_at REAL NOT NULL DEFAULT 0")
                try execute("UPDATE mymusic_track_links SET last_seen_at = matched_at WHERE last_seen_at = 0")
            }
            if !linkColumns.contains("in_current_snapshot") {
                try execute("ALTER TABLE mymusic_track_links ADD COLUMN in_current_snapshot INTEGER NOT NULL DEFAULT 1")
            }
            let eventTrackIDIsRequired = try query("PRAGMA table_info(mymusic_playback_events)") {
                (name: text($0, 1), required: sqlite3_column_int($0, 3) != 0)
            }.contains { $0.name == "mymusic_track_id" && $0.required }
            if eventTrackIDIsRequired {
                try execute("""
                    ALTER TABLE mymusic_playback_events RENAME TO mymusic_playback_events_v8;
                    CREATE TABLE mymusic_playback_events(
                        event_id TEXT PRIMARY KEY,
                        home_track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
                        mymusic_track_id TEXT, played_at REAL NOT NULL,
                        play_duration REAL NOT NULL CHECK(play_duration >= 0),
                        track_duration REAL NOT NULL CHECK(track_duration >= 0),
                        completed INTEGER NOT NULL CHECK(completed IN (0, 1)),
                        skipped INTEGER NOT NULL CHECK(skipped IN (0, 1)),
                        play_source TEXT NOT NULL, selection_type TEXT NOT NULL,
                        platform TEXT NOT NULL, schema_version INTEGER NOT NULL,
                        CHECK(NOT(completed = 1 AND skipped = 1))
                    );
                    INSERT INTO mymusic_playback_events SELECT * FROM mymusic_playback_events_v8;
                    DROP TABLE mymusic_playback_events_v8;
                    """)
            }
            let analyticsEventColumns = try query("PRAGMA table_info(mymusic_playback_events)") { text($0, 1) }
            if !analyticsEventColumns.contains("ended_at") {
                try execute("ALTER TABLE mymusic_playback_events ADD COLUMN ended_at REAL NOT NULL DEFAULT 0")
                try execute("UPDATE mymusic_playback_events SET ended_at = played_at + play_duration WHERE ended_at = 0")
            }
            if !analyticsEventColumns.contains("end_kind") {
                try execute("ALTER TABLE mymusic_playback_events ADD COLUMN end_kind TEXT NOT NULL DEFAULT 'other'")
                try execute("UPDATE mymusic_playback_events SET end_kind = CASE WHEN completed = 1 THEN 'natural' WHEN skipped = 1 THEN 'user_skipped' ELSE 'other' END")
            }
            if startingSchemaVersion < 11 {
                if startingSchemaVersion > 0 {
                    try execute("""
                        ALTER TABLE mymusic_playback_events RENAME TO mymusic_playback_events_pre_analytics;
                        CREATE TABLE mymusic_playback_events(
                            event_id TEXT PRIMARY KEY, home_track_id TEXT NOT NULL,
                            mymusic_track_id TEXT, played_at REAL NOT NULL,
                            play_duration REAL NOT NULL CHECK(play_duration >= 0),
                            track_duration REAL NOT NULL CHECK(track_duration >= 0),
                            completed INTEGER NOT NULL CHECK(completed IN (0, 1)),
                            skipped INTEGER NOT NULL CHECK(skipped IN (0, 1)),
                            play_source TEXT NOT NULL, selection_type TEXT NOT NULL,
                            platform TEXT NOT NULL, schema_version INTEGER NOT NULL,
                            ended_at REAL NOT NULL, end_kind TEXT NOT NULL DEFAULT 'other',
                            CHECK(NOT(completed = 1 AND skipped = 1))
                        );
                        INSERT INTO mymusic_playback_events(
                            event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                            track_duration, completed, skipped, play_source, selection_type,
                            platform, schema_version, ended_at, end_kind
                        ) SELECT event_id, home_track_id, mymusic_track_id, played_at, play_duration,
                            track_duration, completed, skipped, play_source, selection_type,
                            platform, schema_version, ended_at, end_kind
                          FROM mymusic_playback_events_pre_analytics;
                        DROP TABLE mymusic_playback_events_pre_analytics;
                        """)
                }
                try execute("""
                    INSERT OR REPLACE INTO track_preferences(home_track_id, playback_preference, updated_at)
                    SELECT home_track_id, playback_preference, exported_at FROM mymusic_preferences
                    """)
                try rebuildPlaybackSummariesStatements()
            }
            try execute("CREATE INDEX IF NOT EXISTS idx_tracks_audio_fingerprint ON tracks(audio_fingerprint)")
            try execute("CREATE INDEX IF NOT EXISTS idx_mymusic_events_track ON mymusic_playback_events(mymusic_track_id, played_at)")
            try execute("CREATE INDEX IF NOT EXISTS idx_mymusic_events_home_played ON mymusic_playback_events(home_track_id, played_at DESC)")
            try execute("CREATE INDEX IF NOT EXISTS idx_mymusic_events_played ON mymusic_playback_events(played_at DESC)")
            try execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_playlists_mymusic_id ON playlists(mymusic_playlist_id) WHERE mymusic_playlist_id IS NOT NULL")
            try execute("PRAGMA user_version = \(Self.currentSchemaVersion)")
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func upsert(_ track: Track) throws {
        let sql = """
        INSERT INTO tracks(
          id, folder_id, relative_path, normalized_path, file_size, modification_date,
          title, artist, album_artist, album, genre, composer, release_year, track_number,
          track_total, disc_number, disc_total, duration, file_extension, codec, sample_rate,
          bit_depth, channel_count, has_artwork, scan_state, metadata_version, last_scanned_at,
          file_resource_identifier, audio_fingerprint, bit_rate
        ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(folder_id, normalized_path) DO UPDATE SET
          id=excluded.id, relative_path=excluded.relative_path, file_size=excluded.file_size,
          modification_date=excluded.modification_date, title=excluded.title, artist=excluded.artist,
          album_artist=excluded.album_artist, album=excluded.album, genre=excluded.genre,
          composer=excluded.composer, release_year=excluded.release_year, track_number=excluded.track_number,
          track_total=excluded.track_total, disc_number=excluded.disc_number, disc_total=excluded.disc_total,
          duration=excluded.duration, file_extension=excluded.file_extension, codec=excluded.codec,
          sample_rate=excluded.sample_rate, bit_depth=excluded.bit_depth, channel_count=excluded.channel_count,
          has_artwork=excluded.has_artwork, scan_state=excluded.scan_state,
          metadata_version=excluded.metadata_version, last_scanned_at=excluded.last_scanned_at,
          file_resource_identifier=excluded.file_resource_identifier,
          audio_fingerprint=excluded.audio_fingerprint, bit_rate=excluded.bit_rate
        WHERE tracks.file_size != excluded.file_size
           OR tracks.modification_date != excluded.modification_date
           OR tracks.scan_state != excluded.scan_state
           OR tracks.metadata_version != excluded.metadata_version
           OR tracks.relative_path != excluded.relative_path
           OR tracks.file_resource_identifier IS NOT excluded.file_resource_identifier
           OR tracks.audio_fingerprint IS NOT excluded.audio_fingerprint
           OR tracks.bit_rate IS NOT excluded.bit_rate
        """
        try update(sql) { s in
            bind(track.id.uuidString, to: s, at: 1); bind(track.libraryFolderID.uuidString, to: s, at: 2)
            bind(track.relativePath, to: s, at: 3); bind(LibraryService.normalizedRelativePath(track.relativePath), to: s, at: 4)
            bind(track.fileSize, to: s, at: 5); bind(track.modificationDate.timeIntervalSince1970, to: s, at: 6)
            bind(track.title, to: s, at: 7); bind(track.artist, to: s, at: 8); bind(track.albumArtist, to: s, at: 9)
            bind(track.album, to: s, at: 10); bind(track.genre, to: s, at: 11); bind(track.composer, to: s, at: 12)
            bind(track.releaseYear, to: s, at: 13); bind(track.trackNumber, to: s, at: 14); bind(track.trackTotal, to: s, at: 15)
            bind(track.discNumber, to: s, at: 16); bind(track.discTotal, to: s, at: 17); bind(track.duration, to: s, at: 18)
            bind(track.fileExtension, to: s, at: 19); bind(track.codec, to: s, at: 20); bind(track.sampleRate, to: s, at: 21)
            bind(track.bitDepth, to: s, at: 22); bind(track.channelCount, to: s, at: 23); bind(track.hasArtwork ? 1 : 0, to: s, at: 24)
            bind(track.scanState.rawValue, to: s, at: 25); bind(track.metadataSchemaVersion, to: s, at: 26)
            bind(track.lastScannedAt.timeIntervalSince1970, to: s, at: 27)
            bind(track.fileResourceIdentifier, to: s, at: 28)
            bind(track.audioFingerprint, to: s, at: 29)
            bind(track.bitRate, to: s, at: 30)
        }
    }

    private func saveMyMusicTrackLinkStatement(_ link: MyMusicTrackLink) throws {
        try update("""
            INSERT INTO mymusic_track_links(
                home_track_id, mymusic_track_id, relative_path, file_size, duration,
                audio_fingerprint, first_seen_at, last_seen_at, in_current_snapshot,
                matched_at, match_method, source
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(home_track_id) DO UPDATE SET
                mymusic_track_id=excluded.mymusic_track_id,
                relative_path=excluded.relative_path, file_size=excluded.file_size,
                duration=excluded.duration, audio_fingerprint=excluded.audio_fingerprint,
                first_seen_at=COALESCE(excluded.first_seen_at, mymusic_track_links.first_seen_at),
                last_seen_at=excluded.last_seen_at, in_current_snapshot=excluded.in_current_snapshot,
                matched_at=excluded.matched_at, match_method=excluded.match_method,
                source=excluded.source
            """) { statement in
            bind(link.homeStereoTrackID.uuidString, to: statement, at: 1)
            bind(link.myMusicTrackID.uuidString, to: statement, at: 2)
            bind(link.relativePath, to: statement, at: 3); bind(link.fileSize, to: statement, at: 4)
            bind(link.duration, to: statement, at: 5); bind(link.audioFingerprint, to: statement, at: 6)
            bind(link.firstSeenAt?.timeIntervalSince1970, to: statement, at: 7)
            bind(link.lastSeenAt.timeIntervalSince1970, to: statement, at: 8)
            bind(link.isInCurrentSnapshot ? 1 : 0, to: statement, at: 9)
            bind(link.matchedAt.timeIntervalSince1970, to: statement, at: 10)
            bind(link.matchMethod.rawValue, to: statement, at: 11); bind(link.source.rawValue, to: statement, at: 12)
        }
    }

    private static func encodeTags(_ tags: [String]) -> String {
        guard let data = try? JSONEncoder().encode(tags), let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }

    private static func decodeTags(_ value: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(value.utf8))) ?? []
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }; return try operation()
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(error); throw UserFacingError.persistenceFailed(message)
        }
    }

    private func update(_ sql: String, binds: (OpaquePointer) -> Void = { _ in }) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        binds(statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError() }
    }

    private func query<T>(_ sql: String, binds: (OpaquePointer) -> Void = { _ in }, map: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw sqliteError() }
        defer { sqlite3_finalize(statement) }
        binds(statement)
        var values: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { values.append(try map(statement)) }
        return values
    }

    private func scalarInt(_ sql: String) throws -> Int64 {
        try query(sql) { sqlite3_column_int64($0, 0) }.first ?? 0
    }

    private func sqliteError() -> Error {
        UserFacingError.persistenceFailed(database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error")
    }
}

private struct TrackFingerprint: Equatable {
    let fileSize: Int64
    let modificationDate: Double
    let scanState: String
    let metadataVersion: Int
    let fileResourceIdentifier: Data?
    let audioFingerprint: String?
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
private func bind(_ value: String, to s: OpaquePointer, at i: Int32) { sqlite3_bind_text(s, i, value, -1, sqliteTransient) }
private func bind(_ value: String?, to s: OpaquePointer, at i: Int32) {
    if let value { bind(value, to: s, at: i) } else { sqlite3_bind_null(s, i) }
}
private func bind(_ value: Int64, to s: OpaquePointer, at i: Int32) { sqlite3_bind_int64(s, i, value) }
private func bind(_ value: Int?, to s: OpaquePointer, at i: Int32) {
    if let value { sqlite3_bind_int64(s, i, Int64(value)) } else { sqlite3_bind_null(s, i) }
}
private func bind(_ value: Double, to s: OpaquePointer, at i: Int32) { sqlite3_bind_double(s, i, value) }
private func bind(_ value: Double?, to s: OpaquePointer, at i: Int32) {
    if let value { sqlite3_bind_double(s, i, value) } else { sqlite3_bind_null(s, i) }
}
private func bind(_ value: Data?, to s: OpaquePointer, at i: Int32) {
    guard let value else { sqlite3_bind_null(s, i); return }
    _ = value.withUnsafeBytes { sqlite3_bind_blob(s, i, $0.baseAddress, Int32($0.count), sqliteTransient) }
}
private func text(_ s: OpaquePointer, _ i: Int32) -> String { String(cString: sqlite3_column_text(s, i)) }
private func optionalText(_ s: OpaquePointer, _ i: Int32) -> String? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : text(s, i) }
private func optionalInt(_ s: OpaquePointer, _ i: Int32) -> Int? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(s, i)) }
private func optionalDouble(_ s: OpaquePointer, _ i: Int32) -> Double? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : sqlite3_column_double(s, i) }
private func optionalData(_ s: OpaquePointer, _ i: Int32) -> Data? {
    guard sqlite3_column_type(s, i) != SQLITE_NULL,
          let bytes = sqlite3_column_blob(s, i) else { return nil }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(s, i)))
}
private func date(_ s: OpaquePointer, _ i: Int32) -> Date { Date(timeIntervalSince1970: sqlite3_column_double(s, i)) }
private func optionalDate(_ s: OpaquePointer, _ i: Int32) -> Date? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : date(s, i) }
