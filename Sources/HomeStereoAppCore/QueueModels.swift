import Foundation

public enum QueueRepeatMode: String, CaseIterable, Identifiable, Sendable {
    case off = "Off"
    case all = "All"
    case one = "One"
    public var id: Self { self }
}

public struct QueueItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let trackID: Track.ID
    public init(id: UUID = UUID(), trackID: Track.ID) { self.id = id; self.trackID = trackID }
}

public struct QueueSnapshot: Equatable, Sendable {
    public var items: [QueueItem]
    public var currentIndex: Int?
    public var repeatMode: QueueRepeatMode
    public var shuffleEnabled: Bool
    public var position: TimeInterval

    public init(
        items: [QueueItem] = [], currentIndex: Int? = nil, repeatMode: QueueRepeatMode = .off,
        shuffleEnabled: Bool = false, position: TimeInterval = 0
    ) {
        self.items = items; self.currentIndex = currentIndex; self.repeatMode = repeatMode
        self.shuffleEnabled = shuffleEnabled; self.position = max(0, position)
    }
}
