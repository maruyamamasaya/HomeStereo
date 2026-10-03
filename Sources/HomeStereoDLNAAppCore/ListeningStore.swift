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
    public private(set) var frequentTracks: [FrequentTrack] = []
    public private(set) var message: String?
    public private(set) var analyticsRevision = 0
    @ObservationIgnored public var onAnalyticsRevision: (@MainActor (Int) -> Void)?

    @ObservationIgnored private let repository: any LibraryPersisting
    @ObservationIgnored private let myMusicRepository: (any MyMusicPersisting)?
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let queue: QueueStore
    @ObservationIgnored private var activeEvent: PlaybackEvent?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var myMusicSession: MyMusicPlaybackSession?
    @ObservationIgnored private var myMusicTrackIDs: [Track.ID: UUID] = [:]
    @ObservationIgnored private var frequentCounts: [Track.ID: Int] = [:]

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
    public var recentEvents: [PlaybackEvent] {
        var seen = Set<Track.ID>()
        return events.sorted { $0.startedAt > $1.startedAt }
            .filter { seen.insert($0.trackID).inserted }
    }
    public var recentTracks: [Track] {
        resolve(recentEvents.map(\.trackID))
    }
    private func rebuildFrequentTracks() {
        frequentCounts = Dictionary(grouping: events.filter(eventCountsAsPlay), by: \.trackID)
            .mapValues(\.count)
        publishFrequentTracks()
    }

    private func publishFrequentTracks() {
        frequentTracks = frequentCounts
            .map { FrequentTrack(trackID: $0.key, playCount: $0.value) }
            .sorted { $0.playCount == $1.playCount ? $0.trackID.uuidString < $1.trackID.uuidString : $0.playCount > $1.playCount }
    }

    private func eventCountsAsPlay(_ event: PlaybackEvent) -> Bool {
        guard let duration = track(id: event.trackID)?.duration else { return false }
        return MyMusicPlaybackPolicy.countsAsPlay(
            listenedSeconds: event.playedSeconds, trackDuration: duration
        )
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
            rebuildFrequentTracks()
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
            publishAnalyticsRevision()
        } catch { message = error.localizedDescription }
    }

    public func playFavorites(shuffled: Bool) async {
        var ids = favorites.map(\.trackID)
        if shuffled { ids.shuffle() }
        await queue.playNow(trackIDs: ids, source: .favorite)
    }

    public func resetFavorites() async {
        do { try await repository.deleteAllFavorites(); favorites = []; publishAnalyticsRevision() }
        catch { message = error.localizedDescription }
    }

    public func resetHistory() async {
        finish(reason: .stop)
        await flush()
        do {
            if let analyticsRepository = myMusicRepository as? any AnalyticsPersisting {
                try await analyticsRepository.deleteAnalyticsHistory(trackID: nil)
            } else {
                try await repository.deleteAllPlaybackEvents()
            }
            events = []
            frequentTracks = []
            frequentCounts = [:]
            publishAnalyticsRevision()
        }
        catch { message = error.localizedDescription }
    }

    public func flush() async {
        tick()
        guard let event = activeEvent else {
            await saveTask?.value
            return
        }
        guard event.playedSeconds > 30 else { return }
        saveTask?.cancel()
        saveTask = nil
        do { try await repository.savePlaybackEvent(event); replace(event) }
        catch { message = error.localizedDescription }
    }

    public func track(id: Track.ID) -> Track? { library.track(id: id) }
    public func dismissMessage() { message = nil }

    private func start(
        trackID: Track.ID, duration: TimeInterval,
        source: MyMusicPlaySource, selection: MyMusicSelectionType
    ) {
        if activeEvent?.trackID == trackID { myMusicSession?.setPlaying(true); return }
        finish(reason: .directSelection)
        let event = PlaybackEvent(trackID: trackID)
        activeEvent = event
        myMusicSession = MyMusicPlaybackSession(
            eventID: "mac-\(UUID().uuidString.lowercased())", homeStereoTrackID: trackID,
            myMusicTrackID: myMusicTrackIDs[trackID],
            startedAt: .now, trackDuration: duration, playSource: source, selectionType: selection
        )
    }

    private func stateChanged(_ state: RendererPlaybackState) {
        tick()
        myMusicSession?.setPlaying(state == .playing)
    }

    private func observe(position: TimeInterval) {
        myMusicSession?.observe(
            position: position,
            maximumContinuousDelta: MyMusicPlaybackPolicy.maximumContinuousPositionDelta
        )
        tick()
    }

    private func tick() {
        guard var event = activeEvent else { return }
        // Share actual listening time with the exported event; pauses and seeks do not count.
        event.playedSeconds = myMusicSession?.listenedSeconds ?? 0
        activeEvent = event
        if event.playedSeconds > 30 { scheduleCheckpoint() }
    }

    private func finish(reason: MyMusicPlaybackEndReason) {
        tick()
        if var event = activeEvent {
            event.outcome = reason == .naturalEnd ? .completed : .stopped
            activeEvent = nil
            if event.playedSeconds > 30 {
                replace(event)
                saveImmediately(event)
            } else {
                saveTask?.cancel()
                saveTask = nil
            }
        }
        let pendingSession = myMusicSession
        myMusicSession = nil
        guard var session = pendingSession, let finalized = session.finalize(reason: reason),
              finalized.playDuration > 30, let myMusicRepository else { return }
        Task { [weak self] in
            do {
                let inserted = try await myMusicRepository.appendLocalMyMusicPlaybackEvent(finalized)
                if inserted { self?.publishAnalyticsRevision() }
            }
            catch { self?.message = "再生履歴を保存できませんでした: \(error.localizedDescription)" }
        }
    }

    private func replace(_ event: PlaybackEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            let previouslyCounted = eventCountsAsPlay(events[index])
            events[index] = event
            if previouslyCounted != eventCountsAsPlay(event) {
                frequentCounts[event.trackID, default: 0] += previouslyCounted ? -1 : 1
                if frequentCounts[event.trackID] == 0 { frequentCounts[event.trackID] = nil }
                publishFrequentTracks()
            }
        } else {
            events.insert(event, at: 0)
            if eventCountsAsPlay(event) {
                frequentCounts[event.trackID, default: 0] += 1
                publishFrequentTracks()
            }
        }
    }

    private func scheduleCheckpoint() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            guard let event = self.activeEvent, event.playedSeconds > 30 else {
                self.saveTask = nil
                return
            }
            do {
                try await self.repository.savePlaybackEvent(event)
                self.replace(event)
            }
            catch { self.message = error.localizedDescription }
            self.saveTask = nil
        }
    }

    private func saveImmediately(_ event: PlaybackEvent) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do { try await self.repository.savePlaybackEvent(event) }
            catch { self.message = error.localizedDescription }
            self.saveTask = nil
        }
    }

    private func resolve(_ ids: [Track.ID]) -> [Track] {
        let byID = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    private func publishAnalyticsRevision() {
        analyticsRevision &+= 1
        onAnalyticsRevision?(analyticsRevision)
    }
}
