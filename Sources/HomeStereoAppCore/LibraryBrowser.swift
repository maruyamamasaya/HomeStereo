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
        self.id = ID(albumArtist: nil, title: title)
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
    case genre = "ジャンル"
    case releaseYear = "年"
    case duration = "時間"
    public var id: Self { self }
}

public enum LibrarySortDirection: Sendable, Equatable {
    case ascending
    case descending
}

public struct LibraryTrackComparator: SortComparator, Sendable {
    public let sort: LibrarySort
    public var order: SortOrder

    public init(sort: LibrarySort, order: SortOrder = .forward) {
        self.sort = sort
        self.order = order
    }

    public func compare(_ lhs: Track, _ rhs: Track) -> ComparisonResult {
        let result: ComparisonResult = switch sort {
        case .title: Self.compare(lhs.title, rhs.title)
        case .artist: Self.compare(lhs.artist, rhs.artist)
        case .album: Self.compare(lhs.album, rhs.album)
        case .genre: Self.compare(lhs.genre, rhs.genre)
        case .releaseYear: Self.compare(lhs.releaseYear, rhs.releaseYear)
        case .duration: Self.compare(lhs.duration, rhs.duration)
        }
        let stableResult = result == .orderedSame
            ? Self.compare(lhs.id.uuidString, rhs.id.uuidString)
            : result
        guard order == .reverse else { return stableResult }
        return switch stableResult {
        case .orderedAscending: .orderedDescending
        case .orderedDescending: .orderedAscending
        case .orderedSame: .orderedSame
        }
    }

    private static func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        (lhs ?? "").localizedStandardCompare(rhs ?? "")
    }

    private static func compare<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): .orderedSame
        case (nil, _): .orderedAscending
        case (_, nil): .orderedDescending
        case let (lhs?, rhs?) where lhs < rhs: .orderedAscending
        case let (lhs?, rhs?) where lhs > rhs: .orderedDescending
        default: .orderedSame
        }
    }

}

public struct LibraryBrowserBase: Sendable {
    public let tracks: [Track]
    public let genres: [String]
    public let sort: LibrarySort

    public init(
        tracks: [Track], sort: LibrarySort = .title,
        sortDirection: LibrarySortDirection = .ascending
    ) {
        self.sort = sort
        let available = tracks.filter { $0.scanState != .missing }
        self.tracks = available.sorted(using: LibraryTrackComparator(
            sort: sort, order: sortDirection == .ascending ? .forward : .reverse
        ))
        self.genres = Set(available.compactMap { $0.genre?.nilIfBlank }).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}

public struct LibraryBrowserIndex: Sendable {
    public let tracks: [Track]
    public let albums: [LibraryAlbum]
    public let artists: [LibraryArtist]
    public let genres: [String]

    public init(
        tracks: [Track], search: String = "", sort: LibrarySort = .title,
        sortDirection: LibrarySortDirection = .ascending, genre: String? = nil,
        presetGenreNames: Set<String>? = nil, includesUnassignedGenre: Bool = false,
        buildCollections: Bool = true
    ) {
        self.init(
            base: LibraryBrowserBase(tracks: tracks, sort: sort, sortDirection: sortDirection),
            search: search, genre: genre, presetGenreNames: presetGenreNames,
            includesUnassignedGenre: includesUnassignedGenre, buildCollections: buildCollections
        )
    }

    public init(
        base: LibraryBrowserBase, search: String = "", genre: String? = nil,
        presetGenreNames: Set<String>? = nil, includesUnassignedGenre: Bool = false,
        buildCollections: Bool = true
    ) {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        self.genres = base.genres
        let genreFiltered = base.tracks.filter { track in
            if let presetGenreNames {
                guard let trackGenre = track.genre?.nilIfBlank else { return includesUnassignedGenre }
                return presetGenreNames.contains(trackGenre) || GenreDisplayPreset.fixedGenreNames.contains(trackGenre)
            }
            return genre == nil || track.genre?.nilIfBlank == genre
        }
        self.tracks = genreFiltered.filter {
            query.isEmpty || [$0.title, $0.artist, $0.albumArtist, $0.album, $0.genre, $0.composer]
                .compactMap { $0 }.contains { $0.localizedCaseInsensitiveContains(query) }
        }

        guard buildCollections else {
            self.albums = []
            self.artists = []
            return
        }

        let collectionTracks = genreFiltered.filter(\.isRegularLibraryTrack)
        let albumGroups = Dictionary(grouping: collectionTracks.compactMap { track -> (LibraryAlbum.ID, Track)? in
            guard let title = track.album?.nilIfBlank else { return nil }
            return (LibraryAlbum.ID(albumArtist: nil, title: title), track)
        }, by: { $0.0 })
        self.albums = albumGroups.map { key, values in
            let tracks = Self.trackOrder(values.map(\.1))
            let albumArtists = Set(tracks.map { $0.albumArtist?.nilIfBlank })
            let albumArtist = albumArtists.count == 1 ? tracks.first?.albumArtist?.nilIfBlank : nil
            return LibraryAlbum(title: key.title, albumArtist: albumArtist, tracks: tracks)
        }.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) ||
                ($0.albumArtist?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.tracks.contains { track in
                    [track.title, track.artist, track.albumArtist].compactMap { $0 }
                        .contains { $0.localizedCaseInsensitiveContains(query) }
                }
        }.sorted {
            let lhs = base.sort == .artist ? ($0.albumArtist ?? "") : $0.title
            let rhs = base.sort == .artist ? ($1.albumArtist ?? "") : $1.title
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }

        let artistGroups = Dictionary(grouping: collectionTracks.compactMap { track -> (String, Track)? in
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
