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

    public func playlists(of kind: PlaylistKind) -> [Playlist] {
        playlists.filter { $0.playlistKind == kind }
    }

    public func selectedPlaylist(of kind: PlaylistKind) -> Playlist? {
        selectedPlaylist.flatMap { $0.playlistKind == kind ? $0 : nil }
    }

    public init(repository: any LibraryPersisting, library: LibraryStore, queue: QueueStore, files: any PlaylistFileServicing) {
        self.repository = repository; self.library = library; self.queue = queue; self.files = files
    }

    public func load() async {
        do { playlists = try await repository.loadPlaylists() }
        catch { message = error.localizedDescription }
    }

    public func create(name: String, kind: PlaylistKind = .regular) async {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let playlist = Playlist(name: value, kind: kind.rawValue)
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
        let accepted = compatibleTrackIDs(trackIDs, with: playlist.playlistKind)
        guard !accepted.isEmpty else {
            if !trackIDs.isEmpty { message = incompatibleTracksMessage(for: playlist.playlistKind) }
            return
        }
        playlist.items.append(contentsOf: accepted.map { PlaylistItem(trackID: $0) })
        if accepted.count != trackIDs.count { message = incompatibleTracksMessage(for: playlist.playlistKind) }
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
        var ids: [Track.ID] = playlist.items.compactMap { item in
            guard let track = library.track(id: item.trackID), track.scanState == .available else { return nil }
            return track.id
        }
        if shuffled { ids.shuffle() }
        await queue.playNow(trackIDs: ids, source: .playlist)
    }

    public func playNow(trackIDs: [Track.ID], startingAt: Track.ID? = nil) async {
        await queue.playNow(trackIDs: trackIDs, startingAt: startingAt, source: .playlist)
    }

    public func playNext(trackIDs: [Track.ID]) async { await queue.playNext(trackIDs: trackIDs) }
    public func appendToQueue(trackIDs: [Track.ID]) async { await queue.append(trackIDs: trackIDs) }

    public func importM3U8(kind: PlaylistKind = .regular) async {
        guard let url = files.chooseImportURL() else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = Self.parseM3U8(text, tracks: library.tracks)
            let accepted = compatibleTrackIDs(result.trackIDs, with: kind)
            let playlist = Playlist(
                name: url.deletingPathExtension().lastPathComponent,
                kind: kind.rawValue,
                items: accepted.map { PlaylistItem(trackID: $0) }
            )
            try await repository.savePlaylist(playlist)
            lastImportResult = M3U8ImportResult(
                imported: accepted.count,
                unresolved: result.summary.unresolved,
                ambiguous: result.summary.ambiguous
            )
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

    public func track(for item: PlaylistItem) -> Track? { library.track(id: item.trackID) }
    public func canAdd(trackIDs: [Track.ID], to playlistID: Playlist.ID) -> Bool {
        guard let playlist = playlists.first(where: { $0.id == playlistID }) else { return false }
        return compatibleTrackIDs(trackIDs, with: playlist.playlistKind).count == trackIDs.count
    }

    public func compatiblePlaylists(for trackIDs: [Track.ID]) -> [Playlist] {
        playlists.filter { canAdd(trackIDs: trackIDs, to: $0.id) }
    }

    public func activate(_ kind: PlaylistKind) {
        let visibleIDs = Set(playlists(of: kind).map(\.id))
        selectedPlaylistIDs.formIntersection(visibleIDs)
        if let selectedPlaylistID, !visibleIDs.contains(selectedPlaylistID) {
            self.selectedPlaylistID = nil
            selectedItemIDs = []
        }
    }
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

    private func compatibleTrackIDs(_ trackIDs: [Track.ID], with kind: PlaylistKind) -> [Track.ID] {
        trackIDs.filter { id in
            guard let track = library.track(id: id) else { return false }
            return kind.accepts(track)
        }
    }

    private func incompatibleTracksMessage(for kind: PlaylistKind) -> String {
        switch kind {
        case .regular: "作業用BGMの曲は通常プレイリストへ追加できません。"
        case .work: "ジャンルが「作業用BGM」の曲だけを作業用プレイリストへ追加できます。"
        }
    }
}
