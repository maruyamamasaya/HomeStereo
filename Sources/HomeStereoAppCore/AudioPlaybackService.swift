import AVFoundation
import Foundation

@MainActor
public final class AudioPlaybackService: AudioPlaybackServicing {
    public let player = AVQueuePlayer()
    public var routePickerPlayer: AVPlayer? { player }
    public var onStateChange: (@MainActor (PlaybackState, Int?) -> Void)?
    public var onFailure: (@MainActor (String) -> Void)?

    private var queue = PlaybackQueue()
    nonisolated(unsafe) private var endObserver: NSObjectProtocol?
    nonisolated(unsafe) private var failureObserver: NSObjectProtocol?

    public init() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidFinish() }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onStateChange?(.stopped, self?.queue.currentIndex)
                self?.onFailure?("AVFoundationが再生を完了できませんでした。")
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
    }

    public func load(queue tracks: [Track], startingAt index: Int) throws {
        guard tracks.indices.contains(index) else { throw UserFacingError.playbackFailed("選択した曲が一覧にありません。") }
        guard FileManager.default.fileExists(atPath: tracks[index].url.path),
              FileManager.default.isReadableFile(atPath: tracks[index].url.path) else {
            throw UserFacingError.playbackFailed("ファイルが移動、削除、または読み取り不可になっています。")
        }
        queue = PlaybackQueue(tracks: tracks, currentIndex: index)
        rebuildPlayerItems(startingAt: index)
        onStateChange?(.paused, index)
    }

    public func play() {
        if player.currentItem == nil, let index = queue.currentIndex {
            rebuildPlayerItems(startingAt: index)
        }
        guard player.currentItem != nil else { return }
        player.play()
        onStateChange?(.playing, queue.currentIndex)
    }

    public func pause() {
        player.pause()
        onStateChange?(.paused, queue.currentIndex)
    }

    public func next() {
        guard queue.moveNext() != nil else { return }
        player.advanceToNextItem()
        player.play()
        onStateChange?(.playing, queue.currentIndex)
    }

    public func previous() {
        if currentTime() > 3 {
            seek(to: 0)
            return
        }
        guard queue.movePrevious() != nil, let index = queue.currentIndex else {
            seek(to: 0)
            return
        }
        rebuildPlayerItems(startingAt: index)
        player.play()
        onStateChange?(.playing, index)
    }

    public func seek(to seconds: TimeInterval) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func currentTime() -> TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func rebuildPlayerItems(startingAt index: Int) {
        player.removeAllItems()
        for track in queue.tracks[index...] {
            player.insert(AVPlayerItem(url: track.url), after: nil)
        }
    }

    private func itemDidFinish() {
        if queue.moveNext() != nil {
            onStateChange?(.playing, queue.currentIndex)
        } else {
            onStateChange?(.stopped, queue.currentIndex)
        }
    }
}
