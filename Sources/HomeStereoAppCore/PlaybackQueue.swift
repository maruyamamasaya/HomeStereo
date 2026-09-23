import Foundation

public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var tracks: [Track]
    public private(set) var currentIndex: Int?

    public init(tracks: [Track] = [], currentIndex: Int? = nil) {
        self.tracks = tracks
        if let currentIndex, tracks.indices.contains(currentIndex) {
            self.currentIndex = currentIndex
        } else {
            self.currentIndex = tracks.isEmpty ? nil : 0
        }
    }

    public var currentTrack: Track? {
        guard let currentIndex else { return nil }
        return tracks[currentIndex]
    }

    @discardableResult
    public mutating func moveNext() -> Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex + 1) else { return nil }
        self.currentIndex = currentIndex + 1
        return currentTrack
    }

    @discardableResult
    public mutating func movePrevious() -> Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex - 1) else { return nil }
        self.currentIndex = currentIndex - 1
        return currentTrack
    }
}
