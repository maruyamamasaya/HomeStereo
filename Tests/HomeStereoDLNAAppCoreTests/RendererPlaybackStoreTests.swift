import Foundation
import HomeStereoAppCore
import HomeStereoKit
import Testing
@testable import HomeStereoDLNAAppCore

@MainActor
@Test func stereoPreparationAcceptsSonyAutoPlayingState() {
    let expectedURI = URL(string: "http://192.168.0.35:8765/tracks/left?token=secret")!
    #expect(RendererPlaybackStore.isPreparedTransportState("STOPPED"))
    #expect(RendererPlaybackStore.isPreparedTransportState("PAUSED_PLAYBACK"))
    #expect(RendererPlaybackStore.isPreparedTransportState("PLAYING"))
    #expect(!RendererPlaybackStore.isPreparedTransportState("TRANSITIONING"))
    #expect(RendererPlaybackStore.isStereoRendererPrepared(
        reportedURI: expectedURI.absoluteString, expectedURI: expectedURI, state: "PLAYING"
    ))
    #expect(!RendererPlaybackStore.isStereoRendererPrepared(
        reportedURI: "http://192.168.0.35/old-track", expectedURI: expectedURI, state: "PLAYING"
    ))
}

@MainActor
@Test func rendererStoreDefaultsToStable48kHz() {
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []),
        descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: FakeController()
    )
    #expect(store.stereoOutputQuality == .stable48kHz)
    #expect(store.isThisMacSelected)
    #expect(store.destination == .songs)
    #expect(store.hasSelectedOutput)
    #expect(store.canPlaySelectedOutput)
    #expect(store.selectedOutputName == "このMac")
    store.shutdown()
}

@MainActor
@Test func normalizationAppliesPerTrackAndToggleRestoresPlayerVolume() async {
    let player = FakeLocalAudioPlayer()
    let store = RendererPlaybackStore(discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController(),
        localPlayer: player, pollingInterval: .seconds(60))
    let id = UUID()
    store.configureNormalization(features: [id: FeatureValues(values: ["integratedLUFS": -8, "truePeakDBTP": -1, "normalizationGainDB": -4])], enabled: true)
    store.selectThisMac()
    #expect(store.selectLibraryFile(URL(fileURLWithPath: "/tmp/normalization.mp3"), expectedDuration: 60, trackID: id))
    await store.play()
    #expect(abs(player.amplitude - Float(pow(10, -8.0 / 20))) < 0.00001)
    store.configureNormalization(features: [:], enabled: false)
    #expect(player.amplitude == 1)
    store.shutdown()
}

@MainActor
@Test func thisMacOutputUsesLocalPlayerAndPublishesPlaybackState() async {
    let localPlayer = FakeLocalAudioPlayer()
    localPlayer.duration = 123
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []),
        descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: FakeController(),
        localPlayer: localPlayer,
        pollingInterval: .seconds(60)
    )
    let fileURL = URL(fileURLWithPath: "/tmp/home-stereo-local-output.mp3")
    var finishedCount = 0
    store.onTrackFinished = { finishedCount += 1 }

    store.selectThisMac()
    #expect(store.isThisMacSelected)
    #expect(store.selectedOutputName == "このMac")
    #expect(store.canPlaySelectedOutput)
    #expect(store.canSeekSelectedOutput)
    #expect(!store.canControlSelectedOutputVolume)
    #expect(store.selectLibraryFile(fileURL, expectedDuration: 120, trackID: UUID()))

    await store.play()
    #expect(localPlayer.loadedURL == fileURL)
    #expect(localPlayer.playCount == 1)
    #expect(store.playbackState == .playing)
    #expect(store.duration == 123)

    localPlayer.position = 12
    await store.refreshState()
    #expect(store.elapsed == 12)
    await store.pause()
    #expect(localPlayer.pauseCount == 1)
    #expect(store.playbackState == .paused)
    await store.seek(to: 30)
    #expect(localPlayer.position == 30)

    await store.play()
    localPlayer.finish()
    #expect(finishedCount == 1)
    #expect(store.playbackState == .stopped)
    #expect(store.elapsed == 123)
    store.shutdown()
}

@Test func stereoBalanceKeepsFavoredSideAtMasterVolume() {
    var levels = RendererPlaybackStore.stereoVolumes(master: 40, balance: 0)
    #expect(levels.left == 40)
    #expect(levels.right == 40)

    levels = RendererPlaybackStore.stereoVolumes(master: 40, balance: 0.25)
    #expect(levels.left == 30)
    #expect(levels.right == 40)

    levels = RendererPlaybackStore.stereoVolumes(master: 40, balance: -0.5)
    #expect(levels.left == 40)
    #expect(levels.right == 20)

    levels = RendererPlaybackStore.stereoVolumes(master: 120, balance: 1)
    #expect(levels.left == 0)
    #expect(levels.right == 100)
}

@MainActor
@Test func stereoVolumeCommandsApplyCurrentBalanceToBothRenderers() async {
    let leftResponse = stereoResponse(address: "192.168.0.105", id: "left")
    let rightResponse = stereoResponse(address: "192.168.0.106", id: "right")
    let leftController = FakeController()
    let rightController = FakeController()
    let descriptions = StereoDescriptions(renderers: [
        leftResponse.location: stereoRenderer(modelName: "SRS-HG10", response: leftResponse),
        rightResponse.location: stereoRenderer(modelName: "SRS-HG1", response: rightResponse),
    ])
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [leftResponse, rightResponse]),
        descriptions: descriptions,
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(),
        controller: leftController, secondaryController: rightController,
        pollingInterval: .seconds(60)
    )

    await store.discoverRenderers()
    store.selectSonyStereo()
    await store.refreshState()
    await store.setVolume(40)
    await store.setStereoBalance(0.25)

    #expect(await leftController.setVolumes.suffix(2) == [40, 30])
    #expect(await rightController.setVolumes.suffix(2) == [40, 40])
    #expect(store.volume == 40)
    #expect(store.stereoLeftVolume == 30)
    #expect(store.stereoRightVolume == 40)
    #expect(store.stereoBalance == 0.25)
    store.shutdown()
}

@MainActor
@Test func sonyStereoPrewarmsAndReusesPreparedMedia() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.wav")
    try Data("audio".utf8).write(to: source)
    let nextSource = root.appendingPathComponent("next.wav")
    try Data("next".utf8).write(to: nextSource)
    let leftResponse = stereoResponse(address: "192.168.0.105", id: "left-prewarm")
    let rightResponse = stereoResponse(address: "192.168.0.106", id: "right-prewarm")
    let preparer = CountingStereoPreparer(root: root)
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [leftResponse, rightResponse]),
        descriptions: StereoDescriptions(renderers: [
            leftResponse.location: stereoRenderer(modelName: "SRS-HG10", response: leftResponse),
            rightResponse.location: stereoRenderer(modelName: "SRS-HG1", response: rightResponse),
        ]),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(),
        controller: FakeController(), secondaryController: FakeController(),
        stereoPreparer: preparer, pollingInterval: .seconds(60)
    )

    await store.discoverRenderers()
    store.selectSonyStereo()
    #expect(store.selectLibraryFile(source, expectedDuration: 120, trackID: UUID()))
    for _ in 0..<20 where preparer.preparationCount == 0 {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(preparer.preparationCount == 1)

    await store.play()
    #expect(preparer.preparationCount == 1)
    #expect(store.selectLibraryFile(source, expectedDuration: 120, trackID: UUID()))
    await store.play()
    #expect(preparer.preparationCount == 1)

    await store.prewarmStereoMedia(fileURL: nextSource)
    #expect(preparer.preparationCount == 2)
    #expect(store.selectLibraryFile(nextSource, expectedDuration: 120, trackID: UUID()))
    await store.play()
    #expect(preparer.preparationCount == 2)
    store.shutdown()
}

@MainActor
@Test func synchronizationCheckPlaysWithoutChangingTheSelectedTrackOrAdvancingQueue() async {
    let leftResponse = stereoResponse(address: "192.168.0.105", id: "left-sync")
    let rightResponse = stereoResponse(address: "192.168.0.106", id: "right-sync")
    let leftController = FakeController()
    let rightController = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [leftResponse, rightResponse]),
        descriptions: StereoDescriptions(renderers: [
            leftResponse.location: stereoRenderer(modelName: "SRS-HG10", response: leftResponse),
            rightResponse.location: stereoRenderer(modelName: "SRS-HG1", response: rightResponse),
        ]),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: leftController,
        secondaryController: rightController,
        pollingInterval: .seconds(60)
    )
    var trackFinishedCount = 0
    store.onTrackFinished = { trackFinishedCount += 1 }

    await store.discoverRenderers()
    store.selectSonyStereo()
    await store.refreshState()
    await store.playStereoSynchronizationCheck()

    #expect(store.isStereoSynchronizationCheckActive)
    #expect(store.playbackState == .playing)
    #expect(store.media == nil)
    #expect(await leftController.actions.suffix(2) == ["SetAVTransportURI", "Play"])
    #expect(await rightController.actions.suffix(2) == ["SetAVTransportURI", "Play"])

    await leftController.setTransportState("STOPPED")
    await leftController.setPositionInfo(PositionInfo(
        duration: store.duration,
        position: store.duration,
        trackURI: await leftController.trackURI
    ))
    await store.refreshState()

    #expect(!store.isStereoSynchronizationCheckActive)
    #expect(trackFinishedCount == 0)
    store.shutdown()
}

@MainActor
@Test func stereoConnectionResetRebuildsBothStreamsAndKeepsCalibration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source.wav")
    try Data("audio".utf8).write(to: source)
    let leftResponse = stereoResponse(address: "192.168.0.105", id: "left-reset")
    let rightResponse = stereoResponse(address: "192.168.0.106", id: "right-reset")
    let leftController = FakeController()
    let rightController = FakeController()
    let preparer = CountingStereoPreparer(root: root)
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [leftResponse, rightResponse]),
        descriptions: StereoDescriptions(renderers: [
            leftResponse.location: stereoRenderer(modelName: "SRS-HG10", response: leftResponse),
            rightResponse.location: stereoRenderer(modelName: "SRS-HG1", response: rightResponse),
        ]),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(),
        controller: leftController, secondaryController: rightController,
        stereoPreparer: preparer, pollingInterval: .seconds(60)
    )

    await store.discoverRenderers()
    store.selectSonyStereo()
    store.setStereoChannelsSwapped(true)
    store.setStereoDelayedChannel(.right)
    store.setStereoDelayMilliseconds(275)
    #expect(store.selectLibraryFile(source, expectedDuration: 120, trackID: UUID()))
    await store.play()
    await leftController.clearActions()
    await rightController.clearActions()

    await store.resetStereoConnection()

    #expect(store.playbackState == .playing)
    #expect(store.elapsed == 0)
    #expect(store.stereoChannelsSwapped)
    #expect(store.stereoDelayedChannel == .right)
    #expect(store.stereoDelayMilliseconds == 275)
    #expect(preparer.preparationCount == 2)
    #expect(await leftController.actions == ["Stop", "SetAVTransportURI", "Play"])
    #expect(await rightController.actions == ["Stop", "SetAVTransportURI", "Play"])
    store.shutdown()
}

@MainActor
@Test func discoveryLoadsDescriptionsAndSelectsRenderer() async throws {
    let response = sampleResponse()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response, response]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: FakeController()
    )

    await store.discoverRenderers()
    #expect(store.devices.count == 1)
    #expect(store.devices[0].friendlyName == "Stereo Pair")
    #expect(store.devices[0].supportsAVTransport)
    store.selectDevice(store.devices[0].id)
    #expect(store.selectedDevice?.description?.connectionManager != nil)
}

@MainActor
@Test func emptyListSelectionDoesNotClearSelectedRenderer() async {
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: FakeController()
    )

    await store.discoverRenderers()
    let selectedID = store.devices[0].id
    store.selectDevice(selectedID)

    store.selectDevice(nil)

    #expect(store.selectedDeviceID == selectedID)
    #expect(store.selectedDevice?.id == selectedID)
    store.shutdown()
}

@MainActor
@Test func discoveryRetriesTransientNetworkFailureBeforeShowingAlert() async {
    let discovery = FlakyDiscovery(response: sampleResponse(), failuresBeforeSuccess: 2)
    let store = RendererPlaybackStore(
        discovery: discovery,
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )

    await store.discoverRenderers()

    #expect(store.devices.count == 1)
    #expect(store.lastError == nil)
    #expect(await discovery.attemptCount == 3)
    store.shutdown()
}

@MainActor
@Test func discoveryDoesNotShowNonRendererDescriptionFailures() async {
    let unrelated = SSDPResponse(
        usn: "uuid:streaming-device::upnp:rootdevice",
        location: URL(string: "http://192.168.0.161:9080")!,
        searchTarget: "upnp:rootdevice",
        server: "Unrelated/1.0",
        sourceAddress: "192.168.0.161"
    )
    let renderer = sampleResponse()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [unrelated, renderer]),
        descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(),
        serverFactory: FakeServerFactory(),
        controller: FakeController()
    )

    await store.discoverRenderers()

    #expect(store.devices.count == 1)
    #expect(store.devices[0].discovery == renderer)
    #expect(store.devices[0].descriptionError != nil)
}

@MainActor
@Test func discoveryKeepsStableNameOrderAndMovesSelectionToFront() async {
    let first = SSDPResponse(
        usn: "uuid:first::urn:schemas-upnp-org:device:MediaRenderer:1",
        location: URL(string: "http://192.168.0.20/device.xml")!,
        searchTarget: "urn:schemas-upnp-org:device:MediaRenderer:1",
        server: "Renderer/1.0", sourceAddress: "192.168.0.20"
    )
    let second = SSDPResponse(
        usn: "uuid:second::urn:schemas-upnp-org:device:MediaRenderer:1",
        location: URL(string: "http://192.168.0.10/device.xml")!,
        searchTarget: "urn:schemas-upnp-org:device:MediaRenderer:1",
        server: "Renderer/1.0", sourceAddress: "192.168.0.10"
    )
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [first, second]), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )

    await store.discoverRenderers()
    #expect(store.devices.map(\.friendlyName) == ["192.168.0.10", "192.168.0.20"])
    #expect(store.lastDiscoveryAt != nil)
    let firstDeviceID = store.devices.first(where: { $0.discovery.sourceAddress == first.sourceAddress })?.id
    store.selectDevice(firstDeviceID)
    #expect(store.devices.map(\.id).first == firstDeviceID)
    await store.discoverRenderers()
    #expect(store.devices.map(\.id).first == firstDeviceID)
    store.shutdown()
}

@MainActor
@Test func successfulRefreshClearsDismissibleCommunicationError() async {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    await controller.setFailsTransport(true)
    await store.refreshState()
    #expect(store.lastError == nil)
    await store.refreshState()
    await store.refreshState()
    #expect(store.lastError != nil)
    store.dismissError()
    #expect(store.lastError == nil)
    await controller.setFailsTransport(false)
    await store.refreshState()
    #expect(store.lastError == nil)
    store.shutdown()
}

@MainActor
@Test func playbackTransitionsThroughPlayPauseAndStop() async throws {
    let file = URL(fileURLWithPath: "/tmp/song.mp3")
    let response = sampleResponse()
    let controller = FakeController()
    let activity = FakePlaybackActivityManager()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: file),
        serverFactory: FakeServerFactory(),
        controller: controller,
        activityManager: activity
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.chooseFile()
    await store.play()
    #expect(store.playbackState == .playing)
    #expect(activity.isActive)
    #expect(await controller.actions == ["SetAVTransportURI", "Play"])
    await controller.setTransportState("PAUSED_PLAYBACK")
    await store.pause()
    #expect(store.playbackState == .paused)
    #expect(!activity.isActive)
    await controller.setTransportState("STOPPED")
    await store.stop()
    #expect(store.playbackState == .stopped)
    #expect(!activity.isActive)
    store.shutdown()
}

@MainActor
@Test func pauseRetriesAndWaitsUntilRendererReportsPaused() async throws {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(),
        controller: controller,
        pollingInterval: .seconds(60),
        commandConfirmationInterval: .milliseconds(1)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.chooseFile()
    await store.play()
    await controller.clearActions()
    await controller.setTransportStateSequence(["TRANSITIONING", "PLAYING", "PAUSED_PLAYBACK"])

    await store.pause()

    #expect(store.playbackState == .paused)
    #expect(store.lastError == nil)
    #expect(await controller.actions == ["Pause", "Pause"])
    store.shutdown()
}

@MainActor
@Test func pauseFallsBackToConfirmedStopWhenRendererRejectsPause() async throws {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(),
        controller: controller,
        pollingInterval: .seconds(60),
        commandConfirmationInterval: .milliseconds(1)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.chooseFile()
    await store.play()
    await controller.clearActions()
    await controller.setFailsPause(true)
    await controller.setTransportStateSequence([
        "PLAYING", "PLAYING", "PLAYING", "PLAYING", "PLAYING", "STOPPED",
    ])

    await store.pause()

    #expect(store.playbackState == .stopped)
    #expect(store.lastError == nil)
    #expect(await controller.actions == ["Pause", "Pause", "Stop"])
    store.shutdown()
}

@MainActor
@Test func stopRetriesAndWaitsUntilRendererReportsStopped() async throws {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(),
        controller: controller,
        pollingInterval: .seconds(60),
        commandConfirmationInterval: .milliseconds(1)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.chooseFile()
    await store.play()
    await controller.clearActions()
    await controller.setTransportStateSequence(["TRANSITIONING", "TRANSITIONING", "STOPPED"])

    await store.stop()

    #expect(store.playbackState == .stopped)
    #expect(store.lastError == nil)
    #expect(await controller.actions == ["Stop", "Stop"])
    store.shutdown()
}

@MainActor
@Test func stopKeepsPlayingStateAndReportsFailureWhenRendererNeverStops() async throws {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(),
        controller: controller,
        pollingInterval: .seconds(60),
        commandConfirmationInterval: .milliseconds(1)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.chooseFile()
    await store.play()
    await controller.clearActions()
    await controller.setTransportState("PLAYING")

    await store.stop()

    #expect(store.playbackState == .playing)
    #expect(store.lastError?.action == "Stop")
    #expect(await controller.actions == ["Stop", "Stop"])
    store.shutdown()
}

@MainActor
@Test func selectedRendererKeepsPollingExternalStateAfterManualStop() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller,
        pollingInterval: .milliseconds(10)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    try await Task.sleep(for: .milliseconds(30))
    await controller.setTransportState("PLAYING")
    try await Task.sleep(for: .milliseconds(40))
    #expect(store.playbackState == .playing)
    await controller.setTransportState("PAUSED_PLAYBACK")
    try await Task.sleep(for: .milliseconds(40))
    #expect(store.playbackState == .paused)
    store.shutdown()
}

@MainActor
@Test func selectedRendererDisappearanceClearsSelectionAndReportsDisconnect() async throws {
    let response = sampleResponse()
    let discovery = MutableDiscovery(responses: [response])
    let store = RendererPlaybackStore(
        discovery: discovery, descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    var failures = 0
    store.onCommunicationFailure = { _ in failures += 1 }
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    await discovery.setResponses([])
    await store.discoverRenderers()
    #expect(store.selectedDeviceID != nil)
    #expect(failures == 0)
    await store.discoverRenderers()
    #expect(store.selectedDeviceID != nil)
    #expect(failures == 0)
    await store.discoverRenderers()
    #expect(store.selectedDeviceID == nil)
    #expect(store.playbackState == .unknown)
    #expect(failures == 1)
    store.shutdown()
}

@MainActor
@Test func volumeReadFailureDoesNotDisconnectReachableRenderer() async {
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]),
        descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    var failures = 0
    store.onCommunicationFailure = { _ in failures += 1 }
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    await controller.setFailsVolume(true)

    await store.refreshState()

    #expect(store.playbackState == .stopped)
    #expect(store.lastError == nil)
    #expect(failures == 0)
    store.shutdown()
}

@Test func rendererIdentityUsesUSNUDNWhenDescriptionIsTemporarilyUnavailable() {
    let response = sampleResponse()
    let described = RendererDevice(discovery: response, description: sampleRenderer())
    let unresolved = RendererDevice(discovery: response, descriptionError: "temporary")
    #expect(described.id == "uuid:pair")
    #expect(unresolved.id == described.id)
}

@MainActor
@Test func reconnectByUDNOnlySynchronizesAndNeverStartsPlaybackOrChangesVolume() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile(); await store.play()
    await controller.clearActions()
    store.prepareForSystemInterruption()
    let reconnected = await store.reconnect(udn: "uuid:pair")
    #expect(reconnected)
    #expect(await controller.actions.isEmpty)
    #expect(store.playbackState == .stopped)
    store.shutdown()
}

@MainActor
@Test func librarySelectionUsesExistingSingleTrackHTTPPlaybackPath() async throws {
    let file = URL(fileURLWithPath: "/tmp/library/folder/song.flac")
    let trackID = UUID()
    let response = sampleResponse()
    let serverFactory = CapturingServerFactory()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: serverFactory, controller: FakeController()
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    store.selectLibraryFile(file, trackID: trackID)
    await store.play()

    #expect(store.media?.fileURL == file)
    #expect(store.selectedLibraryTrackID == trackID)
    #expect(serverFactory.receivedFileURL == file)
}

@MainActor
@Test func onlyNearEndPlayingToStoppedSignalsCompletionOnce() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    var completions = 0
    var failures = 0
    store.onTrackFinished = { completions += 1 }
    store.onCommunicationFailure = { _ in failures += 1 }
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile(); await store.play()
    await controller.setPosition(119)
    await store.refreshState()
    await controller.setTransportState("STOPPED")
    await controller.setPosition(0)
    await store.refreshState()
    #expect(completions == 1)
    await store.refreshState()
    #expect(completions == 1)

    await store.play()
    await controller.setFailsTransport(true)
    await store.refreshState()
    #expect(failures == 0)
    await store.refreshState()
    #expect(failures == 0)
    #expect(store.playbackState == .playing)
    await store.refreshState()
    #expect(completions == 1)
    #expect(failures == 1)
    #expect(store.playbackState == .unknown)
}

@MainActor
@Test func stoppedAwayFromEndDoesNotAdvanceQueue() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    var completions = 0
    store.onTrackFinished = { completions += 1 }
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile(); await store.play()
    await controller.setPosition(24)
    await store.refreshState()
    await controller.setTransportState("STOPPED")
    await store.refreshState()
    #expect(completions == 0)
}

@MainActor
@Test func stalePollingResponseFromPreviousGenerationIsIgnored() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id)
    store.selectLibraryFile(URL(fileURLWithPath: "/tmp/old.mp3"), expectedDuration: 120)
    await store.play()
    await controller.setTransportDelay(.milliseconds(80))
    await controller.setTransportState("PAUSED_PLAYBACK")
    let stalePoll = Task { await store.refreshState() }
    try await Task.sleep(for: .milliseconds(20))
    store.selectLibraryFile(URL(fileURLWithPath: "/tmp/new.mp3"), expectedDuration: 300)
    await stalePoll.value
    #expect(store.media?.title == "new")
    #expect(store.duration == 300)
    #expect(store.playbackState == .stopped)
}

@MainActor
@Test func pollingReadsTransportAndPositionConcurrentlyAndThrottlesVolume() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller,
        pollingInterval: .seconds(60)
    )
    await store.discoverRenderers()
    store.selectDevice(store.devices[0].id)
    try await Task.sleep(for: .milliseconds(30))
    await controller.resetReadMetrics()
    await controller.setTransportDelay(.milliseconds(20))
    await controller.setPositionDelay(.milliseconds(20))

    for _ in 0..<6 { await store.refreshState() }

    #expect(await controller.transportReadCount == 6)
    #expect(await controller.positionReadCount == 6)
    #expect(await controller.volumeReadCount <= 2)
    #expect(await controller.maximumConcurrentReads == 2)
    store.shutdown()
}

@MainActor
@Test func laterRefreshWinsOverOlderResponseWithinSameGeneration() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id)
    await controller.setTransportState("PAUSED_PLAYBACK")
    await controller.setTransportDelay(.milliseconds(80))
    let staleRefresh = Task { await store.refreshState() }
    try await Task.sleep(for: .milliseconds(20))
    await controller.setTransportState("PLAYING")
    await controller.setTransportDelay(.zero)
    await store.refreshState()
    await staleRefresh.value
    #expect(store.playbackState == .playing)
    store.shutdown()
}

@MainActor
@Test func rendererSideTrackChangeInvalidatesLocalNowPlayingWithoutAdvancing() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    var externalChanges = 0
    var completions = 0
    store.onRendererTrackChanged = { externalChanges += 1 }
    store.onTrackFinished = { completions += 1 }
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile(); await store.play()
    await controller.setTransportState("PLAYING")
    await controller.setPositionInfo(PositionInfo(duration: 200, position: 15, trackURI: "http://controller/external.mp3"))
    await store.refreshState()
    #expect(externalChanges == 1)
    #expect(completions == 0)
    #expect(store.media == nil)
    #expect(store.playbackState == .playing)
}

@MainActor
@Test func playbackCommandsAreSerialized() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/tmp/song.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile()
    await controller.setCommandDelay(.milliseconds(20))
    async let play: Void = store.play()
    async let pause: Void = store.pause()
    async let seek: Void = store.seek(to: 30)
    _ = await (play, pause, seek)
    #expect(await controller.maximumConcurrentCommands == 1)
}

@MainActor
@Test func exportedDiagnosticsExcludePathsAddressesAndTokens() async throws {
    let response = sampleResponse()
    let controller = FakeController()
    let store = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [response]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: URL(fileURLWithPath: "/Users/private/Music/secret.mp3")),
        serverFactory: FakeServerFactory(), controller: controller
    )
    await store.discoverRenderers(); store.selectDevice(store.devices[0].id); store.chooseFile(); await store.play()
    await controller.setFailsTransport(true)
    await store.refreshState()
    await store.refreshState()
    await store.refreshState()
    let report = String(decoding: try store.diagnosticReportData(), as: UTF8.self)
    #expect(report.contains("GetTransportInfo / GetPositionInfo"))
    #expect(!report.contains("/Users/private"))
    #expect(!report.contains("192.168"))
    #expect(!report.contains("secret"))
}

@MainActor
@Test func queuePersistsOrderCurrentPositionShuffleAndRepeat() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("queue.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let ids = [UUID(), UUID(), UUID()]
    await queue.append(trackIDs: ids)
    await queue.setRepeatMode(.all)
    await queue.toggleShuffle()

    let restored = QueueStore(repository: repository, library: library, playback: playback)
    await restored.restore()
    #expect(Set(restored.items.map(\.trackID)) == Set(ids))
    #expect(restored.currentIndex == 0)
    #expect(restored.repeatMode == .all)
    #expect(restored.shuffleEnabled)
}

@MainActor
@Test func multipleQueueAndPlaylistSelectionDeletesOnlyReferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("selection.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    await queue.append(trackIDs: [UUID(), UUID(), UUID()])
    queue.selectedItemIDs = Set(queue.items.prefix(2).map(\.id))
    await queue.removeSelected()
    #expect(queue.items.count == 1)

    let playlists = PlaylistStore(repository: repository, library: library, queue: queue, files: FakePlaylistFiles())
    await playlists.create(name: "One")
    await playlists.create(name: "Two")
    playlists.selectedPlaylistIDs = Set(playlists.playlists.map(\.id))
    await playlists.deleteSelectedPlaylists()
    #expect(playlists.playlists.isEmpty)
}

@MainActor
@Test func selectedQueueItemsMoveAfterCurrentAndKeepTheirOrder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("queue-move-next.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let ids = [UUID(), UUID(), UUID(), UUID()]
    await queue.append(trackIDs: ids)
    queue.selectedItemIDs = Set([queue.items[2].id, queue.items[3].id])
    await queue.moveSelectedNext()

    #expect(queue.items.map(\.trackID) == [ids[0], ids[2], ids[3], ids[1]])
    #expect(queue.currentIndex == 0)
    #expect(queue.selectedItemIDs == Set(queue.items[1...2].map(\.id)))
}

@MainActor
@Test func generatedQueueIsLimitedToOneHundredAndCanMoveSingleItems() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("queue-limit.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let ids = (0..<30_000).map { _ in UUID() }

    await queue.playNow(trackIDs: ids, startingAt: ids[15_000], source: .library)

    #expect(queue.items.count == QueueStore.maximumItemCount)
    #expect(queue.items.contains { $0.trackID == ids[15_000] })
    let movedID = queue.items[1].id
    let movedTrackID = queue.items[1].trackID
    await queue.moveItem(id: movedID, by: -1)
    #expect(queue.items[0].trackID == movedTrackID)
}

@MainActor
@Test func queueHandleMoveAndSingleItemDeleteKeepCurrentTrackStable() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("queue-handle.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let ids = [UUID(), UUID(), UUID(), UUID()]
    await queue.append(trackIDs: ids)
    let currentItemID = queue.items[0].id
    let movedItemID = queue.items[3].id

    await queue.move(itemID: movedItemID, toOffset: 1)
    #expect(queue.items.map(\.trackID) == [ids[0], ids[3], ids[1], ids[2]])
    #expect(queue.items[queue.currentIndex ?? -1].id == currentItemID)

    await queue.remove(itemID: movedItemID)
    #expect(queue.items.map(\.trackID) == [ids[0], ids[1], ids[2]])
    #expect(queue.items[queue.currentIndex ?? -1].id == currentItemID)
}

@MainActor
@Test func appendedQueueOverOneHundredDropsOldestItems() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("rolling-queue.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let ids = (0...QueueStore.maximumItemCount).map { _ in UUID() }

    await queue.append(trackIDs: ids)

    #expect(queue.items.count == QueueStore.maximumItemCount)
    #expect(queue.items.first?.trackID == ids[1])
    #expect(queue.items.last?.trackID == ids.last)
    #expect(queue.currentIndex == 0)
}

@MainActor
@Test func individualTrackClickActionsAppendOrInterruptWithoutLosingWaitingQueue() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("click-queue.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let tracks = (1...5).map { number in
        let url = root.appendingPathComponent("\(number).mp3")
        try? Data().write(to: url)
        return Track(
            libraryFolderID: folder.id, relativePath: url.lastPathComponent,
            url: url, title: "Track \(number)", duration: 60
        )
    }
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: tracks, scannedAt: .now)
    let localPlayer = FakeLocalAudioPlayer()
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(),
        controller: FakeController(), localPlayer: localPlayer, pollingInterval: .seconds(60)
    )
    playback.selectThisMac()
    let library = LibraryStore(
        scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository,
        changeMonitor: NoopFolderChangeMonitor(), lifecycleMonitor: NoopSystemEventMonitor(), changeDebounce: .zero
    )
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    var endReasons: [MyMusicPlaybackEndReason] = []
    queue.onTrackEnded = { endReasons.append($0) }

    await queue.append(trackIDs: Array(tracks[0...2].map(\.id)))
    await queue.play()
    #expect(queue.items.map(\.trackID) == tracks[0...2].map(\.id))
    #expect(queue.currentIndex == 0)
    #expect(localPlayer.playCount == 1)

    await queue.playImmediately(trackID: tracks[3].id, source: .library)
    #expect(queue.items.map(\.trackID) == [tracks[0].id, tracks[3].id, tracks[1].id, tracks[2].id])
    #expect(queue.currentIndex == 1)
    #expect(localPlayer.playCount == 2)
    #expect(endReasons == [.directSelection])

    await queue.pause()
    await queue.playImmediately(trackID: tracks[4].id, source: .library)
    #expect(queue.items.map(\.trackID) == [tracks[0].id, tracks[3].id, tracks[4].id, tracks[1].id, tracks[2].id])
    #expect(queue.currentIndex == 2)
    #expect(localPlayer.playCount == 3)
    #expect(localPlayer.loadedURL == tracks[4].url)
    #expect(endReasons == [.directSelection, .directSelection])

    await queue.append(trackIDs: [tracks[0].id])
    #expect(queue.items.map(\.trackID) == [tracks[0].id, tracks[3].id, tracks[4].id, tracks[1].id, tracks[2].id, tracks[0].id])
    #expect(queue.currentIndex == 2)
    #expect(localPlayer.playCount == 3)
    playback.shutdown(); library.pauseMonitoring()
}

@MainActor
@Test func recentHistoryKeepsOnlyLatestEventForEachTrack() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("history-dedup.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let trackID = UUID()
    let older = PlaybackEvent(trackID: trackID, startedAt: Date(timeIntervalSince1970: 100))
    let latest = PlaybackEvent(trackID: trackID, startedAt: Date(timeIntervalSince1970: 200), playedSeconds: 20)
    try await repository.savePlaybackEvent(older)
    try await repository.savePlaybackEvent(latest)
    let listening = ListeningStore(repository: repository, library: library, queue: queue)
    await listening.load()

    #expect(listening.events.count == 2)
    #expect(listening.recentEvents == [latest])
}

@MainActor
@Test func frequentHistoryBuildsCachedCountsFromTrackDictionary() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("frequent-history.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let track = Track(
        libraryFolderID: folder.id, relativePath: "song.mp3",
        url: root.appendingPathComponent("song.mp3"), title: "Song", duration: 60
    )
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: [track], scannedAt: .now)
    try await repository.savePlaybackEvent(PlaybackEvent(trackID: track.id, playedSeconds: 31))
    try await repository.savePlaybackEvent(PlaybackEvent(trackID: track.id, playedSeconds: 45))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(
        scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository,
        changeMonitor: NoopFolderChangeMonitor(), lifecycleMonitor: NoopSystemEventMonitor(), changeDebounce: .zero
    )
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let listening = ListeningStore(repository: repository, library: library, queue: queue)

    await listening.load()

    #expect(listening.frequentTracks == [FrequentTrack(trackID: track.id, playCount: 2)])
    playback.shutdown(); library.pauseMonitoring()
}

@MainActor
@Test func playlistPlaybackSkipsUnavailableReferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("playlist-playback.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let available = Track(
        libraryFolderID: folder.id, relativePath: "available.mp3",
        url: root.appendingPathComponent("available.mp3"), title: "Available"
    )
    let workBGM = Track(
        libraryFolderID: folder.id, relativePath: "work.mp3",
        url: root.appendingPathComponent("work.mp3"), title: "Work", genre: Track.workPlaybackGenre
    )
    let missing = Track(
        libraryFolderID: folder.id, relativePath: "missing.mp3",
        url: root.appendingPathComponent("missing.mp3"), title: "Missing", scanState: .missing
    )
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: [available, workBGM, missing], scannedAt: .now)
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository)
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let playlists = PlaylistStore(repository: repository, library: library, queue: queue, files: FakePlaylistFiles())
    await playlists.create(name: "Playable")
    let playlistID = try #require(playlists.selectedPlaylistID)
    await playlists.add(trackIDs: [available.id, workBGM.id, missing.id], to: playlistID)
    let playlist = try #require(playlists.selectedPlaylist)

    await playlists.play(playlist, shuffled: false)

    #expect(queue.items.map(\.trackID) == [available.id, workBGM.id])
}

@MainActor
@Test func overlappingNextDuringTrackStartCannotDesynchronizeQueuePosition() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let oneURL = root.appendingPathComponent("one.mp3")
    let twoURL = root.appendingPathComponent("two.mp3")
    try Data().write(to: oneURL); try Data().write(to: twoURL)
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("queue-race.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let tracks = [
        Track(libraryFolderID: folder.id, relativePath: "one.mp3", url: oneURL, title: "One"),
        Track(libraryFolderID: folder.id, relativePath: "two.mp3", url: twoURL, title: "Two")
    ]
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: tracks, scannedAt: .now)
    let controller = FakeController()
    await controller.setCommandDelay(.milliseconds(60))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    await playback.discoverRenderers(); playback.selectDevice(playback.devices[0].id)
    let library = LibraryStore(
        scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository,
        changeMonitor: NoopFolderChangeMonitor(), lifecycleMonitor: NoopSystemEventMonitor(), changeDebounce: .zero
    )
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    await queue.append(trackIDs: tracks.map(\.id))
    let starting = Task { await queue.play() }
    try await Task.sleep(for: .milliseconds(20))
    await queue.next()
    await starting.value
    #expect(queue.currentIndex == 0)
    #expect(playback.media?.title == "one")
    playback.shutdown(); library.pauseMonitoring()
}

@MainActor
@Test func realQueuePlaybackPersistsSessionsAndCarriesAdvanceSelectionReason() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let oneURL = root.appendingPathComponent("one.mp3")
    let twoURL = root.appendingPathComponent("two.mp3")
    try Data().write(to: oneURL); try Data().write(to: twoURL)
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("sessions.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let tracks = [
        Track(libraryFolderID: folder.id, relativePath: "one.mp3", url: oneURL, title: "One", duration: 100),
        Track(libraryFolderID: folder.id, relativePath: "two.mp3", url: twoURL, title: "Two", duration: 100)
    ]
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: tracks, scannedAt: .now)
    let controller = FakeController()
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: controller
    )
    await playback.discoverRenderers(); playback.selectDevice(playback.devices[0].id)
    let library = LibraryStore(
        scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository,
        changeMonitor: NoopFolderChangeMonitor(), lifecycleMonitor: NoopSystemEventMonitor(), changeDebounce: .zero
    )
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let listening = ListeningStore(
        repository: repository, library: library, queue: queue, myMusicRepository: repository
    )
    _ = listening

    await queue.playNow(trackIDs: tracks.map(\.id), source: .playlist)
    for position in 0...35 {
        queue.onTrackPosition?(Double(position))
    }
    await queue.next()
    for position in 0...35 {
        queue.onTrackPosition?(Double(position))
    }
    await queue.stop()
    try await Task.sleep(for: .milliseconds(50))

    let events = try await repository.loadMyMusicPlaybackEvents()
    #expect(events.count == 2)
    guard events.count == 2 else { return }
    #expect(events[0].selectionType == MyMusicSelectionType.manual.rawValue)
    #expect(events[0].playSource == MyMusicPlaySource.playlist.rawValue)
    #expect(events[0].skipped)
    #expect(events[1].selectionType == MyMusicSelectionType.userAdvanced.rawValue)
    #expect(!events[1].skipped)
    #expect(events.allSatisfy { $0.eventID.hasPrefix("mac-") && $0.platform == "macOS" })
    playback.shutdown(); library.pauseMonitoring()
}

@Test func m3u8RoundTripAndAmbiguousPathsRemainUnresolved() {
    let folder = UUID()
    let one = Track(libraryFolderID: folder, relativePath: "Album/one.mp3", url: URL(fileURLWithPath: "/tmp/one.mp3"), title: "One", artist: "Artist", duration: 60)
    let duplicateA = Track(libraryFolderID: folder, relativePath: "same.mp3", url: URL(fileURLWithPath: "/tmp/a.mp3"), title: "A")
    let duplicateB = Track(libraryFolderID: UUID(), relativePath: "same.mp3", url: URL(fileURLWithPath: "/tmp/b.mp3"), title: "B")
    let playlist = Playlist(name: "Export", items: [PlaylistItem(trackID: one.id)])
    let text = PlaylistStore.makeM3U8(playlist: playlist, tracks: [one])
    let roundTrip = PlaylistStore.parseM3U8(text, tracks: [one])
    #expect(roundTrip.trackIDs == [one.id])

    let ambiguous = PlaylistStore.parseM3U8("#EXTM3U\nsame.mp3\nmissing.mp3\n", tracks: [duplicateA, duplicateB])
    #expect(ambiguous.trackIDs.isEmpty)
    #expect(ambiguous.summary.ambiguous == ["same.mp3"])
    #expect(ambiguous.summary.unresolved == ["missing.mp3"])
}

@Test func nowPlayingSnapshotSeparatesArtistAlbumAndRendererState() throws {
    let presentation = NowPlayingPresentation(
        trackID: UUID(), title: "Song", artist: "Track Artist", album: "Album",
        duration: 245, elapsed: 31, state: .playing
    )
    let snapshot = try #require(NowPlayingSnapshot(presentation: presentation))
    #expect(snapshot.title == "Song")
    #expect(snapshot.artist == "Track Artist")
    #expect(snapshot.album == "Album")
    #expect(snapshot.duration == 245)
    #expect(snapshot.elapsed == 31)
    #expect(snapshot.isPlaying)
}

@MainActor
@Test func unifiedNowPlayingCoversDirectFileLoadingPauseFailureAndRendererChange() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directFile = root.appendingPathComponent("Direct Song.mp3")
    try Data().write(to: directFile)
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("now-playing.sqlite3"))
    let controller = FakeController()
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: [sampleResponse()]), descriptions: FakeDescriptions(renderer: sampleRenderer()),
        fileSelection: FakeFileSelection(url: directFile), serverFactory: FakeServerFactory(), controller: controller
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    var observedStates: [NowPlayingDisplayState] = []
    queue.onNowPlayingChange = { observedStates.append($0.state) }

    await playback.discoverRenderers()
    playback.selectDevice(playback.devices[0].id)
    playback.chooseFile()
    #expect(queue.nowPlaying.title == "Direct Song")
    #expect(queue.nowPlaying.state == .stopped)
    #expect(!queue.nowPlaying.isQueueTrack)

    await queue.play()
    #expect(queue.nowPlaying.state == .playing)
    #expect(observedStates.contains(.loading))
    await controller.setTransportState("PAUSED_PLAYBACK")
    await queue.togglePlayback()
    #expect(queue.nowPlaying.state == .paused)

    await controller.setFailsTransport(true)
    await playback.refreshState()
    #expect(queue.nowPlaying.state == .paused)
    await playback.refreshState()
    #expect(queue.nowPlaying.state == .paused)
    await playback.refreshState()
    #expect(queue.nowPlaying.state == .unknown)

    await controller.setFailsTransport(false)
    await playback.play()
    await controller.setTransportState("PLAYING")
    await controller.setPositionInfo(PositionInfo(duration: 200, position: 15, trackURI: "http://controller/external.mp3"))
    await playback.refreshState()
    #expect(queue.nowPlaying.title == nil)
    #expect(queue.nowPlaying.state == .unknown)
    playback.shutdown()
}

@Test func oversizedEmbeddedArtworkIsRejectedBeforeImageDecoding() async {
    let track = Track(
        url: URL(fileURLWithPath: "/tmp/song.mp3"), title: "Song",
        artworkData: Data(repeating: 0xFF, count: 9)
    )
    let cache = ArtworkCache(maximumSourceBytes: 8)
    #expect(await cache.data(for: track, fileURL: track.url) == nil)
}

@Test func reconnectPolicyHasFiniteExponentialBackoff() {
    let policy = ReconnectPolicy()
    #expect(policy.delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
    #expect(policy.delays.count == 4)
}

private func sampleResponse() -> SSDPResponse {
    SSDPResponse(
        usn: "uuid:pair::urn:schemas-upnp-org:device:MediaRenderer:1",
        location: URL(string: "http://192.168.0.105/device.xml")!,
        searchTarget: "urn:schemas-upnp-org:device:MediaRenderer:1",
        server: "Sony/1.0 UPnP/1.0",
        sourceAddress: "192.168.0.105"
    )
}

private func sampleRenderer() -> MediaRenderer {
    let base = URL(string: "http://192.168.0.105/device.xml")!
    return MediaRenderer(
        descriptionURL: base,
        deviceType: "urn:schemas-upnp-org:device:MediaRenderer:1",
        friendlyName: "Stereo Pair",
        manufacturer: "Sony Corporation",
        modelName: "SRS-HG1",
        modelNumber: nil,
        udn: "uuid:pair",
        services: [
            UPnPService(serviceType: "urn:schemas-upnp-org:service:AVTransport:1", serviceID: "av", controlURL: base, eventSubscriptionURL: nil, descriptionURL: nil),
            UPnPService(serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", serviceID: "rc", controlURL: base, eventSubscriptionURL: nil, descriptionURL: nil),
            UPnPService(serviceType: "urn:schemas-upnp-org:service:ConnectionManager:1", serviceID: "cm", controlURL: base, eventSubscriptionURL: nil, descriptionURL: nil),
        ]
    )
}

private func stereoResponse(address: String, id: String) -> SSDPResponse {
    SSDPResponse(
        usn: "uuid:\(id)::urn:schemas-upnp-org:device:MediaRenderer:1",
        location: URL(string: "http://\(address)/device.xml")!,
        searchTarget: "urn:schemas-upnp-org:device:MediaRenderer:1",
        server: "Sony/1.0 UPnP/1.0",
        sourceAddress: address
    )
}

private func stereoRenderer(modelName: String, response: SSDPResponse) -> MediaRenderer {
    MediaRenderer(
        descriptionURL: response.location,
        deviceType: "urn:schemas-upnp-org:device:MediaRenderer:1",
        friendlyName: modelName,
        manufacturer: "Sony Corporation",
        modelName: modelName,
        modelNumber: nil,
        udn: response.usn.components(separatedBy: "::").first!,
        services: [
            UPnPService(serviceType: "urn:schemas-upnp-org:service:AVTransport:1", serviceID: "av", controlURL: response.location, eventSubscriptionURL: nil, descriptionURL: nil),
            UPnPService(serviceType: "urn:schemas-upnp-org:service:RenderingControl:1", serviceID: "rc", controlURL: response.location, eventSubscriptionURL: nil, descriptionURL: nil),
        ]
    )
}

private struct FakeDiscovery: RendererDiscovering {
    let responses: [SSDPResponse]
    func discover() async throws -> [SSDPResponse] { responses }
}

private actor MutableDiscovery: RendererDiscovering {
    private var responses: [SSDPResponse]
    init(responses: [SSDPResponse]) { self.responses = responses }
    func discover() async throws -> [SSDPResponse] { responses }
    func setResponses(_ responses: [SSDPResponse]) { self.responses = responses }
}

private actor FlakyDiscovery: RendererDiscovering {
    let response: SSDPResponse
    let failuresBeforeSuccess: Int
    private(set) var attemptCount = 0

    init(response: SSDPResponse, failuresBeforeSuccess: Int) {
        self.response = response
        self.failuresBeforeSuccess = failuresBeforeSuccess
    }

    func discover() async throws -> [SSDPResponse] {
        attemptCount += 1
        if attemptCount <= failuresBeforeSuccess {
            throw HomeStereoError.serverFailure("No route to host")
        }
        return [response]
    }
}

private struct FakeDescriptions: DeviceDescriptionLoading {
    let renderer: MediaRenderer
    func load(from url: URL) async throws -> MediaRenderer { renderer }
}

private struct StereoDescriptions: DeviceDescriptionLoading {
    let renderers: [URL: MediaRenderer]
    func load(from url: URL) async throws -> MediaRenderer {
        guard let renderer = renderers[url] else { throw HomeStereoError.invalidDeviceDescription }
        return renderer
    }
}

private struct FailingDescriptions: DeviceDescriptionLoading {
    func load(from url: URL) async throws -> MediaRenderer {
        throw HomeStereoError.invalidDeviceDescription
    }
}

@MainActor
private final class FakeFileSelection: MediaFileSelecting {
    let url: URL?
    init(url: URL? = nil) { self.url = url }
    func chooseFile() -> URL? { url }
    func beginAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}

private final class FakeServer: MediaServerSession, @unchecked Sendable {
    let trackURL = URL(string: "http://192.168.0.35:8765/tracks/id?token=secret")!
    let mimeType = "audio/mpeg"
    func stop() {}
}

private final class CountingStereoPreparer: StereoMediaPreparing, @unchecked Sendable {
    private let lock = NSLock()
    private let root: URL
    private var count = 0
    var preparationCount: Int { lock.withLock { count } }

    init(root: URL) { self.root = root }

    func prepare(fileURL: URL, options: StereoPreparationOptions) async throws -> StereoMediaFiles {
        let current = lock.withLock { count += 1; return count }
        try await Task.sleep(for: .milliseconds(20))
        let directory = root.appendingPathComponent("prepared-\(current)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let left = directory.appendingPathComponent("left.wav")
        let right = directory.appendingPathComponent("right.wav")
        try Data("left".utf8).write(to: left)
        try Data("right".utf8).write(to: right)
        return StereoMediaFiles(leftURL: left, rightURL: right, sourceSampleRate: 48_000)
    }

    func prepareSynchronizationCheck(options: StereoPreparationOptions) async throws -> StereoMediaFiles {
        try await prepare(fileURL: root, options: options)
    }

    func remove(_ files: StereoMediaFiles) {
        try? FileManager.default.removeItem(at: files.leftURL.deletingLastPathComponent())
    }
}

@MainActor
private final class FakeLocalAudioPlayer: LocalAudioPlaying {
    var onPlaybackEnded: (@MainActor () -> Void)?
    var onPlaybackFailure: (@MainActor (String) -> Void)?
    var loadedURL: URL?
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var playCount = 0
    var pauseCount = 0
    var amplitude: Float = 1
    func setAmplitude(_ value: Float) { amplitude = value }

    func load(fileURL: URL) throws { loadedURL = fileURL; position = 0 }
    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func stop() { position = 0 }
    func seek(to position: TimeInterval) { self.position = position }
    func currentTime() -> TimeInterval { position }
    func itemDuration() -> TimeInterval { duration }
    func finish() { onPlaybackEnded?() }
}

private struct FakeServerFactory: MediaServerCreating {
    func start(fileURL: URL, rendererAddress: String) throws -> any MediaServerSession { FakeServer() }
}

private final class CapturingServerFactory: MediaServerCreating, @unchecked Sendable {
    var receivedFileURL: URL?
    func start(fileURL: URL, rendererAddress: String) throws -> any MediaServerSession {
        receivedFileURL = fileURL
        return FakeServer()
    }
}

private actor FakeController: RendererControlling {
    var actions: [String] = []
    var setVolumes: [UInt8] = []
    var transportState = "STOPPED"
    var transportStateSequence: [String] = []
    var failsTransport = false
    var failsPause = false
    var failsVolume = false
    var position: TimeInterval = 0
    var trackURI: String?
    var reportedDuration: TimeInterval = 120
    var transportDelay: Duration = .zero
    var positionDelay: Duration = .zero
    var commandDelay: Duration = .zero
    var concurrentCommands = 0
    var maximumConcurrentCommands = 0
    var transportReadCount = 0
    var positionReadCount = 0
    var volumeReadCount = 0
    var concurrentReads = 0
    var maximumConcurrentReads = 0
    func setURI(service: UPnPService, uri: URL, metadata: String) async throws {
        trackURI = uri.absoluteString
        try await command("SetAVTransportURI")
    }
    func play(service: UPnPService) async throws { try await command("Play") }
    func pause(service: UPnPService) async throws {
        try await command("Pause")
        if failsPause { throw NSError(domain: "pause", code: 701) }
    }
    func stop(service: UPnPService) async throws { try await command("Stop") }
    func seek(service: UPnPService, position: TimeInterval) async throws { try await command("Seek") }
    func transportInfo(service: UPnPService) async throws -> TransportInfo {
        transportReadCount += 1
        concurrentReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, concurrentReads)
        defer { concurrentReads -= 1 }
        let state = transportStateSequence.isEmpty ? transportState : transportStateSequence.removeFirst()
        try await Task.sleep(for: transportDelay)
        if failsTransport { throw NSError(domain: "network", code: -1) }
        return TransportInfo(state: state, status: "OK", speed: "1")
    }
    func positionInfo(service: UPnPService) async throws -> PositionInfo {
        positionReadCount += 1
        concurrentReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, concurrentReads)
        defer { concurrentReads -= 1 }
        try await Task.sleep(for: positionDelay)
        return PositionInfo(duration: reportedDuration, position: position, trackURI: trackURI)
    }
    func volume(service: UPnPService) async throws -> UInt8 {
        volumeReadCount += 1
        if failsVolume { throw NSError(domain: "network", code: -1) }
        return 20
    }
    func setVolume(service: UPnPService, volume: UInt8) async throws {
        setVolumes.append(volume)
        try await command("SetVolume")
    }
    func setTransportState(_ value: String) { transportState = value }
    func setTransportStateSequence(_ values: [String]) { transportStateSequence = values }
    func setFailsTransport(_ value: Bool) { failsTransport = value }
    func setFailsPause(_ value: Bool) { failsPause = value }
    func setFailsVolume(_ value: Bool) { failsVolume = value }
    func setPosition(_ value: TimeInterval) { position = value }
    func setPositionInfo(_ value: PositionInfo) {
        reportedDuration = value.duration ?? reportedDuration
        position = value.position ?? position
        trackURI = value.trackURI
    }
    func setTransportDelay(_ value: Duration) { transportDelay = value }
    func setPositionDelay(_ value: Duration) { positionDelay = value }
    func setCommandDelay(_ value: Duration) { commandDelay = value }
    func clearActions() { actions.removeAll() }
    func resetReadMetrics() {
        transportReadCount = 0
        positionReadCount = 0
        volumeReadCount = 0
        concurrentReads = 0
        maximumConcurrentReads = 0
    }

    private func command(_ action: String) async throws {
        concurrentCommands += 1
        maximumConcurrentCommands = max(maximumConcurrentCommands, concurrentCommands)
        defer { concurrentCommands -= 1 }
        actions.append(action)
        try await Task.sleep(for: commandDelay)
    }
}

@MainActor
private final class FakePlaybackActivityManager: PlaybackActivityManaging {
    private(set) var isActive = false
    func setPlaybackActive(_ active: Bool) { isActive = active }
}

private struct NoopScanner: LibraryScanning {
    func scan(folder: URL) async throws -> [Track] { [] }
}

@MainActor
private final class FakePlaylistFiles: PlaylistFileServicing {
    func chooseImportURL() -> URL? { nil }
    func chooseExportURL(defaultName: String) -> URL? { nil }
}

@MainActor
private final class QueueFolderAccess: FolderAccessServicing {
    let root: URL?
    init(root: URL? = nil) { self.root = root }
    func chooseFolder() -> URL? { nil }
    func makeBookmark(for folder: URL) throws -> Data { Data("fixture".utf8) }
    func resolveBookmark(_ data: Data) throws -> BookmarkResolution {
        guard let root else { throw UserFacingError.folderUnavailable }
        return BookmarkResolution(url: root)
    }
    func saveBookmark(for folder: URL) throws {}
    func restoreFolder() throws -> URL? { nil }
    func beginAccessing(_ folder: URL) -> Bool { true }
    func stopAccessing(_ folder: URL) {}
}

@MainActor
private final class NoopFolderChangeMonitor: FolderChangeMonitoring {
    func watch(_ folders: [UUID: URL], handler: @escaping @MainActor (UUID) -> Void) {}
    func stop() {}
}

@MainActor
private final class NoopSystemEventMonitor: SystemEventMonitoring {
    func start(_ handler: @escaping @MainActor (SystemPlaybackEvent) -> Void) {}
    func stop() {}
}

@MainActor
@Test(arguments: [0, 29, 30, 31], [MyMusicPlaybackEndReason.stop, .naturalEnd])
func macHistoryRequiresMoreThanThirtyListenedSeconds(seconds: Int, reason: MyMusicPlaybackEndReason) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("threshold.sqlite3"))
    let playback = RendererPlaybackStore(
        discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(),
        fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController()
    )
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(), repository: repository)
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    let listening = ListeningStore(repository: repository, library: library, queue: queue, myMusicRepository: repository)
    queue.onTrackStarted?(UUID(), 100, .library, .manual)
    queue.onTrackPosition?(0)
    queue.onTrackPosition?(100) // Seeking forward is not listening time.
    queue.onPlaybackStateChange?(.paused)
    queue.onTrackPosition?(105)
    queue.onPlaybackStateChange?(.playing)
    for position in 0...seconds { queue.onTrackPosition?(Double(position)) }
    await listening.flush()
    #expect(try await repository.loadPlaybackEvents().count == (seconds > 30 ? 1 : 0))
    queue.onTrackEnded?(reason)
    await listening.flush()
    try await Task.sleep(for: .milliseconds(50))
    #expect(listening.events.count == (seconds > 30 ? 1 : 0))
    let exported = try await repository.loadMyMusicPlaybackEvents()
    #expect(exported.count == (seconds > 30 ? 1 : 0))
    if seconds > 30 { #expect(exported.first?.playDuration == Double(seconds)) }
}

private struct QueueSeededGenerator: RandomNumberGenerator {
    var state: UInt64 = 42
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Test func queueSamplingDeduplicatesCapsAndKeepsSmallCollectionsInOrder() {
    let ids = (0..<300).map { _ in UUID() }
    var generator = QueueSeededGenerator()
    #expect(QueueCandidateSelection.select([ids[0], ids[1], ids[0]], preferences: [:], limit: 100, using: &generator) == Array(ids.prefix(2)))
    let selected = QueueCandidateSelection.select(ids + ids, preferences: [:], limit: 100, using: &generator)
    #expect(selected.count == 100)
    #expect(Set(selected).count == 100)
    #expect(Set(selected).isSubset(of: Set(ids)))
    #expect(QueueCandidateSelection.select(ids, preferences: [:], limit: 0, using: &generator).isEmpty)
}

@Test func queueSamplingFavorsGoodWithoutExcludingOtherTracks() {
    let good = UUID(), neutral = UUID(), bad = UUID()
    var generator = QueueSeededGenerator()
    var counts: [UUID: Int] = [:]
    for _ in 0..<3000 {
        let selected = QueueCandidateSelection.select([good, neutral, bad], preferences: [good: 10, bad: -10], limit: 1, using: &generator)
        counts[selected[0], default: 0] += 1
    }
    #expect(counts[good, default: 0] > counts[neutral, default: 0] * 5)
    #expect(counts[neutral, default: 0] > 100)
    #expect(counts[bad, default: 0] > 100)
}

@MainActor
@Test func queueCreationAndClearPreserveActivePlaybackAndPersistReferences() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = try SQLiteLibraryRepository(databaseURL: root.appendingPathComponent("create-queue.sqlite3"))
    let folder = LibraryFolder(displayName: "Fixture", path: root.path)
    try await repository.addFolder(folder, bookmarkData: Data("fixture".utf8))
    let tracks = (0..<120).map { index in
        try? Data().write(to: root.appendingPathComponent("\(index).mp3"))
        return Track(libraryFolderID: folder.id, relativePath: "\(index).mp3", url: root.appendingPathComponent("\(index).mp3"), title: "Track \(index)", duration: 120)
    }
    let missing = Track(libraryFolderID: folder.id, relativePath: "missing.mp3", url: root.appendingPathComponent("missing.mp3"), title: "Missing", scanState: .missing)
    try await repository.applySuccessfulScan(folderID: folder.id, tracks: tracks + [missing], scannedAt: .now)
    let player = FakeLocalAudioPlayer()
    let playback = RendererPlaybackStore(discovery: FakeDiscovery(responses: []), descriptions: FailingDescriptions(), fileSelection: FakeFileSelection(), serverFactory: FakeServerFactory(), controller: FakeController(), localPlayer: player, pollingInterval: .seconds(60))
    playback.selectThisMac()
    let library = LibraryStore(scanner: NoopScanner(), folderAccess: QueueFolderAccess(root: root), repository: repository, changeMonitor: NoopFolderChangeMonitor(), lifecycleMonitor: NoopSystemEventMonitor(), changeDebounce: .zero)
    await library.load()
    let queue = QueueStore(repository: repository, library: library, playback: playback)
    await queue.createFromCandidates(trackIDs: [tracks[0].id, tracks[1].id, missing.id, UUID(), tracks[0].id])
    #expect(queue.items.map(\.trackID) == [tracks[0].id, tracks[1].id])
    #expect(player.playCount == 0)
    await queue.play()
    let currentID = queue.items[0].id
    var ended = 0
    queue.onTrackEnded = { _ in ended += 1 }
    await queue.createFromCandidates(trackIDs: tracks.map(\.id))
    #expect(queue.items.count == 100)
    #expect(Set(queue.items.map(\.trackID)).count == 100)
    #expect(queue.items[0].id == currentID)
    #expect(player.playCount == 1)
    #expect(playback.playbackState == .playing)
    #expect(ended == 0)
    #expect(try await repository.loadQueue().items == queue.items)
    await queue.createFromCandidates(trackIDs: [tracks[0].id])
    #expect(queue.items.count == 1)
    #expect(queue.items[0].id == currentID)
    #expect(player.playCount == 1)
    queue.selectedItemIDs = Set(queue.items.map(\.id))
    await queue.clear()
    #expect(queue.items.isEmpty)
    #expect(queue.currentIndex == nil)
    #expect(queue.selectedItemIDs.isEmpty)
    #expect(playback.playbackState == .playing)
    #expect(ended == 0)
    #expect(try await repository.loadQueue().items.isEmpty)
    // A rebuilt queue after clearing an active track starts with its first candidate on completion.
    await queue.createFromCandidates(trackIDs: [tracks[1].id, tracks[2].id])
    #expect(queue.items.map(\.trackID) == [tracks[1].id, tracks[2].id])
    playback.shutdown(); library.pauseMonitoring()
}
