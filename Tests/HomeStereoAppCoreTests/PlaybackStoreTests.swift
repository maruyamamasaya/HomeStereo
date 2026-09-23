import AVFoundation
import Foundation
import XCTest
@testable import HomeStereoAppCore

@MainActor
final class PlaybackStoreTests: XCTestCase {
    func testSelectingTrackLoadsFakeQueueAndStartsPlayback() {
        let tracks = makeTracks()
        let playback = FakePlaybackService()
        let folder = FakeFolderAccessService(folder: URL(fileURLWithPath: "/tmp/Music"))
        let store = PlaybackStore(playback: playback, library: FakeLibraryService(tracks: tracks), folderAccess: folder)

        store.selectTrack(id: nil)
        XCTAssertFalse(playback.didPlay)
    }

    func testRestoreScansAndSelectionUsesFakePlayback() async {
        let tracks = makeTracks()
        let playback = FakePlaybackService()
        let folderURL = URL(fileURLWithPath: "/tmp/Music")
        let folder = FakeFolderAccessService(folder: folderURL)
        let store = PlaybackStore(playback: playback, library: FakeLibraryService(tracks: tracks), folderAccess: folder)

        await store.restoreLibrary()
        store.selectTrack(id: tracks[1].id)

        XCTAssertEqual(store.tracks, tracks)
        XCTAssertEqual(playback.loadedIndex, 1)
        XCTAssertEqual(playback.loadedTracks, tracks)
        XCTAssertTrue(playback.didPlay)
        XCTAssertEqual(store.currentTrack, tracks[1])
        XCTAssertEqual(store.playbackState, .playing)
    }

    func testChooseFolderPersistsThroughBoundary() async {
        let folder = FakeFolderAccessService(folder: URL(fileURLWithPath: "/tmp/Music"))
        let store = PlaybackStore(playback: FakePlaybackService(), library: FakeLibraryService(tracks: []), folderAccess: folder)

        await store.chooseFolder()

        XCTAssertEqual(folder.savedURL, folder.folder)
    }

    private func makeTracks() -> [Track] {
        [
            Track(url: URL(fileURLWithPath: "/tmp/one.m4a"), title: "One"),
            Track(url: URL(fileURLWithPath: "/tmp/two.m4a"), title: "Two"),
        ]
    }
}

@MainActor
private final class FakePlaybackService: AudioPlaybackServicing {
    var routePickerPlayer: AVPlayer? { nil }
    var onStateChange: (@MainActor (PlaybackState, Int?) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    var loadedTracks: [Track] = []
    var loadedIndex: Int?
    var didPlay = false

    func load(queue: [Track], startingAt index: Int) throws {
        loadedTracks = queue
        loadedIndex = index
        onStateChange?(.paused, index)
    }

    func play() { didPlay = true; onStateChange?(.playing, loadedIndex) }
    func pause() { onStateChange?(.paused, loadedIndex) }
    func next() {}
    func previous() {}
    func seek(to seconds: TimeInterval) {}
    func currentTime() -> TimeInterval { 0 }
}

private struct FakeLibraryService: LibraryScanning, @unchecked Sendable {
    let tracks: [Track]
    func scan(folder: URL) async throws -> [Track] { tracks }
}

@MainActor
private final class FakeFolderAccessService: FolderAccessServicing {
    let folder: URL
    var savedURL: URL?

    init(folder: URL) { self.folder = folder }
    func chooseFolder() -> URL? { folder }
    func saveBookmark(for folder: URL) throws { savedURL = folder }
    func restoreFolder() throws -> URL? { folder }
    func beginAccessing(_ folder: URL) -> Bool { true }
    func stopAccessing(_ folder: URL) {}
}
