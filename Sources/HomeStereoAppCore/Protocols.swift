import AVFoundation
import Foundation

@MainActor
public protocol AudioPlaybackServicing: AnyObject {
    var routePickerPlayer: AVPlayer? { get }
    var onStateChange: (@MainActor (PlaybackState, Int?) -> Void)? { get set }
    var onFailure: (@MainActor (String) -> Void)? { get set }
    func load(queue: [Track], startingAt index: Int) throws
    func play()
    func pause()
    func next()
    func previous()
    func seek(to seconds: TimeInterval)
    func currentTime() -> TimeInterval
}

public protocol LibraryScanning: Sendable {
    func scan(folder: URL) async throws -> [Track]
}

@MainActor
public protocol FolderAccessServicing: AnyObject {
    func chooseFolder() -> URL?
    func saveBookmark(for folder: URL) throws
    func restoreFolder() throws -> URL?
    func beginAccessing(_ folder: URL) -> Bool
    func stopAccessing(_ folder: URL)
}

public protocol BookmarkStoring: Sendable {
    func save(_ data: Data) throws
    func load() throws -> Data?
    func remove() throws
}
