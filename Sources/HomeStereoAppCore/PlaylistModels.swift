import Foundation

public struct PlaylistItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let trackID: Track.ID
    public init(id: UUID = UUID(), trackID: Track.ID) { self.id = id; self.trackID = trackID }
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    public var items: [PlaylistItem]

    public init(id: UUID = UUID(), name: String, createdAt: Date = .now, updatedAt: Date = .now, items: [PlaylistItem] = []) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt; self.items = items
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
