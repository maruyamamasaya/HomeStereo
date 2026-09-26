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
    @ObservationIgnored private var pending: ResolvedBackup?

    public init(repository: any LibraryPersisting, library: LibraryStore, playlists: PlaylistStore, listening: ListeningStore, files: any BackupFileServicing) {
        self.repository = repository; self.library = library; self.playlists = playlists
        self.listening = listening; self.files = files
    }

    public func export() async {
        guard let url = files.chooseExportURL() else { return }
        lastImportResult = nil
        do {
            let document = makeDocument(
                exportedAt: .now,
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
            )
            let data = try BackupCodec.encode(document)
            try data.write(to: url, options: .atomic)
            message = "バックアップを書き出しました。"
            messageIsError = false
        } catch { message = error.localizedDescription; messageIsError = true }
    }

    public func previewImport() async {
        guard let url = files.chooseImportURL() else { return }
        message = nil
        lastImportResult = nil
        do {
            let document = try BackupCodec.decode(Data(contentsOf: url))
            let resolved = Self.resolve(
                document, tracks: library.tracks, existingPlaylists: playlists.playlists,
                existingFavorites: listening.favorites, existingEvents: listening.events
            )
            pending = resolved; pendingPreview = resolved.preview
        } catch { pending = nil; pendingPreview = nil; message = error.localizedDescription; messageIsError = true }
    }

    public func applyImport() async {
        guard let pending else { return }
        do {
            try await repository.mergeBackup(playlists: pending.playlists, favorites: pending.favorites, events: pending.events)
            UserDefaults.standard.set(pending.document.settings.automaticLibraryUpdates, forKey: "LibraryAutoUpdateEnabled")
            await library.setAutoUpdateEnabled(pending.document.settings.automaticLibraryUpdates)
            await playlists.load(); await listening.load()
            lastImportResult = pending.preview
            self.pending = nil; pendingPreview = nil
        } catch { message = error.localizedDescription; messageIsError = true }
    }

    public func cancelImport() { pending = nil; pendingPreview = nil }
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
                BackupPlaylist(id: playlist.id, name: playlist.name, createdAt: playlist.createdAt, updatedAt: playlist.updatedAt, tracks: playlist.items.map { reference($0.trackID) })
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
        let importedPlaylists = document.playlists.map {
            Playlist(id: $0.id, name: $0.name, createdAt: $0.createdAt, updatedAt: $0.updatedAt, items: $0.tracks.map { PlaylistItem(trackID: id($0)) })
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
