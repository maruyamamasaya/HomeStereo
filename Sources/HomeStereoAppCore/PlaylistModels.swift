import Foundation

public enum PlaylistKind: String, CaseIterable, Sendable {
    case regular
    case work

    public func accepts(_ track: Track) -> Bool {
        switch self {
        case .regular: !track.isEligibleForWorkPlayback
        case .work: track.isEligibleForWorkPlayback
        }
    }
}

public struct PlaylistItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let trackID: Track.ID
    public init(id: UUID = UUID(), trackID: Track.ID) { self.id = id; self.trackID = trackID }
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var myMusicPlaylistID: UUID?
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var kind: String
    public var tags: [String]
    public var items: [PlaylistItem]

    public var playlistKind: PlaylistKind { PlaylistKind(rawValue: kind) ?? .regular }

    public init(
        id: UUID = UUID(), myMusicPlaylistID: UUID? = nil, name: String,
        createdAt: Date = .now, updatedAt: Date = .now, kind: String = "regular",
        tags: [String] = [], items: [PlaylistItem] = []
    ) {
        self.id = id; self.myMusicPlaylistID = myMusicPlaylistID; self.name = name
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.kind = kind
        self.tags = tags; self.items = items
    }
}

public struct M3U8ImportResult: Equatable, Sendable {
    public let imported: Int
    public let unresolved: [String]
    public let ambiguous: [String]
    public init(imported: Int, unresolved: [String], ambiguous: [String]) {
        self.imported = imported; self.unresolved = unresolved; self.ambiguous = ambiguous
    }
}
