import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

@MainActor
@Observable
public final class AnalyticsStore {
    public private(set) var snapshot = AnalyticsSnapshot.empty()
    public private(set) var isLoading = false
    public private(set) var errorMessage: String?
    public private(set) var revision = 0
    public private(set) var fullSnapshot = AnalyticsSnapshot.empty()
    public var period = AnalyticsPeriod.all
    public var startDate = Date.now
    public var endDate = Date.now

    @ObservationIgnored private let repository: any AnalyticsPersisting
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var invalidationTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var needsRefresh = true

    public init(repository: any AnalyticsPersisting) {
        self.repository = repository
    }

    deinit { refreshTask?.cancel(); invalidationTask?.cancel() }

    public func activate() async {
        isActive = true
        if needsRefresh || snapshot.generatedAt == .distantPast { await refresh() }
    }

    public func deactivate() {
        isActive = false
        invalidationTask?.cancel()
        invalidationTask = nil
    }

    public func invalidate() {
        needsRefresh = true
        guard isActive else { return }
        invalidationTask?.cancel()
        invalidationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
            self.invalidationTask = nil
        }
    }

    public func refresh() async {
        generation &+= 1
        let requestedGeneration = generation
        refreshTask?.cancel()
        isLoading = true
        errorMessage = nil
        let repository = self.repository
        let interval = period.interval(now: .now, start: startDate, end: endDate)
        let task = Task { @MainActor [weak self] in
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    let context = try await repository.loadAnalyticsContext()
                    try Task.checkCancellation()
                    return (AnalyticsService.makeSnapshot(context: context, interval: interval),
                            AnalyticsService.makeSnapshot(context: context))
                }.value
                guard let self, !Task.isCancelled, requestedGeneration == self.generation else { return }
                self.snapshot = value.0
                self.fullSnapshot = value.1
                self.revision &+= 1
                self.isLoading = false
                self.needsRefresh = false
            } catch is CancellationError {
                guard let self, requestedGeneration == self.generation else { return }
                self.isLoading = false
            } catch {
                guard let self, requestedGeneration == self.generation else { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
        refreshTask = task
        await task.value
    }

    public func setPreference(trackID: Track.ID, value: Int) async {
        do {
            try await repository.saveTrackPreference(
                TrackPreference(trackID: trackID, playbackPreference: value)
            )
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    public func adjustPreference(trackID: Track.ID, delta: Int) async {
        guard delta == -1 || delta == 1 else { return }
        let currentValue = snapshot.allTracks.first { $0.trackID == trackID }?.playbackPreference ?? 0
        await setPreference(trackID: trackID, value: currentValue + delta)
    }

    public func resetHistory(trackID: Track.ID? = nil) async {
        do {
            try await repository.deleteAnalyticsHistory(trackID: trackID)
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    public func dismissError() { errorMessage = nil }
}

@MainActor
@Observable
public final class PlaybackPreferenceStore {
    public private(set) var values: [Track.ID: Int] = [:]
    public private(set) var errorMessage: String?
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let repository: any TrackPreferencePersisting

    public init(repository: any TrackPreferencePersisting) {
        self.repository = repository
    }

    public func load() async {
        do {
            values = Dictionary(uniqueKeysWithValues: try await repository.loadTrackPreferences().map {
                ($0.trackID, $0.playbackPreference)
            })
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    public func preference(for trackID: Track.ID) -> Int {
        values[trackID] ?? 0
    }

    public func setPreference(trackID: Track.ID, value: Int) async {
        do {
            let preference = TrackPreference(trackID: trackID, playbackPreference: value)
            try await repository.saveTrackPreference(preference)
            values[trackID] = preference.playbackPreference
            errorMessage = nil
            onChange?()
        } catch { errorMessage = error.localizedDescription }
    }

    public func adjustPreference(trackID: Track.ID, delta: Int) async {
        guard delta == -1 || delta == 1 else { return }
        let previousValue = preference(for: trackID)
        let preference = TrackPreference(
            trackID: trackID,
            playbackPreference: previousValue + delta
        )
        guard preference.playbackPreference != previousValue else { return }

        // Update first so successive button presses always use the latest local value.
        values[trackID] = preference.playbackPreference
        do {
            try await repository.saveTrackPreference(preference)
            errorMessage = nil
            onChange?()
        } catch {
            if values[trackID] == preference.playbackPreference {
                values[trackID] = previousValue
            }
            errorMessage = error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }
}
