import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class PlaylistStore {
    public private(set) var playlists: [Playlist] = []
    public var selectedPlaylistID: Playlist.ID?
    public var selectedPlaylistIDs = Set<Playlist.ID>()
    public var selectedItemIDs = Set<PlaylistItem.ID>()
    public private(set) var message: String?
    public private(set) var lastImportResult: M3U8ImportResult?

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let queue: QueueStore
    @ObservationIgnored private let files: any PlaylistFileServicing

    public var selectedPlaylist: Playlist? { playlists.first { $0.id == selectedPlaylistID } }

    public init(repository: any LibraryPersisting, library: LibraryStore, queue: QueueStore, files: any PlaylistFileServicing) {
        self.repository = repository; self.library = library; self.queue = queue; self.files = files
    }

    public func load() async {
        do { playlists = try await repository.loadPlaylists() }
        catch { message = error.localizedDescription }
    }

    public func create(name: String) async {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let playlist = Playlist(name: value)
        do {
            try await repository.savePlaylist(playlist)
            await load()
            selectedPlaylistID = playlist.id
            selectedPlaylistIDs = [playlist.id]
        }
        catch { message = error.localizedDescription }
    }

    public func rename(id: UUID, name: String) async {
        guard var playlist = playlists.first(where: { $0.id == id }) else { return }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }
        playlist.name = value; playlist.updatedAt = .now; await save(playlist)
    }

    public func delete(id: UUID) async {
        do {
            try await repository.deletePlaylist(id: id)
            selectedPlaylistIDs.remove(id)
            if selectedPlaylistID == id { selectedPlaylistID = nil }
            await load()
        }
        catch { message = error.localizedDescription }
    }

    public func deleteSelectedPlaylists() async {
        let ids = selectedPlaylistIDs
        guard !ids.isEmpty else { return }
        do {
            for id in ids { try await repository.deletePlaylist(id: id) }
            selectedPlaylistIDs.removeAll()
            if let selectedPlaylistID, ids.contains(selectedPlaylistID) { self.selectedPlaylistID = nil }
            await load()
        } catch { message = error.localizedDescription }
    }

    public func add(trackIDs: [Track.ID], to playlistID: UUID) async {
        guard var playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        playlist.items.append(contentsOf: trackIDs.map { PlaylistItem(trackID: $0) })
        playlist.updatedAt = .now; await save(playlist)
    }

    public func addCurrentQueue(to playlistID: UUID) async { await add(trackIDs: queue.items.map(\.trackID), to: playlistID) }

    public func move(fromOffsets: IndexSet, toOffset: Int, in playlistID: UUID) async {
        guard var playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        let moving = fromOffsets.sorted().map { playlist.items[$0] }
        for index in fromOffsets.sorted(by: >) { playlist.items.remove(at: index) }
        let adjusted = toOffset - fromOffsets.filter { $0 < toOffset }.count
        playlist.items.insert(contentsOf: moving, at: min(max(0, adjusted), playlist.items.count))
        playlist.updatedAt = .now; await save(playlist)
    }

    public func removeSelected(from playlistID: UUID) async {
        guard var playlist = playlists.first(where: { $0.id == playlistID }) else { return }
        playlist.items.removeAll { selectedItemIDs.contains($0.id) }
        selectedItemIDs = []; playlist.updatedAt = .now; await save(playlist)
    }

    public func play(_ playlist: Playlist, shuffled: Bool) async {
        var ids = playlist.items.map(\.trackID)
        if shuffled { ids.shuffle() }
        await queue.playNow(trackIDs: ids)
    }

    public func playNow(trackIDs: [Track.ID], startingAt: Track.ID? = nil) async {
        await queue.playNow(trackIDs: trackIDs, startingAt: startingAt)
    }

    public func playNext(trackIDs: [Track.ID]) async { await queue.playNext(trackIDs: trackIDs) }
    public func appendToQueue(trackIDs: [Track.ID]) async { await queue.append(trackIDs: trackIDs) }

    public func importM3U8() async {
        guard let url = files.chooseImportURL() else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = Self.parseM3U8(text, tracks: library.tracks)
            let playlist = Playlist(name: url.deletingPathExtension().lastPathComponent, items: result.trackIDs.map { PlaylistItem(trackID: $0) })
            try await repository.savePlaylist(playlist)
            lastImportResult = result.summary
            await load()
            selectedPlaylistID = playlist.id
            selectedPlaylistIDs = [playlist.id]
        } catch { message = error.localizedDescription }
    }

    public func exportM3U8(_ playlist: Playlist) async {
        guard let url = files.chooseExportURL(defaultName: playlist.name) else { return }
        do { try Self.makeM3U8(playlist: playlist, tracks: library.tracks).data(using: .utf8)!.write(to: url, options: .atomic) }
        catch { message = error.localizedDescription }
    }

    public func track(for item: PlaylistItem) -> Track? { library.tracks.first { $0.id == item.trackID } }
    public func dismissMessage() { message = nil; lastImportResult = nil }

    public nonisolated static func makeM3U8(playlist: Playlist, tracks: [Track]) -> String {
        var lines = ["#EXTM3U"]
        for item in playlist.items {
            guard let track = tracks.first(where: { $0.id == item.trackID }) else { continue }
            let label = [track.artist, track.title].compactMap { $0 }.joined(separator: " - ")
            lines.append("#EXTINF:\(Int(track.duration.rounded())),\(label)")
            lines.append(track.relativePath)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public nonisolated static func parseM3U8(_ text: String, tracks: [Track]) -> (trackIDs: [Track.ID], summary: M3U8ImportResult) {
        var ids: [Track.ID] = [], unresolved: [String] = [], ambiguous: [String] = []
        let paths = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        for path in paths {
            let candidates = tracks.filter { $0.relativePath == path }
            if candidates.count == 1 { ids.append(candidates[0].id) }
            else if candidates.isEmpty { unresolved.append(path) }
            else { ambiguous.append(path) }
        }
        return (ids, M3U8ImportResult(imported: ids.count, unresolved: unresolved, ambiguous: ambiguous))
    }

    private func save(_ playlist: Playlist) async {
        do { try await repository.savePlaylist(playlist); await load(); selectedPlaylistID = playlist.id }
        catch { message = error.localizedDescription }
    }
}
