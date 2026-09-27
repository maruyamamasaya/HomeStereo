import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class QueueStore {
    public static let maximumItemCount = 100
    public private(set) var snapshot = QueueSnapshot()
    public private(set) var errorMessage: String?
    public private(set) var isTransitioning = false
    public private(set) var nowPlaying = NowPlayingPresentation()
    public var selectedItemIDs = Set<QueueItem.ID>()
    @ObservationIgnored public var onTrackStarted: (@MainActor (
        Track.ID, TimeInterval, MyMusicPlaySource, MyMusicSelectionType
    ) -> Void)?
    @ObservationIgnored public var onTrackPosition: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored public var onTrackEnded: (@MainActor (MyMusicPlaybackEndReason) -> Void)?
    @ObservationIgnored public var onPlaybackStateChange: (@MainActor (RendererPlaybackState) -> Void)?
    @ObservationIgnored public var onNowPlayingChange: (@MainActor (NowPlayingPresentation) -> Void)?

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let playback: RendererPlaybackStore
    @ObservationIgnored private var positionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var stereoPrewarmTask: Task<Void, Never>?
    @ObservationIgnored private var currentWasRemoved = false
    @ObservationIgnored private var currentPlaySource: MyMusicPlaySource = .unknown
    @ObservationIgnored private var nextSelectionType: MyMusicSelectionType = .manual

    public var items: [QueueItem] { snapshot.items }
    public var currentIndex: Int? { snapshot.currentIndex }
    public var repeatMode: QueueRepeatMode { snapshot.repeatMode }
    public var shuffleEnabled: Bool { snapshot.shuffleEnabled }
    public var currentTrack: Track? {
        guard let index = snapshot.currentIndex, snapshot.items.indices.contains(index) else { return nil }
        return track(for: snapshot.items[index])
    }

    public var nowPlayingTrack: Track? {
        guard !playback.isStereoSynchronizationCheckActive else { return nil }
        guard let id = playback.selectedLibraryTrackID else { return nil }
        return library.track(id: id)
    }

    private func makeNowPlayingPresentation() -> NowPlayingPresentation {
        if playback.isStereoSynchronizationCheckActive {
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
                title: "同期チェック音",
                artist: "3回のクリックが中央で1音に聞こえるか確認",
                duration: playback.duration,
                elapsed: playback.elapsed,
                state: state
            )
        }
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
            trackID: playback.selectedLibraryTrackID,
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
            self?.onTrackEnded?(.naturalEnd)
            Task { await self?.advanceAfterCompletion() }
        }
        playback.onPositionChange = { [weak self] position in
            self?.recordPosition(position)
            self?.onTrackPosition?(position)
            self?.refreshNowPlaying()
        }
        playback.onPlaybackStateChange = { [weak self] state in
            self?.library.setPlaybackActive(state == .playing)
            self?.onPlaybackStateChange?(state)
            self?.refreshNowPlaying()
        }
        playback.onPresentationChange = { [weak self] in self?.refreshNowPlaying() }
        playback.onCommunicationFailure = { [weak self] diagnostic in
            self?.onTrackEnded?(.error)
            self?.errorMessage = "通信が切断されました。再接続後に再試行してください。\n\(diagnostic.details)"
            self?.refreshNowPlaying()
        }
        playback.onRendererTrackChanged = { [weak self] in
            self?.onTrackEnded?(.error)
            self?.errorMessage = "スピーカー側で別の曲へ変更されました。再生キューは保持しています。"
            self?.refreshNowPlaying()
        }
        playback.onShutdown = { [weak self] in self?.onTrackEnded?(.playerDestroyed) }
        library.onTracksChanged = { [weak self] in self?.refreshNowPlaying() }
        refreshNowPlaying(force: true)
    }

    deinit { positionSaveTask?.cancel(); stereoPrewarmTask?.cancel() }

    public func restore() async {
        do {
            snapshot = try await repository.loadQueue()
            if snapshot.items.count > Self.maximumItemCount {
                let currentID = currentItemID
                snapshot.items = Array(snapshot.items.suffix(Self.maximumItemCount))
                snapshot.currentIndex = currentID.flatMap { id in snapshot.items.firstIndex { $0.id == id } }
                    ?? (snapshot.items.isEmpty ? nil : 0)
                await persist()
            }
        }
        catch { errorMessage = error.localizedDescription }
    }

    public func playNow(
        trackIDs: [Track.ID], startingAt trackID: Track.ID? = nil,
        source: MyMusicPlaySource = .unknown
    ) async {
        guard !trackIDs.isEmpty else { return }
        await withPlaybackTransition {
            onTrackEnded?(.queueReplacement)
            currentPlaySource = snapshot.shuffleEnabled ? .shuffle : source
            nextSelectionType = .manual
            var values: [Track.ID]
            if snapshot.shuffleEnabled {
                values = trackIDs
                if let trackID, let index = values.firstIndex(of: trackID) {
                    values.remove(at: index)
                    values.shuffle()
                    values.insert(trackID, at: 0)
                } else {
                    values.shuffle()
                }
                values = Array(values.prefix(Self.maximumItemCount))
            } else {
                values = limitedTrackIDs(trackIDs, startingAt: trackID)
            }
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
        let additions = trackIDs.suffix(Self.maximumItemCount).map { QueueItem(trackID: $0) }
        guard !additions.isEmpty else { return }
        let insertion = min((snapshot.currentIndex ?? -1) + 1, snapshot.items.count)
        snapshot.items.insert(contentsOf: additions, at: insertion)
        if snapshot.currentIndex == nil, !snapshot.items.isEmpty { snapshot.currentIndex = 0 }
        trimOldestItemsIfNeeded()
        await persist()
    }

    public func append(trackIDs: [Track.ID]) async {
        let additions = trackIDs.suffix(Self.maximumItemCount).map { QueueItem(trackID: $0) }
        guard !additions.isEmpty else { return }
        snapshot.items.append(contentsOf: additions)
        if snapshot.currentIndex == nil, !snapshot.items.isEmpty { snapshot.currentIndex = 0 }
        trimOldestItemsIfNeeded()
        await persist()
    }

    public func playImmediately(
        trackID: Track.ID,
        source: MyMusicPlaySource = .unknown
    ) async {
        await withPlaybackTransition {
            onTrackEnded?(.directSelection)
            let previousIndex = snapshot.currentIndex
            let insertionIndex = min((previousIndex ?? -1) + 1, snapshot.items.count)
            snapshot.items.insert(QueueItem(trackID: trackID), at: insertionIndex)
            currentPlaySource = source
            nextSelectionType = .manual
            snapshot.currentIndex = insertionIndex
            snapshot.position = 0
            currentWasRemoved = false
            trimOldestItemsIfNeeded()
            await persist()
            await playCurrent()
        }
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

    public func move(itemID: QueueItem.ID, toOffset: Int) async {
        guard let source = snapshot.items.firstIndex(where: { $0.id == itemID }) else { return }
        await move(fromOffsets: IndexSet(integer: source), toOffset: toOffset)
    }

    public func remove(atOffsets offsets: IndexSet) async {
        let currentID = currentItemID
        let removedIDs = Set(offsets.map { snapshot.items[$0].id })
        let removedCurrent = currentID.map { id in offsets.contains { snapshot.items[$0].id == id } } ?? false
        let oldIndex = snapshot.currentIndex ?? 0
        for index in offsets.sorted(by: >) { snapshot.items.remove(at: index) }
        selectedItemIDs.subtract(removedIDs)
        if removedCurrent {
            currentWasRemoved = playback.playbackState == .playing || playback.playbackState == .paused
            snapshot.currentIndex = snapshot.items.isEmpty ? nil : min(oldIndex, snapshot.items.count - 1)
        } else if let currentID {
            snapshot.currentIndex = snapshot.items.firstIndex(where: { $0.id == currentID })
        }
        await persist()
    }

    public func remove(itemID: QueueItem.ID) async {
        guard let index = snapshot.items.firstIndex(where: { $0.id == itemID }) else { return }
        await remove(atOffsets: IndexSet(integer: index))
    }

    public func removeSelected() async {
        let offsets = IndexSet(snapshot.items.indices.filter { selectedItemIDs.contains(snapshot.items[$0].id) })
        guard !offsets.isEmpty else { return }
        await remove(atOffsets: offsets)
        selectedItemIDs.removeAll()
    }

    public func moveNext(itemIDs: Set<QueueItem.ID>) async {
        guard !itemIDs.isEmpty else { return }
        let currentID = currentItemID
        let moving = snapshot.items.filter { itemIDs.contains($0.id) && $0.id != currentID }
        guard !moving.isEmpty else { return }
        let movingIDs = Set(moving.map(\.id))
        snapshot.items.removeAll { movingIDs.contains($0.id) }
        let insertion: Int
        if let currentID, let current = snapshot.items.firstIndex(where: { $0.id == currentID }) {
            insertion = current + 1
        } else {
            insertion = 0
        }
        snapshot.items.insert(contentsOf: moving, at: insertion)
        if let currentID { snapshot.currentIndex = snapshot.items.firstIndex(where: { $0.id == currentID }) }
        selectedItemIDs = movingIDs
        await persist()
    }

    public func moveSelectedNext() async { await moveNext(itemIDs: selectedItemIDs) }

    public func moveItem(id: QueueItem.ID, by offset: Int) async {
        guard let source = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(0, source + offset), snapshot.items.count - 1)
        guard source != destination else { return }
        let currentID = currentItemID
        let item = snapshot.items.remove(at: source)
        snapshot.items.insert(item, at: destination)
        if let currentID { snapshot.currentIndex = snapshot.items.firstIndex(where: { $0.id == currentID }) }
        await persist()
    }

    public func clear() async {
        onTrackEnded?(.queueReplacement)
        snapshot.items = []
        snapshot.currentIndex = nil
        snapshot.position = 0
        currentWasRemoved = playback.playbackState == .playing || playback.playbackState == .paused
        selectedItemIDs.removeAll()
        await persist()
    }

    public func next() async {
        await withPlaybackTransition {
            onTrackEnded?(.userAdvanced)
            nextSelectionType = .userAdvanced
            await advance(manual: true)
        }
    }

    public func play() async {
        await withPlaybackTransition {
            if playback.selectedLibraryTrackID == nil, playback.media != nil { await playback.play() }
            else if playback.playbackState == .paused { await playback.play() }
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
            onTrackEnded?(.stop)
        }
    }

    public func playItem(id: QueueItem.ID) async {
        guard let index = snapshot.items.firstIndex(where: { $0.id == id }) else { return }
        await withPlaybackTransition {
            onTrackEnded?(.directSelection)
            currentPlaySource = .queue
            nextSelectionType = .manual
            snapshot.currentIndex = index; snapshot.position = 0; currentWasRemoved = false
            await persist(); await playCurrent()
        }
    }

    public func previous() async {
        await withPlaybackTransition {
            guard let index = snapshot.currentIndex else { return }
            if snapshot.position > 3 { await playback.seek(to: 0); snapshot.position = 0; await persist(); return }
            guard index > 0 else { return }
            onTrackEnded?(.userAdvanced)
            nextSelectionType = .userAdvanced
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

    public func track(for item: QueueItem) -> Track? { library.track(id: item.trackID) }

    private var currentItemID: QueueItem.ID? {
        guard let index = snapshot.currentIndex, snapshot.items.indices.contains(index) else { return nil }
        return snapshot.items[index].id
    }

    private func limitedTrackIDs(_ trackIDs: [Track.ID], startingAt trackID: Track.ID?) -> [Track.ID] {
        guard trackIDs.count > Self.maximumItemCount else { return trackIDs }
        guard let trackID, let current = trackIDs.firstIndex(of: trackID) else {
            return Array(trackIDs.prefix(Self.maximumItemCount))
        }
        let end = min(trackIDs.count, current + Self.maximumItemCount)
        let missingPrefixCount = Self.maximumItemCount - (end - current)
        let start = max(0, current - missingPrefixCount)
        return Array(trackIDs[start..<end])
    }

    private func trimOldestItemsIfNeeded() {
        let overflow = snapshot.items.count - Self.maximumItemCount
        guard overflow > 0 else { return }
        let removedIDs = Set(snapshot.items.prefix(overflow).map(\.id))
        snapshot.items.removeFirst(overflow)
        selectedItemIDs.subtract(removedIDs)
        guard let currentIndex = snapshot.currentIndex else { return }
        if currentIndex >= overflow {
            snapshot.currentIndex = currentIndex - overflow
        } else {
            currentWasRemoved = playback.playbackState == .playing || playback.playbackState == .paused
            snapshot.currentIndex = snapshot.items.isEmpty ? nil : 0
        }
    }

    private func advanceAfterCompletion() async {
        await withPlaybackTransition { await advance(manual: false) }
    }

    private func advance(manual: Bool) async {
        guard !snapshot.items.isEmpty else { return }
        nextSelectionType = manual ? .userAdvanced : .automatic
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
            errorMessage = "再生キュー内の曲がライブラリにないか、ファイルが見つかりません。"; return
        }
        guard track.scanState == .available else { errorMessage = "この曲のファイルが見つからないため再生できません。"; return }
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
        onTrackStarted?(track.id, track.duration, currentPlaySource, nextSelectionType)
        scheduleNextStereoPrewarm()
        refreshNowPlaying()
        errorMessage = nil
    }

    private func scheduleNextStereoPrewarm() {
        stereoPrewarmTask?.cancel()
        guard playback.isSonyStereoSelected,
              let currentIndex = snapshot.currentIndex else { return }
        let nextIndex: Int
        if currentIndex + 1 < snapshot.items.count { nextIndex = currentIndex + 1 }
        else if snapshot.repeatMode == .all, !snapshot.items.isEmpty { nextIndex = 0 }
        else { return }
        let trackID = snapshot.items[nextIndex].trackID
        stereoPrewarmTask = Task { [weak self] in
            guard let self else { return }
            await self.library.withTemporaryTrackAccess(trackID) { [weak self] url in
                guard let self, !Task.isCancelled else { return }
                await self.playback.prewarmStereoMedia(fileURL: url)
            }
        }
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

    private func refreshNowPlaying(force: Bool = false) {
        let presentation = makeNowPlayingPresentation()
        guard force || presentation != nowPlaying else { return }
        nowPlaying = presentation
        onNowPlayingChange?(presentation)
    }

    private func recordPosition(_ position: TimeInterval) {
        snapshot.position = max(0, position)
        guard positionSaveTask == nil else { return }
        positionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            do { try await self.repository.saveQueuePosition(self.snapshot.position) }
            catch { self.errorMessage = error.localizedDescription }
            self.positionSaveTask = nil
        }
    }

    private func persist() async {
        do { try await repository.saveQueue(snapshot) }
        catch { errorMessage = error.localizedDescription }
    }
}
