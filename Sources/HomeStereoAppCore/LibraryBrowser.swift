import Foundation

public struct LibraryAlbum: Identifiable, Hashable, Sendable {
    public struct ID: Hashable, Sendable {
        public let albumArtist: String?
        public let title: String
        public init(albumArtist: String?, title: String) { self.albumArtist = albumArtist; self.title = title }
    }
    public let id: ID
    public let title: String
    public let albumArtist: String?
    public let tracks: [Track]
    public init(title: String, albumArtist: String?, tracks: [Track]) {
        self.id = ID(albumArtist: albumArtist, title: title)
        self.title = title; self.albumArtist = albumArtist; self.tracks = tracks
    }
}

public struct LibraryArtist: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let tracks: [Track]
    public init(name: String, tracks: [Track]) { id = name; self.name = name; self.tracks = tracks }
}

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case title = "名前"
    case artist = "アーティスト"
    case album = "アルバム"
    case duration = "時間"
    public var id: Self { self }
}

public struct LibraryBrowserIndex: Sendable {
    public let tracks: [Track]
    public let albums: [LibraryAlbum]
    public let artists: [LibraryArtist]

    public init(tracks: [Track], search: String = "", sort: LibrarySort = .title) {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let available = tracks.filter { $0.scanState != .missing }
        self.tracks = Self.sort(available.filter {
            query.isEmpty || [$0.title, $0.artist, $0.albumArtist, $0.album, $0.genre, $0.composer]
                .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
        }, by: sort)

        let albumGroups = Dictionary(grouping: available.compactMap { track -> (LibraryAlbum.ID, Track)? in
            guard let title = track.album?.nilIfBlank else { return nil }
            return (LibraryAlbum.ID(albumArtist: track.albumArtist?.nilIfBlank, title: title), track)
        }, by: { $0.0 })
        self.albums = albumGroups.map { key, values in
            LibraryAlbum(title: key.title, albumArtist: key.albumArtist, tracks: Self.trackOrder(values.map(\.1)))
        }.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.albumArtist?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.tracks.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }.sorted {
            let lhs = sort == .artist ? ($0.albumArtist ?? "") : $0.title
            let rhs = sort == .artist ? ($1.albumArtist ?? "") : $1.title
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        let artistGroups = Dictionary(grouping: available.compactMap { track -> (String, Track)? in
            guard let artist = track.artist?.nilIfBlank else { return nil }
            return (artist, track)
        }, by: { $0.0 })
        self.artists = artistGroups.map { name, values in
            LibraryArtist(name: name, tracks: Self.trackOrder(values.map(\.1)))
        }.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) ||
                $0.tracks.contains { $0.title.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func sort(_ tracks: [Track], by sort: LibrarySort) -> [Track] {
        tracks.sorted { lhs, rhs in
            switch sort {
            case .title: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .artist: (lhs.artist ?? "").localizedStandardCompare(rhs.artist ?? "") == .orderedAscending
            case .album: (lhs.album ?? "").localizedStandardCompare(rhs.album ?? "") == .orderedAscending
            case .duration: lhs.duration < rhs.duration
            }
        }
    }

    private static func trackOrder(_ tracks: [Track]) -> [Track] {
        tracks.sorted {
            if ($0.discNumber ?? 0) != ($1.discNumber ?? 0) { return ($0.discNumber ?? 0) < ($1.discNumber ?? 0) }
            if ($0.trackNumber ?? 0) != ($1.trackNumber ?? 0) { return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
