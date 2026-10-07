import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class BackupStore {
    public private(set) var pendingPreview: BackupImportPreview?
    public private(set) var lastImportResult: BackupImportPreview?
    public private(set) var message: String?
    public private(set) var messageIsError = false

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let playlists: PlaylistStore
    @ObservationIgnored private let listening: ListeningStore
    @ObservationIgnored private let files: any BackupFileServicing
    public private(set) var isWorking = false
    public private(set) var pendingStateRestore = false
    public private(set) var restorePrepared = false
    @ObservationIgnored private let stateBackup: StateBackupService?
    @ObservationIgnored private var pending: ResolvedBackup?

    public init(repository: any LibraryPersisting, library: LibraryStore, playlists: PlaylistStore, listening: ListeningStore, files: any BackupFileServicing, stateBackup: StateBackupService? = nil) {
        self.repository = repository; self.library = library; self.playlists = playlists
        self.listening = listening; self.files = files; self.stateBackup = stateBackup
    }

    public func export() async {
        guard !isWorking, !restorePrepared else { return }
        isWorking = true
        defer { isWorking = false }
        guard let url = files.chooseExportURL() else { return }
        lastImportResult = nil
        do {
            let base = makeDocument(
                exportedAt: .now,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            )
            guard let stateBackup else { throw BackupContractError.invalidStructure("保存状態のバックアップ先がありません") }
            let payload = try await Task.detached { try stateBackup.snapshot() }.value
            let document = HomeStereoBackup(exportedAt: base.exportedAt, appVersion: base.appVersion,
                playlists: base.playlists, favorites: base.favorites, playbackEvents: base.playbackEvents,
                settings: base.settings, state: payload, schemaVersion: 2)
            let data = try BackupCodec.encode(document)
            try data.write(to: url, options: .atomic)
            message = "バックアップを書き出しました。"
            messageIsError = false
        } catch { message = error.localizedDescription; messageIsError = true }
    }

    public func previewImport() async {
        guard !isWorking, !restorePrepared else { return }
        isWorking = true
        defer { isWorking = false }
        guard let url = files.chooseImportURL() else { return }
        pending = nil; pendingPreview = nil; pendingStateRestore = false
        message = nil
        lastImportResult = nil
        do {
            let document = try BackupCodec.decode(Data(contentsOf: url))
            if let state = document.state {
                guard let stateBackup else { throw BackupContractError.invalidStructure("保存状態を復元できません") }
                try await Task.detached { try stateBackup.validate(state) }.value
            }
            pendingStateRestore = document.state != nil
            let resolved = Self.resolve(
                document, tracks: library.tracks, existingPlaylists: playlists.playlists,
                existingFavorites: listening.favorites, existingEvents: listening.events
            )
            pending = resolved; pendingPreview = resolved.preview
        } catch { pending = nil; pendingPreview = nil; message = error.localizedDescription; messageIsError = true }
    }

    public func applyImport() async {
        guard !isWorking, !restorePrepared else { return }
        isWorking = true
        defer { isWorking = false }
        guard let pending else { return }
        do {
            if let state = pending.document.state {
                guard let stateBackup else { throw BackupContractError.invalidStructure("保存状態を復元できません") }
                try await Task.detached { try stateBackup.stageRestore(state) }.value
                restorePrepared = true
                self.pending = nil; pendingPreview = nil; pendingStateRestore = false
                message = "復元を準備しました。HomeStereoを終了して再起動してください。現在の保存状態は復元前フォルダへ退避されます。"
                messageIsError = false
                return
            }
            try await repository.mergeBackup(playlists: pending.playlists, favorites: pending.favorites, events: pending.events)
            UserDefaults.standard.set(pending.document.settings.automaticLibraryUpdates, forKey: "LibraryAutoUpdateEnabled")
            await library.setAutoUpdateEnabled(pending.document.settings.automaticLibraryUpdates)
            await playlists.load(); await listening.load()
            lastImportResult = pending.preview
            self.pending = nil; pendingPreview = nil
        } catch { message = error.localizedDescription; messageIsError = true }
    }

    public func cancelImport() { pending = nil; pendingPreview = nil; pendingStateRestore = false }
    public func dismissMessage() { message = nil; messageIsError = false; lastImportResult = nil }

    public func makeDocument(exportedAt: Date, appVersion: String) -> HomeStereoBackup {
        let byID = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        func reference(_ id: Track.ID) -> BackupTrackReference {
            if let track = byID[id] { return BackupTrackReference(track: track) }
            return BackupTrackReference(trackID: id, relativePath: "", fileSize: 0, duration: 0, title: "未解決の曲")
        }
        return HomeStereoBackup(
            exportedAt: exportedAt, appVersion: appVersion,
            playlists: playlists.playlists.map { playlist in
                BackupPlaylist(
                    id: playlist.id, name: playlist.name, createdAt: playlist.createdAt,
                    updatedAt: playlist.updatedAt, kind: playlist.kind,
                    tracks: playlist.items.map { reference($0.trackID) }
                )
            },
            favorites: listening.favorites.map { BackupFavorite(track: reference($0.trackID), addedAt: $0.addedAt) },
            playbackEvents: listening.events.map {
                BackupPlaybackEvent(id: $0.id, track: reference($0.trackID), startedAt: $0.startedAt, playedSeconds: $0.playedSeconds, outcome: $0.outcome)
            },
            settings: BackupSettings(automaticLibraryUpdates: library.autoUpdateEnabled)
        )
    }

    public nonisolated static func resolve(
        _ document: HomeStereoBackup, tracks: [Track], existingPlaylists: [Playlist],
        existingFavorites: [Favorite], existingEvents: [PlaybackEvent]
    ) -> ResolvedBackup {
        var unresolved = 0, ambiguous = 0
        func id(_ reference: BackupTrackReference) -> Track.ID {
            switch BackupTrackMatcher.match(reference, tracks: tracks) {
            case let .matched(id): return id
            case .unresolved: unresolved += 1; return reference.trackID
            case .ambiguous: ambiguous += 1; return reference.trackID
            }
        }
        let importedPlaylists = document.playlists.map { imported in
            let existing = existingPlaylists.first { $0.id == imported.id }
            return Playlist(
                id: imported.id, myMusicPlaylistID: existing?.myMusicPlaylistID, name: imported.name, createdAt: imported.createdAt,
                updatedAt: imported.updatedAt, kind: imported.kind, tags: existing?.tags ?? [],
                items: imported.tracks.map { PlaylistItem(trackID: id($0)) }
            )
        }
        let importedFavorites = document.favorites.map { Favorite(trackID: id($0.track), addedAt: $0.addedAt) }
        let importedEvents = document.playbackEvents.map {
            PlaybackEvent(id: $0.id, trackID: id($0.track), startedAt: $0.startedAt, playedSeconds: $0.playedSeconds, outcome: $0.outcome)
        }
        let playlistIDs = Set(existingPlaylists.map(\.id)), favoriteIDs = Set(existingFavorites.map(\.trackID)), eventIDs = Set(existingEvents.map(\.id))
        let preview = BackupImportPreview(
            addedPlaylists: importedPlaylists.filter { !playlistIDs.contains($0.id) }.count,
            updatedPlaylists: importedPlaylists.filter { playlistIDs.contains($0.id) }.count,
            addedFavorites: importedFavorites.filter { !favoriteIDs.contains($0.trackID) }.count,
            addedEvents: importedEvents.filter { !eventIDs.contains($0.id) }.count,
            unresolvedTracks: unresolved, ambiguousTracks: ambiguous
        )
        return ResolvedBackup(document: document, playlists: importedPlaylists, favorites: importedFavorites, events: importedEvents, preview: preview)
    }
}
