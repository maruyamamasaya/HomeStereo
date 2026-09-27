import Foundation
import HomeStereoAppCore
import Testing
@testable import HomeStereoDLNAAppCore

@MainActor
@Test func analyticsInvalidationLoadsOnlyWhileViewIsActive() async throws {
    let repository = CountingAnalyticsRepository()
    let store = AnalyticsStore(repository: repository)

    store.invalidate()
    try await Task.sleep(for: .milliseconds(50))
    #expect(await repository.loadCount == 0)

    await store.activate()
    #expect(await repository.loadCount == 1)

    store.deactivate()
    store.invalidate()
    try await Task.sleep(for: .milliseconds(50))
    #expect(await repository.loadCount == 1)

    await store.activate()
    #expect(await repository.loadCount == 2)
}

@MainActor
@Test func playbackPreferenceStoreAdjustsOneStepAndClampsToMyMusicRange() async throws {
    let trackID = UUID()
    let repository = PreferenceRepository(
        values: [TrackPreference(trackID: trackID, playbackPreference: -5)]
    )
    let store = PlaybackPreferenceStore(repository: repository)

    await store.load()
    #expect(store.preference(for: trackID) == -5)

    await store.adjustPreference(trackID: trackID, delta: 1)
    #expect(store.preference(for: trackID) == -4)
    #expect(await repository.savedValues == [-4])

    for _ in 0..<20 { await store.adjustPreference(trackID: trackID, delta: 1) }
    #expect(store.preference(for: trackID) == 10)
    #expect(await repository.savedValues.last == 10)
    let savedCountAtUpperLimit = await repository.savedValues.count
    await store.adjustPreference(trackID: trackID, delta: 1)
    #expect(await repository.savedValues.count == savedCountAtUpperLimit)

    for _ in 0..<20 { await store.adjustPreference(trackID: trackID, delta: -1) }
    #expect(store.preference(for: trackID) == -10)
    #expect(await repository.savedValues.last == -10)
    let savedCountAtLowerLimit = await repository.savedValues.count
    await store.adjustPreference(trackID: trackID, delta: -1)
    #expect(await repository.savedValues.count == savedCountAtLowerLimit)
}

private actor CountingAnalyticsRepository: AnalyticsPersisting {
    private(set) var loadCount = 0

    func loadAnalyticsContext() async throws -> AnalyticsContext {
        loadCount += 1
        return AnalyticsContext(tracks: [], events: [], favorites: [], preferences: [], playlists: [])
    }

    func saveTrackPreference(_ preference: TrackPreference) async throws {}
    func deleteAnalyticsHistory(trackID: Track.ID?) async throws {}
}

private actor PreferenceRepository: TrackPreferencePersisting {
    let values: [TrackPreference]
    private(set) var savedValues: [Int] = []

    init(values: [TrackPreference]) { self.values = values }

    func loadTrackPreferences() async throws -> [TrackPreference] { values }
    func saveTrackPreference(_ preference: TrackPreference) async throws {
        savedValues.append(preference.playbackPreference)
    }
}
