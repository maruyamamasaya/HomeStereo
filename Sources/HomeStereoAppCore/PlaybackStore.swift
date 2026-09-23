import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
public final class PlaybackStore {
    public var destination: SidebarDestination = .songs
    public private(set) var tracks: [Track] = []
    public private(set) var folderURL: URL?
    public private(set) var currentTrack: Track?
    public private(set) var playbackState: PlaybackState = .stopped
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var message: String?
    public var selectedTrackID: Track.ID?

    @ObservationIgnored private let playback: AudioPlaybackServicing
    @ObservationIgnored private let library: LibraryScanning
    @ObservationIgnored private let folderAccess: FolderAccessServicing
    @ObservationIgnored private var activeScopedURL: URL?
    @ObservationIgnored private var progressTask: Task<Void, Never>?

    public var routePickerPlayer: AVPlayer? { playback.routePickerPlayer }
    public var duration: TimeInterval { currentTrack?.duration ?? 0 }

    public init(
        playback: AudioPlaybackServicing,
        library: LibraryScanning,
        folderAccess: FolderAccessServicing
    ) {
        self.playback = playback
        self.library = library
        self.folderAccess = folderAccess
        playback.onStateChange = { [weak self] state, index in
            guard let self else { return }
            self.playbackState = state
            if let index, self.tracks.indices.contains(index) {
                self.currentTrack = self.tracks[index]
                self.selectedTrackID = self.tracks[index].id
            }
        }
        playback.onFailure = { [weak self] details in
            self?.message = UserFacingError.playbackFailed(details).localizedDescription
        }
    }

    deinit { progressTask?.cancel() }

    public func restoreLibrary() async {
        do {
            guard let folder = try folderAccess.restoreFolder() else { return }
            await load(folder: folder, persist: false)
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? UserFacingError.folderAccessLost.localizedDescription
        }
    }

    public func chooseFolder() async {
        guard let folder = folderAccess.chooseFolder() else { return }
        await load(folder: folder, persist: true)
    }

    public func selectTrack(id: Track.ID?) {
        guard let id, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        do {
            try playback.load(queue: tracks, startingAt: index)
            currentTrack = tracks[index]
            elapsed = 0
            playback.play()
            startProgressUpdates()
        } catch {
            message = UserFacingError.playbackFailed(error.localizedDescription).localizedDescription
        }
    }

    public func togglePlayback() {
        guard currentTrack != nil else { return }
        if playbackState == .playing { playback.pause() } else { playback.play() }
    }

    public func next() { playback.next() }
    public func previous() { playback.previous() }

    public func seek(to seconds: TimeInterval) {
        playback.seek(to: min(max(0, seconds), duration))
        elapsed = seconds
    }

    public func dismissMessage() { message = nil }

    private func load(folder: URL, persist: Bool) async {
        stopActiveScope()
        let accessed = folderAccess.beginAccessing(folder)
        activeScopedURL = accessed ? folder : nil
        do {
            if persist { try folderAccess.saveBookmark(for: folder) }
            let scanned = try await library.scan(folder: folder)
            folderURL = folder
            tracks = scanned
            selectedTrackID = nil
            message = scanned.isEmpty ? UserFacingError.noPlayableAudio.localizedDescription : nil
        } catch {
            stopActiveScope()
            message = (error as? LocalizedError)?.errorDescription ?? UserFacingError.scanFailed(error.localizedDescription).localizedDescription
        }
    }

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.elapsed = self.playback.currentTime()
            }
        }
    }

    private func stopActiveScope() {
        if let activeScopedURL { folderAccess.stopAccessing(activeScopedURL) }
        activeScopedURL = nil
    }
}
