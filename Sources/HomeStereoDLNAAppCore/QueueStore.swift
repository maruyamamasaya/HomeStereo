import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class QueueStore {
    public private(set) var snapshot = QueueSnapshot()
    public private(set) var errorMessage: String?
    public private(set) var isTransitioning = false
    public var selectedItemIDs = Set<QueueItem.ID>()
    @ObservationIgnored public var onTrackStarted: (@MainActor (Track.ID) -> Void)?
    @ObservationIgnored public var onTrackPosition: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored public var onTrackEnded: (@MainActor (Bool) -> Void)?
    @ObservationIgnored public var onPlaybackStateChange: (@MainActor (RendererPlaybackState) -> Void)?
    @ObservationIgnored public var onNowPlayingTrack: (@MainActor (Track?) -> Void)?
    @ObservationIgnored public var onNowPlayingPosition: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored public var onNowPlayingState: (@MainActor (RendererPlaybackState) -> Void)?
    @ObservationIgnored public var onNowPlayingChange: (@MainActor (NowPlayingPresentation) -> Void)?

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let playback: RendererPlaybackStore
    @ObservationIgnored private var positionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var currentWasRemoved = false

    public var items: [QueueItem] { snapshot.items }
    public var currentIndex: Int? { snapshot.currentIndex }
    public var repeatMode: QueueRepeatMode { snapshot.repeatMode }
    public var shuffleEnabled: Bool { snapshot.shuffleEnabled }
    public var currentTrack: Track? {
        guard let index = snapshot.currentIndex, snapshot.items.indices.contains(index) else { return nil }
        return track(for: snapshot.items[index])
    }

    public var nowPlayingTrack: Track? {
        guard let id = playback.selectedLibraryTrackID else { return nil }
        return library.tracks.first { $0.id == id }
    }

    public var nowPlaying: NowPlayingPresentation {
        guard let media = playback.media else {
            let state: NowPlayingDisplayState = playback.playbackState == .stopped ? .empty : .unknown
            return NowPlayingPresentation(state: state)
        }
        let track = nowPlayingTrack
        let state: NowPlayingDisplayState
        if playback.isBusy { state = .loading }
        else {
            switch playback.playbackState {
            case .stopped: state = .stopped
            case .playing: state = .playing
            case .paused: state = .paused
            case .transitioning: state = .loading
            case .unknown: state = .unknown
            }
        }
        return NowPlayingPresentation(
            trackID: track?.id,
            title: track?.title ?? media.title,
            artist: track?.artist,
            album: track?.album,
            duration: playback.duration > 0 ? playback.duration : (track?.duration ?? 0),
            elapsed: playback.elapsed,
            state: state
        )
    }

    public init(repository: any LibraryPersisting, library: LibraryStore, playback: RendererPlaybackStore) {
        self.repository = repository; self.library = library; self.playback = playback
        playback.onTrackFinished = { [weak self] in
            self?.onTrackEnded?(true)
            Task { await self?.advanceAfterCompletion() }
        }
        playback.onPositionChange = { [weak self] position in
            self?.recordPosition(position)
            self?.onTrackPosition?(position)
            self?.onNowPlayingPosition?(position)
            self?.publishNowPlaying()
        }
        playback.onPlaybackStateChange = { [weak self] state in
            self?.onPlaybackStateChange?(state)
            self?.onNowPlayingState?(state)
            self?.publishNowPlaying()
        }
        playback.onPresentationChange = { [weak self] in self?.publishNowPlaying() }
        playback.onCommunicationFailure = { [weak self] diagnostic in
            self?.onTrackEnded?(false)
            self?.onNowPlayingState?(.unknown)
            self?.errorMessage = "通信が切断されました。再接続後に再試行してください。\n\(diagnostic.details)"
            self?.publishNowPlaying()
        }
        playback.onRendererTrackChanged = { [weak self] in
            self?.onTrackEnded?(false)
            self?.onNowPlayingTrack?(nil)
            self?.errorMessage = "Renderer側で別の曲へ変更されました。Queueは保持しています。"
            self?.publishNowPlaying()
        }
    }

    deinit { positionSaveTask?.cancel() }

    public func restore() async {
        do { snapshot = try await repository.loadQueue() }
        catch { errorMessage = error.localizedDescription }
    }

    public func playNow(trackIDs: [Track.ID], startingAt trackID: Track.ID? = nil) async {
        guard !trackIDs.isEmpty else { return }
        await withPlaybackTransition {
            var values = trackIDs
            if snapshot.shuffleEnabled { values.shuffle() }
            snapshot.items = values.map { QueueItem(trackID: $0) }
            if let trackID, let index = snapshot.items.firstIndex(where: { $0.trackID == trackID }) { snapshot.currentIndex = index }
            else { snapshot.currentIndex = 0 }
            snapshot.position = 0
            currentWasRemoved = false
            await persist()
            await playCurrent()
        }
    }

    public func playNext(trackIDs: [Track.ID]) async {
        let additions = trackIDs.map { QueueItem(trackID: $0) }
        let insertion = min((snapshot.currentIndex ?? -1) + 1, snapshot.items.count)
        snapshot.items.insert(contentsOf: additions, at: insertion)
        if snapshot.currentIndex == nil, !snapshot.items.isEmpty { snapshot.currentIndex = 0 }
        await persist()
    }

    public func append(trackIDs: [Track.ID]) async {
        snapshot.items.append(contentsOf: trackIDs.map { QueueItem(trackID: $0) })
        if snapshot.currentIndex == nil, !snapshot.items.isEmpty { snapshot.currentIndex = 0 }
        await persist()
    }

    public func move(fromOffsets: IndexSet, toOffset: Int) async {
        let currentID = currentItemID
        let moving = fromOffsets.sorted().map { snapshot.items[$0] }
        for index in fromOffsets.sorted(by: >) { snapshot.items.remove(at: index) }
        let adjusted = toOffset - fromOffsets.filter { $0 < toOffset }.count
        snapshot.items.insert(contentsOf: moving, at: min(max(0, adjusted), snapshot.items.count))
        if let currentID { snapshot.currentIndex = snapshot.items.firstIndex(where: { $0.id == currentID }) }
        await persist()
    }

    public func remove(atOffsets offsets: IndexSet) async {
        let currentID = currentItemID
        let removedCurrent = currentID.map { id in offsets.contains { snapshot.items[$0].id == id } } ?? false
        let oldIndex = snapshot.currentIndex ?? 0
        for index in offsets.sorted(by: >) { snapshot.items.remove(at: index) }
        if removedCurrent {
            currentWasRemoved = playback.playbackState == .playing || playback.playbackState == .paused
            snapshot.currentIndex = snapshot.items.isEmpty ? nil : min(oldIndex, snapshot.items.count - 1)
        } else if let currentID {
            snapshot.currentIndex = snapshot.items.firstIndex(where: { $0.id == currentID })
        }
        await persist()
    }

    public func removeSelected() async {
        let offsets = IndexSet(snapshot.items.indices.filter { selectedItemIDs.contains(snapshot.items[$0].id) })
        guard !offsets.isEmpty else { return }
        await remove(atOffsets: offsets)
        selectedItemIDs.removeAll()
    }

    public func clear() async {
        snapshot.items = []
        snapshot.currentIndex = nil
        snapshot.position = 0
        currentWasRemoved = playback.playbackState == .playing || playback.playbackState == .paused
        selectedItemIDs.removeAll()
        await persist()
    }

    public func next() async { await withPlaybackTransition { await advance(manual: true) } }

    public func play() async {
        await withPlaybackTransition {
            if playback.playbackState == .paused { await playback.play() }
            else { await playCurrent() }
        }
    }

    public func pause() async { await withPlaybackTransition { await playback.pause() } }

    public func togglePlayback() async {
        if playback.selectedLibraryTrackID == nil, playback.media != nil {
            await playback.togglePlayback()
        } else if playback.playbackState == .playing {
            await pause()
        } else {
            await play()
        }
    }

    public func stop() async {
        await withPlaybackTransition {
            await playback.stop()
            onTrackEnded?(false)
        }
    }

    public func playItem(id: QueueItem.ID) async {
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        await withPlaybackTransition {
            snapshot.currentIndex = index; snapshot.position = 0; currentWasRemoved = false
            await persist(); await playCurrent()
        }
    }

    public func previous() async {
        await withPlaybackTransition {
            guard let index = snapshot.currentIndex else { return }
            if snapshot.position > 3 { await playback.seek(to: 0); snapshot.position = 0; await persist(); return }
            guard index > 0 else { return }
            snapshot.currentIndex = index - 1; snapshot.position = 0; currentWasRemoved = false
            await persist(); await playCurrent()
        }
    }

    public func toggleShuffle() async {
        snapshot.shuffleEnabled.toggle()
        guard let index = snapshot.currentIndex, index + 1 < snapshot.items.count else { await persist(); return }
        let prefix = snapshot.items[...index]
        let suffix = snapshot.items[(index + 1)...].shuffled()
        snapshot.items = Array(prefix) + suffix
        await persist()
    }

    public func setRepeatMode(_ mode: QueueRepeatMode) async { snapshot.repeatMode = mode; await persist() }
    public func dismissError() { errorMessage = nil }
    public func persistForLifecycle() async { await persist() }

    public func track(for item: QueueItem) -> Track? { library.tracks.first { $0.id == item.trackID } }

    private var currentItemID: QueueItem.ID? {
        guard let index = snapshot.currentIndex, snapshot.items.indices.contains(index) else { return nil }
        return snapshot.items[index].id
    }

    private func advanceAfterCompletion() async {
        await withPlaybackTransition { await advance(manual: false) }
    }

    private func advance(manual: Bool) async {
        guard !snapshot.items.isEmpty else { return }
        if !manual, currentWasRemoved {
            currentWasRemoved = false
            snapshot.position = 0
            await persist(); await playCurrent(); return
        }
        guard let index = snapshot.currentIndex else { snapshot.currentIndex = 0; await playCurrent(); return }
        if !manual, snapshot.repeatMode == .one { snapshot.position = 0; await persist(); await playCurrent(); return }
        if index + 1 < snapshot.items.count { snapshot.currentIndex = index + 1 }
        else if snapshot.repeatMode == .all { snapshot.currentIndex = 0 }
        else { snapshot.position = 0; await persist(); return }
        snapshot.position = 0
        await persist(); await playCurrent()
    }

    private func playCurrent() async {
        guard let track = currentTrack else {
            errorMessage = "Queue内の曲がLibraryにないか、missingです。"; return
        }
        guard track.scanState == .available else { errorMessage = "この曲はmissingのため再生できません。"; return }
        let resumePosition = snapshot.position
        guard let url = await library.prepareTrack(track.id) else {
            errorMessage = library.message
            await skipUnavailableTrack()
            return
        }
        guard playback.selectLibraryFile(url, expectedDuration: track.duration, trackID: track.id) else {
            errorMessage = playback.lastError?.details ?? "非対応formatのため、この曲をスキップしました。"
            await skipUnavailableTrack()
            return
        }
        await playback.play()
        guard playback.playbackState == .playing else {
            errorMessage = playback.lastError?.details ?? "再生を開始できませんでした。"; return
        }
        if resumePosition > 0 { await playback.seek(to: resumePosition) }
        onTrackStarted?(track.id)
        onNowPlayingTrack?(track)
        onNowPlayingState?(.playing)
        publishNowPlaying()
        errorMessage = nil
    }

    private func withPlaybackTransition(_ operation: () async -> Void) async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        await operation()
    }

    private func skipUnavailableTrack() async {
        guard let index = snapshot.currentIndex, index + 1 < snapshot.items.count else { return }
        snapshot.currentIndex = index + 1
        snapshot.position = 0
        await persist()
        await playCurrent()
    }

    private func publishNowPlaying() { onNowPlayingChange?(nowPlaying) }

    private func recordPosition(_ position: TimeInterval) {
        snapshot.position = max(0, position)
        positionSaveTask?.cancel()
        positionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await self.persist()
        }
    }

    private func persist() async {
        do { try await repository.saveQueue(snapshot) }
        catch { errorMessage = error.localizedDescription }
    }
}
