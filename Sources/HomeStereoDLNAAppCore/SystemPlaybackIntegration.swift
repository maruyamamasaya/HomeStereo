import AppKit
import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import MediaPlayer

public struct NowPlayingSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval
    public let elapsed: TimeInterval
    public let isPlaying: Bool

    public init?(presentation: NowPlayingPresentation) {
        guard let title = presentation.title else { return nil }
        self.title = title
        artist = presentation.artist
        album = presentation.album
        duration = presentation.duration
        elapsed = max(0, presentation.elapsed)
        isPlaying = presentation.state == .playing
    }
}

@MainActor
public final class SystemPlaybackIntegration {
    private let queue: QueueStore
    private let playback: RendererPlaybackStore
    private let library: LibraryStore
    private var currentPresentation = NowPlayingPresentation()
    private var currentArtworkData: Data?
    private var artworkTask: Task<Void, Never>?

    public init(queue: QueueStore, playback: RendererPlaybackStore, library: LibraryStore) {
        self.queue = queue
        self.playback = playback
        self.library = library
        configureCommands()
        queue.onNowPlayingChange = { [weak self] presentation in self?.setPresentation(presentation) }
        setPresentation(queue.nowPlaying)
    }

    deinit {
        artworkTask?.cancel()
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.removeTarget(nil)
        commands.pauseCommand.removeTarget(nil)
        commands.togglePlayPauseCommand.removeTarget(nil)
        commands.nextTrackCommand.removeTarget(nil)
        commands.previousTrackCommand.removeTarget(nil)
    }

    private func configureCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in self?.dispatch { await $0.play() } ?? .commandFailed }
        commands.pauseCommand.addTarget { [weak self] _ in self?.dispatch { await $0.pause() } ?? .commandFailed }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.dispatch { await $0.togglePlayback() } ?? .commandFailed }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.dispatch { await $0.next() } ?? .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.dispatch { await $0.previous() } ?? .commandFailed }
    }

    private func dispatch(_ action: @escaping @MainActor (QueueStore) async -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak queue] in if let queue { await action(queue) } }
        return .success
    }

    private func setPresentation(_ presentation: NowPlayingPresentation) {
        let trackChanged = currentPresentation.trackID != presentation.trackID || currentPresentation.title != presentation.title
        currentPresentation = presentation
        updateCommandAvailability()
        guard trackChanged else { publish(); return }
        artworkTask?.cancel()
        currentArtworkData = nil
        publish()
        guard let track = queue.nowPlayingTrack else { return }
        artworkTask = Task { [weak self] in
            guard let self else { return }
            let data = await library.artworkData(for: track)
            guard !Task.isCancelled, currentPresentation.trackID == track.id else { return }
            currentArtworkData = data
            publish()
        }
    }

    private func updateCommandAvailability() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = currentPresentation.hasMedia && currentPresentation.state != .playing
        commands.pauseCommand.isEnabled = currentPresentation.state == .playing
        commands.togglePlayPauseCommand.isEnabled = currentPresentation.hasMedia
        commands.nextTrackCommand.isEnabled = currentPresentation.isQueueTrack
        commands.previousTrackCommand.isEnabled = currentPresentation.isQueueTrack
    }

    private func publish() {
        guard let snapshot = NowPlayingSnapshot(presentation: currentPresentation) else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: snapshot.title,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.isPlaying ? 1.0 : 0.0
        ]
        if let artist = snapshot.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = snapshot.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let currentArtworkData, let image = NSImage(data: currentArtworkData) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        switch currentPresentation.state {
        case .playing: MPNowPlayingInfoCenter.default().playbackState = .playing
        case .paused, .loading: MPNowPlayingInfoCenter.default().playbackState = .paused
        case .empty, .stopped, .unknown: MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
}
