import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class ListeningStore {
    public private(set) var favorites: [Favorite] = []
    public private(set) var events: [PlaybackEvent] = []
    public private(set) var message: String?

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let myMusicRepository: (any MyMusicPersisting)?
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let queue: QueueStore
    @ObservationIgnored private var activeEvent: PlaybackEvent?
    @ObservationIgnored private var lastTick: ContinuousClock.Instant?
    @ObservationIgnored private var isPlaying = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var myMusicSession: MyMusicPlaybackSession?
    @ObservationIgnored private var myMusicTrackIDs: [Track.ID: UUID] = [:]

    public init(
        repository: any LibraryPersisting, library: LibraryStore, queue: QueueStore,
        myMusicRepository: (any MyMusicPersisting)? = nil
    ) {
        self.repository = repository
        self.myMusicRepository = myMusicRepository
        self.library = library
        self.queue = queue
        queue.onTrackStarted = { [weak self] id, duration, source, selection in
            self?.start(trackID: id, duration: duration, source: source, selection: selection)
        }
        queue.onTrackPosition = { [weak self] position in self?.observe(position: position) }
        queue.onTrackEnded = { [weak self] reason in self?.finish(reason: reason) }
        queue.onPlaybackStateChange = { [weak self] state in self?.stateChanged(state) }
    }

    deinit { saveTask?.cancel() }

    public var favoriteTracks: [Track] { resolve(favorites.map(\.trackID)) }
    public var recentTracks: [Track] {
        var seen = Set<Track.ID>()
        return resolve(events.sorted { $0.startedAt > $1.startedAt }.compactMap { seen.insert($0.trackID).inserted ? $0.trackID : nil })
    }
    public var frequentTracks: [FrequentTrack] {
        Dictionary(grouping: events.filter { event in
            guard let duration = track(id: event.trackID)?.duration else { return false }
            return MyMusicPlaybackPolicy.countsAsPlay(
                listenedSeconds: event.playedSeconds, trackDuration: duration
            )
        }, by: \.trackID)
            .map { FrequentTrack(trackID: $0.key, playCount: $0.value.count) }
            .sorted { $0.playCount == $1.playCount ? $0.trackID.uuidString < $1.trackID.uuidString : $0.playCount > $1.playCount }
    }
    public var unplayedTracks: [Track] {
        let played = Set(events.map(\.trackID))
        return library.tracks.filter { !played.contains($0.id) }
    }

    public func load() async {
        do {
            async let loadedFavorites = repository.loadFavorites()
            async let loadedEvents = repository.loadPlaybackEvents()
            favorites = try await loadedFavorites
            events = try await loadedEvents
            if let myMusicRepository {
                myMusicTrackIDs = Dictionary(uniqueKeysWithValues: try await myMusicRepository
                    .loadMyMusicTrackLinks().map { ($0.homeStereoTrackID, $0.myMusicTrackID) })
            }
        } catch { message = error.localizedDescription }
    }

    public func isFavorite(_ trackID: Track.ID) -> Bool { favorites.contains { $0.trackID == trackID } }

    public func toggleFavorite(_ trackID: Track.ID) async {
        do {
            if isFavorite(trackID) { try await repository.deleteFavorite(trackID: trackID) }
            else { try await repository.saveFavorite(Favorite(trackID: trackID)) }
            favorites = try await repository.loadFavorites()
        } catch { message = error.localizedDescription }
    }

    public func playFavorites(shuffled: Bool) async {
        var ids = favorites.map(\.trackID)
        if shuffled { ids.shuffle() }
        await queue.playNow(trackIDs: ids, source: .favorite)
    }

    public func resetFavorites() async {
        do { try await repository.deleteAllFavorites(); favorites = [] }
        catch { message = error.localizedDescription }
    }

    public func resetHistory() async {
        finish(reason: .stop)
        await flush()
        do { try await repository.deleteAllPlaybackEvents(); events = [] }
        catch { message = error.localizedDescription }
    }

    public func flush() async {
        tick()
        guard let event = activeEvent else { return }
        do { try await repository.savePlaybackEvent(event); replace(event) }
        catch { message = error.localizedDescription }
    }

    public func track(id: Track.ID) -> Track? { library.tracks.first { $0.id == id } }
    public func dismissMessage() { message = nil }

    private func start(
        trackID: Track.ID, duration: TimeInterval,
        source: MyMusicPlaySource, selection: MyMusicSelectionType
    ) {
        if activeEvent?.trackID == trackID { isPlaying = true; lastTick = .now; return }
        finish(reason: .directSelection)
        let event = PlaybackEvent(trackID: trackID)
        activeEvent = event
        isPlaying = true
        lastTick = .now
        replace(event)
        scheduleSave(event)
        myMusicSession = MyMusicPlaybackSession(
            eventID: "mac-\(UUID().uuidString.lowercased())", homeStereoTrackID: trackID,
            myMusicTrackID: myMusicTrackIDs[trackID],
            startedAt: .now, trackDuration: duration, playSource: source, selectionType: selection
        )
    }

    private func stateChanged(_ state: RendererPlaybackState) {
        tick()
        isPlaying = state == .playing
        lastTick = isPlaying ? .now : nil
        myMusicSession?.setPlaying(isPlaying)
    }

    private func observe(position: TimeInterval) {
        tick()
        myMusicSession?.observe(
            position: position,
            maximumContinuousDelta: MyMusicPlaybackPolicy.maximumContinuousPositionDelta
        )
    }

    private func tick() {
        guard isPlaying, var event = activeEvent, let lastTick else { return }
        let now = ContinuousClock.now
        let elapsed = lastTick.duration(to: now)
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        event.playedSeconds += max(0, min(seconds, 5))
        activeEvent = event
        self.lastTick = now
        replace(event)
        scheduleSave(event)
    }

    private func finish(reason: MyMusicPlaybackEndReason) {
        tick()
        if var event = activeEvent {
            event.outcome = reason == .naturalEnd ? .completed : .stopped
            activeEvent = nil
            replace(event)
            scheduleSave(event)
        }
        isPlaying = false
        lastTick = nil
        guard var session = myMusicSession, let finalized = session.finalize(reason: reason) else { return }
        myMusicSession = nil
        guard let myMusicRepository else { return }
        Task { [weak self] in
            do { _ = try await myMusicRepository.appendLocalMyMusicPlaybackEvent(finalized) }
            catch { self?.message = "再生履歴を保存できませんでした: \(error.localizedDescription)" }
        }
    }

    private func replace(_ event: PlaybackEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) { events[index] = event }
        else { events.insert(event, at: 0) }
    }

    private func scheduleSave(_ event: PlaybackEvent) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            do { try await self.repository.savePlaybackEvent(event) }
            catch { self.message = error.localizedDescription }
        }
    }

    private func resolve(_ ids: [Track.ID]) -> [Track] {
        let byID = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }
}
