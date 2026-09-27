import Foundation
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif
import Observation

private struct StereoMediaCacheKey: Equatable {
    let path: String
    let fileSize: UInt64
    let modificationDate: Date?
    let options: StereoPreparationOptions

    init(fileURL: URL, options: StereoPreparationOptions) throws {
        let url = fileURL.standardizedFileURL
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        path = url.path
        fileSize = UInt64(max(0, values.fileSize ?? 0))
        modificationDate = values.contentModificationDate
        self.options = options
    }
}

private struct StereoMediaCacheEntry {
    let key: StereoMediaCacheKey
    let files: StereoMediaFiles
}

@MainActor
@Observable
public final class RendererPlaybackStore {
    public var destination: DLNASidebarDestination = .devices
    public private(set) var devices: [RendererDevice] = []
    public var selectedDeviceID: String?
    public private(set) var isThisMacSelected = false
    public private(set) var media: LocalMediaResource?
    public private(set) var selectedLibraryTrackID: UUID?
    public private(set) var playbackState: RendererPlaybackState = .stopped
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var volume: Double = 0
    public private(set) var stereoBalance: Double = 0
    public private(set) var stereoLeftVolume: Double = 0
    public private(set) var stereoRightVolume: Double = 0
    public private(set) var isDiscovering = false
    public private(set) var isBusy = false
    public private(set) var lastError: PlaybackDiagnostic?
    public private(set) var lastDiscoveryAt: Date?
    public private(set) var playbackGeneration = UUID()
    public private(set) var stereoRightDeviceID: String?
    public private(set) var stereoChannelsSwapped = false
    public private(set) var stereoDelayedChannel: StereoChannel = .left
    public private(set) var stereoDelayMilliseconds = StereoPreparationOptions.standard48kHzDelayMilliseconds
    public private(set) var stereoOutputQuality: StereoOutputQuality = .stable48kHz
    public private(set) var isStereoSynchronizationCheckActive = false
    public private(set) var lastStereoSourceSampleRate: Double?
    public private(set) var lastStereoAppliedDelayMilliseconds: Double?
    @ObservationIgnored public var onTrackFinished: (@MainActor () -> Void)?
    @ObservationIgnored public var onPositionChange: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored public var onCommunicationFailure: (@MainActor (PlaybackDiagnostic) -> Void)?
    @ObservationIgnored public var onPlaybackStateChange: (@MainActor (RendererPlaybackState) -> Void)?
    @ObservationIgnored public var onShutdown: (@MainActor () -> Void)?
    @ObservationIgnored public var onRendererTrackChanged: (@MainActor () -> Void)?
    @ObservationIgnored public var onPresentationChange: (@MainActor () -> Void)?

    @ObservationIgnored private let discovery: any RendererDiscovering
    @ObservationIgnored private let descriptions: any DeviceDescriptionLoading
    @ObservationIgnored private let fileSelection: any MediaFileSelecting
    @ObservationIgnored private let serverFactory: any MediaServerCreating
    @ObservationIgnored private let controller: any RendererControlling
    @ObservationIgnored private let secondaryController: any RendererControlling
    @ObservationIgnored private let localPlayer: any LocalAudioPlaying
    @ObservationIgnored private let stereoPreparer: any StereoMediaPreparing
    @ObservationIgnored private let activityManager: any PlaybackActivityManaging
    @ObservationIgnored private let pollingInterval: Duration
    @ObservationIgnored private let commandConfirmationInterval: Duration
    @ObservationIgnored private var activeServer: (any MediaServerSession)?
    @ObservationIgnored private var secondaryActiveServer: (any MediaServerSession)?
    @ObservationIgnored private var retiredServers: [any MediaServerSession] = []
    @ObservationIgnored private var preparedStereoFiles: [StereoMediaFiles] = []
    @ObservationIgnored private var stereoMediaCache: [StereoMediaCacheEntry] = []
    @ObservationIgnored private var stereoPreparationTask: Task<StereoMediaFiles, Error>?
    @ObservationIgnored private var stereoPreparationTaskKey: StereoMediaCacheKey?
    @ObservationIgnored private var activeScopedURL: URL?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private var completedGeneration: UUID?
    @ObservationIgnored private var lastConfirmedPosition: TimeInterval = 0
    @ObservationIgnored private var refreshSequence: UInt64 = 0
    @ObservationIgnored private var selectedDiscoveryMisses = 0
    @ObservationIgnored private var consecutiveTransportRefreshFailures = 0
    @ObservationIgnored private var diagnosticEvents: [PlaybackDiagnosticEvent] = []
    @ObservationIgnored private var localPlayerGeneration: UUID?

    public var selectedDevice: RendererDevice? { devices.first { $0.id == selectedDeviceID } }
    public var hasSelectedOutput: Bool { isThisMacSelected || selectedDevice != nil }
    public var canPlaySelectedOutput: Bool { isThisMacSelected || selectedDevice?.supportsAVTransport == true }
    public var canSeekSelectedOutput: Bool { isThisMacSelected || selectedDevice?.description?.avTransport != nil }
    public var canControlSelectedOutputVolume: Bool {
        !isThisMacSelected && selectedDevice?.description?.renderingControl != nil
    }
    public var isSonyStereoSelected: Bool { stereoRightDeviceID != nil }
    public var selectedOutputName: String {
        if isThisMacSelected { return "このMac" }
        if isSonyStereoSelected { return "Sonyステレオ" }
        return selectedDevice?.friendlyName ?? "スピーカーを選択"
    }
    public var isStereoStreaming: Bool {
        isSonyStereoSelected && activeServer != nil && secondaryActiveServer != nil && playbackState == .playing
    }
    public var stereoDelay44_1Milliseconds: Double {
        StereoPreparationOptions.calibrated44_1kHzDelay(for48kHzBase: stereoDelayMilliseconds)
    }
    public var stereoDelayPerRateStepMilliseconds: Double { stereoDelayMilliseconds }
    public var sonyStereoPair: StereoRendererPair? {
        guard let left = devices.first(where: { $0.modelName.localizedCaseInsensitiveCompare("SRS-HG10") == .orderedSame }),
              let right = devices.first(where: { $0.modelName.localizedCaseInsensitiveCompare("SRS-HG1") == .orderedSame }),
              left.supportsAVTransport, right.supportsAVTransport else { return nil }
        return StereoRendererPair(left: left, right: right)
    }
    public var stereoTimingDescription: String {
        guard stereoDelay44_1Milliseconds > 0 || stereoDelayMilliseconds > 0 else {
            return "タイミング補正なし"
        }
        let delay44 = stereoDelay44_1Milliseconds.formatted(.number.precision(.fractionLength(0...1)))
        let delay48 = stereoDelayMilliseconds.formatted(.number.precision(.fractionLength(0)))
        return "\(stereoDelayedChannel.rawValue)を44.1kHz系 \(delay44)ms／48kHz系 \(delay48)ms遅延"
    }

    public init(
        discovery: any RendererDiscovering,
        descriptions: any DeviceDescriptionLoading,
        fileSelection: any MediaFileSelecting,
        serverFactory: any MediaServerCreating,
        controller: any RendererControlling,
        secondaryController: (any RendererControlling)? = nil,
        localPlayer: (any LocalAudioPlaying)? = nil,
        stereoPreparer: any StereoMediaPreparing = AVFoundationStereoMediaPreparer(),
        activityManager: any PlaybackActivityManaging = NoopPlaybackActivityManager(),
        pollingInterval: Duration = .seconds(1),
        commandConfirmationInterval: Duration = .milliseconds(250)
    ) {
        self.discovery = discovery
        self.descriptions = descriptions
        self.fileSelection = fileSelection
        self.serverFactory = serverFactory
        self.controller = controller
        self.secondaryController = secondaryController ?? controller
        self.localPlayer = localPlayer ?? SystemAudioPlayer()
        self.stereoPreparer = stereoPreparer
        self.activityManager = activityManager
        self.pollingInterval = pollingInterval
        self.commandConfirmationInterval = commandConfirmationInterval
        self.localPlayer.onPlaybackEnded = { [weak self] in self?.localPlaybackEnded() }
        self.localPlayer.onPlaybackFailure = { [weak self] message in self?.localPlaybackFailed(message) }
    }

    public func discoverRenderers() async {
        isDiscovering = true
        lastError = nil
        do {
            let responses = try await discoverWithRetry()
            let previousDevices = devices
            var loaded: [RendererDevice] = []
            for response in responses {
                do {
                    let description = try await descriptions.load(from: response.location)
                    guard description.deviceType.contains("MediaRenderer") else { continue }
                    loaded.append(RendererDevice(discovery: response, description: description))
                } catch {
                    guard response.searchTarget.localizedCaseInsensitiveContains("urn:schemas-upnp-org:device:MediaRenderer:") else {
                        continue
                    }
                    let unresolved = RendererDevice(
                        discovery: response, descriptionError: error.localizedDescription
                    )
                    if let previous = previousDevices.first(where: {
                        $0.id == unresolved.id
                            && $0.discovery.sourceAddress == response.sourceAddress
                            && $0.description != nil
                    }) {
                        loaded.append(RendererDevice(
                            discovery: response,
                            description: previous.description,
                            descriptionError: error.localizedDescription
                        ))
                    } else {
                        loaded.append(unresolved)
                    }
                }
            }
            let discovered = deduplicateByStableIdentity(loaded)
            lastDiscoveryAt = .now
            let requiredIDs = [selectedDeviceID, stereoRightDeviceID].compactMap { $0 }
            let missingSelectedDevice = requiredIDs.contains { id in
                !discovered.contains(where: { $0.id == id })
            }
            if missingSelectedDevice {
                selectedDiscoveryMisses += 1
                if selectedDiscoveryMisses < 3 {
                    let retained = previousDevices.filter { requiredIDs.contains($0.id) }
                    devices = orderedDevices(deduplicateByStableIdentity(discovered + retained))
                    appendDiagnostic(
                        action: "SSDP M-SEARCH",
                        outcome: "selected-renderer-transient-miss-\(selectedDiscoveryMisses)"
                    )
                } else {
                    devices = orderedDevices(discovered)
                    rendererBecameUnavailable()
                }
            } else {
                selectedDiscoveryMisses = 0
                devices = orderedDevices(discovered)
            }
        } catch {
            if selectedDevice != nil {
                appendDiagnostic(action: "SSDP M-SEARCH", outcome: "transient-failure")
            } else {
                record(error, action: "SSDP M-SEARCH")
            }
        }
        isDiscovering = false
    }

    private func discoverWithRetry() async throws -> [SSDPResponse] {
        var lastDiscoveryError: Error?
        for attempt in 0..<3 {
            do {
                return try await discovery.discover()
            } catch {
                lastDiscoveryError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(400))
                }
            }
        }
        throw lastDiscoveryError ?? HomeStereoError.serverFailure("スピーカー検索に失敗しました。")
    }

    public func selectDevice(_ id: String?) {
        if isThisMacSelected, id == nil { return }
        guard id != selectedDeviceID || isSonyStereoSelected || isThisMacSelected else { return }
        beginPlaybackGeneration()
        localPlayer.stop()
        isThisMacSelected = false
        selectedDeviceID = id
        stereoRightDeviceID = nil
        selectedDiscoveryMisses = 0
        consecutiveTransportRefreshFailures = 0
        devices = orderedDevices(devices)
        stopServing()
        setPlaybackState(.stopped)
        elapsed = 0
        duration = 0
        lastError = nil
        let selectionGeneration = playbackGeneration
        Task { [weak self] in
            guard let self else { return }
            await self.refreshState()
            guard self.playbackGeneration == selectionGeneration, self.selectedDeviceID == id else { return }
            self.startPolling()
        }
    }

    public func selectThisMac() {
        guard !isThisMacSelected else { return }
        beginPlaybackGeneration()
        stopServing()
        localPlayer.stop()
        isThisMacSelected = true
        selectedDeviceID = nil
        stereoRightDeviceID = nil
        selectedDiscoveryMisses = 0
        consecutiveTransportRefreshFailures = 0
        setPlaybackState(.stopped)
        elapsed = 0
        lastError = nil
        onPresentationChange?()
    }

    public func selectSonyStereo() {
        guard let pair = sonyStereoPair else {
            lastError = PlaybackDiagnostic(action: "Sonyステレオ", details: "SRS-HG1とSRS-HG10の両方を検出してから選択してください。")
            return
        }
        beginPlaybackGeneration()
        stopServing()
        localPlayer.stop()
        isThisMacSelected = false
        selectedDeviceID = pair.left.id
        stereoRightDeviceID = pair.right.id
        selectedDiscoveryMisses = 0
        consecutiveTransportRefreshFailures = 0
        devices = orderedDevices(devices)
        setPlaybackState(.stopped)
        elapsed = 0
        duration = 0
        lastError = nil
        onPresentationChange?()
        Task { [weak self] in
            await self?.refreshState()
            self?.startPolling()
        }
        scheduleStereoPreparation()
    }

    public func clearSonyStereo() {
        guard isSonyStereoSelected else { return }
        beginPlaybackGeneration()
        stopServing()
        stereoRightDeviceID = nil
        cancelStereoPreparation()
        selectedDiscoveryMisses = 0
        setPlaybackState(.stopped)
        elapsed = 0
        lastError = nil
        onPresentationChange?()
    }

    public func setStereoChannelsSwapped(_ swapped: Bool) {
        guard stereoChannelsSwapped != swapped else { return }
        guard playbackState != .playing else {
            lastError = PlaybackDiagnostic(action: "Sonyステレオ", details: "停止してからL/Rを入れ替えてください。")
            return
        }
        stereoChannelsSwapped = swapped
        invalidateStereoRendering()
    }

    public func setStereoDelayedChannel(_ channel: StereoChannel) {
        guard stereoDelayedChannel != channel else { return }
        guard playbackState != .playing else {
            lastError = PlaybackDiagnostic(action: "Sonyステレオ", details: "停止してからタイミングを変更してください。")
            return
        }
        stereoDelayedChannel = channel
        invalidateStereoRendering()
    }

    public func setStereoDelayMilliseconds(_ milliseconds: Double) {
        let clamped = min(5_000, max(0, milliseconds.rounded()))
        guard stereoDelayMilliseconds != clamped else { return }
        guard playbackState != .playing else {
            lastError = PlaybackDiagnostic(action: "Sonyステレオ", details: "停止してからタイミングを変更してください。")
            return
        }
        stereoDelayMilliseconds = clamped
        invalidateStereoRendering()
    }

    public func setStereoOutputQuality(_ quality: StereoOutputQuality) {
        guard stereoOutputQuality != quality else { return }
        guard playbackState != .playing else {
            lastError = PlaybackDiagnostic(action: "Sonyステレオ", details: "停止してから出力品質を変更してください。")
            return
        }
        stereoOutputQuality = quality
        invalidateStereoRendering()
    }

    public func chooseFile() {
        guard let url = fileSelection.chooseFile() else { return }
        do {
            let resource = try LocalMediaResource(fileURL: url)
            beginPlaybackGeneration()
            retireActiveServer()
            localPlayer.stop()
            stopSecurityScope()
            activeScopedURL = fileSelection.beginAccessing(url) ? url : nil
            media = resource
            selectedLibraryTrackID = nil
            setPlaybackState(.stopped)
            elapsed = 0
            duration = 0
            lastError = nil
            onPresentationChange?()
            scheduleStereoPreparation()
        } catch { record(error, action: "ファイル選択") }
    }

    @discardableResult
    public func selectLibraryFile(_ url: URL, expectedDuration: TimeInterval? = nil, trackID: UUID? = nil) -> Bool {
        do {
            let resource = try LocalMediaResource(fileURL: url)
            beginPlaybackGeneration()
            retireActiveServer()
            localPlayer.stop()
            stopSecurityScope()
            media = resource
            selectedLibraryTrackID = trackID
            setPlaybackState(.stopped)
            elapsed = 0
            duration = expectedDuration ?? 0
            lastError = nil
            onPresentationChange?()
            scheduleStereoPreparation()
            return true
        } catch {
            record(error, action: "Libraryから再生")
            return false
        }
    }

    public func togglePlayback() async { playbackState == .playing ? await pause() : await play() }

    public func prewarmStereoMedia(fileURL: URL) async {
        guard isSonyStereoSelected else { return }
        do { _ = try await preparedStereoMedia(fileURL: fileURL, options: stereoPreparationOptions) }
        catch is CancellationError { }
        catch { /* Playback surfaces the same preparation error if this track is selected. */ }
    }

    public func play() async {
        await serializeCommand { [weak self] in
            guard let self else { return }
            if self.isThisMacSelected {
                guard let media = self.media else {
                    self.lastError = PlaybackDiagnostic(action: "Play", details: "音源ファイルを選択してください。")
                    return
                }
                await self.perform(action: "このMacで再生") {
                    if self.localPlayerGeneration != self.playbackGeneration {
                        try self.localPlayer.load(fileURL: media.fileURL)
                        self.localPlayerGeneration = self.playbackGeneration
                        let localDuration = self.localPlayer.itemDuration()
                        if localDuration > 0 { self.duration = localDuration }
                    }
                    self.localPlayer.play()
                    self.setPlaybackState(.playing)
                    self.startPolling()
                }
                return
            }
            guard let context = self.playbackContext() else { return }
            await self.perform(action: "Play") {
                if let pair = self.activeStereoPair() {
                    if self.isStereoSynchronizationCheckActive { self.stopServing() }
                    if self.activeServer == nil || self.secondaryActiveServer == nil {
                        let options = self.stereoPreparationOptions
                        let files = try await self.preparedStereoMedia(
                            fileURL: context.media.fileURL, options: options
                        )
                        self.lastStereoSourceSampleRate = files.sourceSampleRate
                        self.lastStereoAppliedDelayMilliseconds = files.appliedDelayMilliseconds
                        let serverFactory = self.serverFactory
                        let leftAddress = pair.left.discovery.sourceAddress
                        let rightAddress = pair.right.discovery.sourceAddress
                        let servers = try await Task.detached(priority: .userInitiated) {
                            try serverFactory.startStereoPair(
                                leftFileURL: files.leftURL,
                                leftRendererAddress: leftAddress,
                                rightFileURL: files.rightURL,
                                rightRendererAddress: rightAddress
                            )
                        }.value
                        let leftServer = servers.left
                        let rightServer = servers.right
                        self.activeServer = leftServer
                        self.secondaryActiveServer = rightServer
                        let leftMetadata = SOAPRequestBuilder.didlLiteMetadata(
                            resourceURL: leftServer.trackURL, mimeType: leftServer.mimeType, title: context.media.title
                        )
                        let rightMetadata = SOAPRequestBuilder.didlLiteMetadata(
                            resourceURL: rightServer.trackURL, mimeType: rightServer.mimeType, title: context.media.title
                        )
                        try await self.warmStereoConnections(
                            leftTransport: context.transport,
                            rightTransport: pair.rightTransport
                        )
                        async let setLeft: Void = self.controller.setURI(
                            service: context.transport, uri: leftServer.trackURL, metadata: leftMetadata
                        )
                        async let setRight: Void = self.secondaryController.setURI(
                            service: pair.rightTransport, uri: rightServer.trackURL, metadata: rightMetadata
                        )
                        _ = try await (setLeft, setRight)
                        try await self.waitUntilStereoPrepared(
                            leftTransport: context.transport,
                            leftURI: leftServer.trackURL,
                            rightTransport: pair.rightTransport,
                            rightURI: rightServer.trackURL
                        )
                    }
                    try await self.warmStereoConnections(
                        leftTransport: context.transport,
                        rightTransport: pair.rightTransport
                    )
                    async let playLeft: Void = self.controller.play(service: context.transport)
                    async let playRight: Void = self.secondaryController.play(service: pair.rightTransport)
                    _ = try await (playLeft, playRight)
                } else if self.activeServer == nil {
                    let serverFactory = self.serverFactory
                    let fileURL = context.media.fileURL
                    let rendererAddress = context.device.discovery.sourceAddress
                    let server = try await Task.detached(priority: .userInitiated) {
                        try serverFactory.start(fileURL: fileURL, rendererAddress: rendererAddress)
                    }.value
                    self.activeServer = server
                    let metadata = SOAPRequestBuilder.didlLiteMetadata(resourceURL: server.trackURL, mimeType: server.mimeType, title: context.media.title)
                    try await self.controller.setURI(service: context.transport, uri: server.trackURL, metadata: metadata)
                }
                if !self.isSonyStereoSelected {
                    try await self.controller.play(service: context.transport)
                }
                self.setPlaybackState(.playing)
                self.startPolling()
            }
        }
    }

    public func playStereoSynchronizationCheck() async {
        await serializeCommand { [weak self] in
            guard let self else { return }
            guard self.playbackState != .playing else {
                self.lastError = PlaybackDiagnostic(
                    action: "遅延チェック",
                    details: "再生中の曲を停止してから同期チェックを実行してください。"
                )
                return
            }
            guard let pair = self.activeStereoPair(),
                  let leftTransport = self.selectedDevice?.description?.avTransport else {
                self.lastError = PlaybackDiagnostic(
                    action: "遅延チェック",
                    details: "Sonyステレオを選択してから実行してください。"
                )
                return
            }

            self.beginPlaybackGeneration()
            self.stopServing()
            self.isStereoSynchronizationCheckActive = true
            self.elapsed = 0
            self.duration = StereoPreparationOptions.synchronizationCheckDuration
            self.onPresentationChange?()
            await self.perform(action: "遅延チェック") {
                let files = try await self.stereoPreparer.prepareSynchronizationCheck(
                    options: self.stereoPreparationOptions
                )
                self.lastStereoSourceSampleRate = files.sourceSampleRate
                self.lastStereoAppliedDelayMilliseconds = files.appliedDelayMilliseconds
                self.duration = StereoPreparationOptions.synchronizationCheckDuration
                    + files.appliedDelayMilliseconds / 1_000
                self.preparedStereoFiles.append(files)
                let serverFactory = self.serverFactory
                let servers = try await Task.detached(priority: .userInitiated) {
                    try serverFactory.startStereoPair(
                        leftFileURL: files.leftURL,
                        leftRendererAddress: pair.left.discovery.sourceAddress,
                        rightFileURL: files.rightURL,
                        rightRendererAddress: pair.right.discovery.sourceAddress
                    )
                }.value
                self.activeServer = servers.left
                self.secondaryActiveServer = servers.right
                let title = "HomeStereo 同期チェック"
                let leftMetadata = SOAPRequestBuilder.didlLiteMetadata(
                    resourceURL: servers.left.trackURL,
                    mimeType: servers.left.mimeType,
                    title: title
                )
                let rightMetadata = SOAPRequestBuilder.didlLiteMetadata(
                    resourceURL: servers.right.trackURL,
                    mimeType: servers.right.mimeType,
                    title: title
                )
                try await self.warmStereoConnections(
                    leftTransport: leftTransport,
                    rightTransport: pair.rightTransport
                )
                async let setLeft: Void = self.controller.setURI(
                    service: leftTransport,
                    uri: servers.left.trackURL,
                    metadata: leftMetadata
                )
                async let setRight: Void = self.secondaryController.setURI(
                    service: pair.rightTransport,
                    uri: servers.right.trackURL,
                    metadata: rightMetadata
                )
                _ = try await (setLeft, setRight)
                try await self.waitUntilStereoPrepared(
                    leftTransport: leftTransport,
                    leftURI: servers.left.trackURL,
                    rightTransport: pair.rightTransport,
                    rightURI: servers.right.trackURL
                )
                async let playLeft: Void = self.controller.play(service: leftTransport)
                async let playRight: Void = self.secondaryController.play(service: pair.rightTransport)
                _ = try await (playLeft, playRight)
                self.setPlaybackState(.playing)
                self.startPolling()
            }
            if self.playbackState != .playing {
                self.stopServing()
                self.onPresentationChange?()
            }
        }
    }

    /// Tears down both stereo media sessions and assigns fresh HTTP URLs to the
    /// renderers. Stereo calibration and the selected track are intentionally
    /// retained. If playback was active, the track restarts from the beginning.
    public func resetStereoConnection() async {
        var shouldRestartPlayback = false
        await serializeCommand { [weak self] in
            guard let self else { return }
            guard !self.isStereoSynchronizationCheckActive else {
                self.lastError = PlaybackDiagnostic(
                    action: "ステレオ通信リセット",
                    details: "遅延チェックが終わってから通信をリセットしてください。"
                )
                return
            }
            guard let leftTransport = self.selectedDevice?.description?.avTransport,
                  let pair = self.activeStereoPair() else {
                self.lastError = PlaybackDiagnostic(
                    action: "ステレオ通信リセット",
                    details: "Sonyステレオを選択してから実行してください。"
                )
                return
            }

            shouldRestartPlayback = self.playbackState == .playing && self.media != nil
            self.isBusy = true
            self.beginPlaybackGeneration()

            do {
                async let leftStop: Void = self.controller.stop(service: leftTransport)
                async let rightStop: Void = self.secondaryController.stop(service: pair.rightTransport)
                _ = try await (leftStop, rightStop)
                self.appendDiagnostic(action: "ステレオ通信リセット", outcome: "renderer-stop-success")
            } catch {
                // This action is itself the recovery path. Even if a renderer no
                // longer answers Stop, discard both local sessions and reconnect.
                self.appendDiagnostic(action: "ステレオ通信リセット", outcome: "renderer-stop-failed")
            }

            self.stopServing()
            self.setPlaybackState(.stopped)
            self.elapsed = 0
            self.lastConfirmedPosition = 0
            self.lastError = nil
            self.isBusy = false
            self.onPositionChange?(0)
            self.onPresentationChange?()
            self.appendDiagnostic(action: "ステレオ通信リセット", outcome: "local-sessions-cleared")
        }

        if shouldRestartPlayback {
            await play()
        }
    }

    public func pause() async {
        await serializeCommand { [weak self] in
            guard let self else { return }
            if self.isThisMacSelected {
                self.localPlayer.pause()
                self.setPlaybackState(.paused)
                self.elapsed = self.localPlayer.currentTime()
                self.onPositionChange?(self.elapsed)
                return
            }
            guard let transport = self.selectedDevice?.description?.avTransport else { return }
            if self.isSonyStereoSelected {
                await self.stopStereo(action: "Pause→Stop")
                return
            }
            await self.perform(action: "Pause") {
                var commandError: Error?
                do {
                    try await self.controller.pause(service: transport)
                } catch {
                    commandError = error
                }
                var lastState = "UNKNOWN"
                var statusError: Error?
                for attempt in 0..<5 {
                    do {
                        lastState = try await self.controller.transportInfo(service: transport).state
                        if lastState == RendererPlaybackState.paused.rawValue { break }
                    } catch {
                        statusError = error
                    }
                    if attempt == 1 {
                        do { try await self.controller.pause(service: transport) }
                        catch { commandError = commandError ?? error }
                    }
                    if attempt < 4 { try await Task.sleep(for: self.commandConfirmationInterval) }
                }
                if lastState != RendererPlaybackState.paused.rawValue {
                    var stopError: Error?
                    do {
                        try await self.controller.stop(service: transport)
                    } catch {
                        stopError = error
                    }
                    for attempt in 0..<5 {
                        do {
                            lastState = try await self.controller.transportInfo(service: transport).state
                            if lastState == RendererPlaybackState.stopped.rawValue { break }
                        } catch {
                            statusError = error
                        }
                        if attempt == 1 {
                            do { try await self.controller.stop(service: transport) }
                            catch { stopError = stopError ?? error }
                        }
                        if attempt < 4 { try await Task.sleep(for: self.commandConfirmationInterval) }
                    }
                    guard lastState == RendererPlaybackState.stopped.rawValue else {
                        if let statusError { throw statusError }
                        if let stopError { throw stopError }
                        if let commandError { throw commandError }
                        throw PauseConfirmationError(state: lastState)
                    }
                    self.setPlaybackState(.stopped)
                    self.elapsed = 0
                    self.lastConfirmedPosition = 0
                    return
                }
                self.setPlaybackState(.paused)
            }
        }
    }

    public func stop() async {
        await serializeCommand { [weak self] in
            guard let self else { return }
            if self.isThisMacSelected {
                self.localPlayer.stop()
                self.setPlaybackState(.stopped)
                self.elapsed = 0
                self.lastConfirmedPosition = 0
                self.onPositionChange?(0)
                return
            }
            guard let transport = self.selectedDevice?.description?.avTransport else { return }
            if self.isSonyStereoSelected {
                await self.stopStereo(action: "Stop")
                return
            }
            await self.perform(action: "Stop") {
                var commandError: Error?
                do {
                    try await self.controller.stop(service: transport)
                } catch {
                    commandError = error
                }
                var lastState = "UNKNOWN"
                var statusError: Error?
                for attempt in 0..<5 {
                    do {
                        lastState = try await self.controller.transportInfo(service: transport).state
                        if lastState == RendererPlaybackState.stopped.rawValue { break }
                    } catch {
                        statusError = error
                    }
                    if attempt == 1 {
                        do { try await self.controller.stop(service: transport) }
                        catch { commandError = commandError ?? error }
                    }
                    if attempt < 4 { try await Task.sleep(for: self.commandConfirmationInterval) }
                }
                guard lastState == RendererPlaybackState.stopped.rawValue else {
                    if let statusError { throw statusError }
                    if let commandError { throw commandError }
                    throw StopConfirmationError(state: lastState)
                }
                self.setPlaybackState(.stopped)
                self.elapsed = 0
                self.lastConfirmedPosition = 0
            }
        }
    }

    public func seek(to position: TimeInterval) async {
        await serializeCommand { [weak self] in
            guard let self else { return }
            if self.isThisMacSelected {
                self.localPlayer.seek(to: position)
                self.elapsed = max(0, position)
                self.lastConfirmedPosition = self.elapsed
                self.onPositionChange?(self.elapsed)
                return
            }
            guard let transport = self.selectedDevice?.description?.avTransport else { return }
            await self.perform(action: "Seek") {
                if let pair = self.activeStereoPair() {
                    async let left: Void = self.controller.seek(service: transport, position: position)
                    async let right: Void = self.secondaryController.seek(service: pair.rightTransport, position: position)
                    _ = try await (left, right)
                } else {
                    try await self.controller.seek(service: transport, position: position)
                }
                self.elapsed = position
                self.lastConfirmedPosition = position
            }
        }
    }

    public func setVolume(_ value: Double) async {
        guard let service = selectedDevice?.description?.renderingControl else { return }
        refreshSequence &+= 1
        let clamped = min(100, max(0, value)).rounded()
        await perform(action: "SetVolume") {
            if let pair = self.activeStereoPair(), let rightService = pair.right.description?.renderingControl {
                let levels = Self.stereoVolumes(master: clamped, balance: self.stereoBalance)
                async let left: Void = self.controller.setVolume(service: service, volume: levels.left)
                async let right: Void = self.secondaryController.setVolume(service: rightService, volume: levels.right)
                _ = try await (left, right)
                self.stereoLeftVolume = Double(levels.left)
                self.stereoRightVolume = Double(levels.right)
            } else {
                try await self.controller.setVolume(service: service, volume: UInt8(clamped))
            }
            self.volume = clamped
        }
    }

    public func setStereoBalance(_ value: Double) async {
        guard let leftService = selectedDevice?.description?.renderingControl,
              let pair = activeStereoPair(),
              let rightService = pair.right.description?.renderingControl else { return }
        refreshSequence &+= 1
        let clamped = min(1, max(-1, value))
        let levels = Self.stereoVolumes(master: volume, balance: clamped)
        await perform(action: "SetStereoBalance") {
            async let left: Void = self.controller.setVolume(service: leftService, volume: levels.left)
            async let right: Void = self.secondaryController.setVolume(service: rightService, volume: levels.right)
            _ = try await (left, right)
            self.stereoBalance = clamped
            self.stereoLeftVolume = Double(levels.left)
            self.stereoRightVolume = Double(levels.right)
        }
    }

    nonisolated public static func stereoVolumes(master: Double, balance: Double) -> (left: UInt8, right: UInt8) {
        let master = min(100, max(0, master))
        let balance = min(1, max(-1, balance))
        let leftScale = balance > 0 ? 1 - balance : 1
        let rightScale = balance < 0 ? 1 + balance : 1
        return (
            UInt8((master * leftScale).rounded()),
            UInt8((master * rightScale).rounded())
        )
    }

    public func refreshState() async {
        guard !isBusy else { return }
        if isThisMacSelected {
            guard localPlayerGeneration == playbackGeneration else { return }
            elapsed = localPlayer.currentTime()
            let localDuration = localPlayer.itemDuration()
            if localDuration > 0 { duration = localDuration }
            lastConfirmedPosition = elapsed
            onPositionChange?(elapsed)
            return
        }
        guard let description = selectedDevice?.description else { return }
        refreshSequence &+= 1
        let sequence = refreshSequence
        let generation = playbackGeneration
        var observedGeneration = generation
        var transportFailed = false
        if let transport = description.avTransport {
            do {
                let previousState = playbackState
                async let infoRequest = controller.transportInfo(service: transport)
                async let positionRequest = controller.positionInfo(service: transport)
                let (info, position) = try await (infoRequest, positionRequest)
                guard generation == playbackGeneration, sequence == refreshSequence else { return }
                let reportedState = RendererPlaybackState(rawValue: info.state) ?? .unknown
                consecutiveTransportRefreshFailures = 0
                if rendererURIChanged(position.trackURI) {
                    playbackGeneration = UUID()
                    observedGeneration = playbackGeneration
                    completedGeneration = observedGeneration
                    retireActiveServer()
                    media = nil
                    selectedLibraryTrackID = nil
                    onPresentationChange?()
                    onRendererTrackChanged?()
                    appendDiagnostic(action: "RendererTrackChanged", outcome: "external-change")
                }
                let priorPosition = lastConfirmedPosition
                elapsed = position.position ?? elapsed
                duration = position.duration ?? duration
                lastConfirmedPosition = max(0, elapsed)
                setPlaybackState(reportedState)
                onPositionChange?(elapsed)
                if isConfirmedCompletion(
                    generation: observedGeneration,
                    previousState: previousState,
                    reportedState: reportedState,
                    priorPosition: priorPosition,
                    position: position
                ) {
                    completedGeneration = observedGeneration
                    if isStereoSynchronizationCheckActive {
                        stopServing()
                        onPresentationChange?()
                    } else {
                        onTrackFinished?()
                    }
                }
            } catch {
                guard observedGeneration == playbackGeneration, sequence == refreshSequence else { return }
                transportFailed = true
                consecutiveTransportRefreshFailures += 1
                if consecutiveTransportRefreshFailures >= 3 {
                    setPlaybackState(.unknown)
                    if consecutiveTransportRefreshFailures == 3 {
                        record(error, action: "GetTransportInfo / GetPositionInfo")
                    }
                } else {
                    appendDiagnostic(
                        action: "GetTransportInfo / GetPositionInfo",
                        outcome: "transient-read-failure"
                    )
                }
            }
        }
        let shouldRefreshVolume = sequence == 1 || sequence.isMultiple(of: 5)
        if shouldRefreshVolume, let rendering = description.renderingControl {
            do {
                if let pair = activeStereoPair(), let rightRendering = pair.right.description?.renderingControl {
                    async let left = controller.volume(service: rendering)
                    async let right = secondaryController.volume(service: rightRendering)
                    let reported = try await (left, right)
                    guard generation == playbackGeneration, sequence == refreshSequence else { return }
                    applyStereoVolumes(left: reported.0, right: reported.1)
                } else {
                    let reportedVolume = try await controller.volume(service: rendering)
                    guard generation == playbackGeneration, sequence == refreshSequence else { return }
                    volume = Double(reportedVolume)
                }
            }
            catch {
                guard observedGeneration == playbackGeneration, sequence == refreshSequence else { return }
                appendDiagnostic(action: "GetVolume", outcome: "read-failure")
            }
        }
        if !transportFailed, observedGeneration == playbackGeneration, sequence == refreshSequence {
            lastError = nil
        }
    }

    private func applyStereoVolumes(left: UInt8, right: UInt8) {
        let left = Double(left)
        let right = Double(right)
        let master = max(left, right)
        volume = master
        stereoLeftVolume = left
        stereoRightVolume = right
        guard master > 0 else {
            stereoBalance = 0
            return
        }
        if left > right {
            stereoBalance = -(1 - right / left)
        } else if right > left {
            stereoBalance = 1 - left / right
        } else {
            stereoBalance = 0
        }
    }

    public func dismissError() { lastError = nil }

    public func shutdown() {
        onShutdown?()
        pollingTask?.cancel()
        commandTail?.cancel()
        localPlayer.stop()
        stopServing()
        stopSecurityScope()
        activityManager.setPlaybackActive(false)
    }

    public func prepareForSystemInterruption() {
        if isThisMacSelected {
            pollingTask?.cancel()
            localPlayer.pause()
            elapsed = localPlayer.currentTime()
            onPositionChange?(elapsed)
            setPlaybackState(.paused)
            return
        }
        beginPlaybackGeneration()
        pollingTask?.cancel()
        stopServing()
        setPlaybackState(.unknown)
    }

    public func reconnect(udn: String?) async -> Bool {
        await discoverRenderers()
        guard let udn, let device = devices.first(where: { $0.description?.udn == udn }) else { return false }
        selectedDeviceID = device.id
        devices = orderedDevices(devices)
        await refreshState()
        startPolling()
        return playbackState != .unknown && lastError == nil
    }

    public func diagnosticReportData() throws -> Data {
        struct Report: Codable {
            let kind: String
            let generatedAt: Date
            let events: [PlaybackDiagnosticEvent]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Report(kind: "home-stereo-diagnostics", generatedAt: Date(), events: diagnosticEvents))
    }

    private func playbackContext() -> (device: RendererDevice, media: LocalMediaResource, transport: UPnPService)? {
        guard let device = selectedDevice else { lastError = PlaybackDiagnostic(action: "Play", details: "Rendererを選択してください。"); return nil }
        guard let transport = device.description?.avTransport else { lastError = PlaybackDiagnostic(action: "Play", details: "選択した機器はAVTransportを公開していません。"); return nil }
        guard let media else { lastError = PlaybackDiagnostic(action: "Play", details: "音源ファイルを選択してください。"); return nil }
        return (device, media, transport)
    }

    private func activeStereoPair() -> (left: RendererDevice, right: RendererDevice, rightTransport: UPnPService)? {
        guard let rightID = stereoRightDeviceID,
              let left = selectedDevice,
              let right = devices.first(where: { $0.id == rightID }),
              let rightTransport = right.description?.avTransport else { return nil }
        return (left, right, rightTransport)
    }

    private var stereoPreparationOptions: StereoPreparationOptions {
        StereoPreparationOptions(
            swapsChannels: stereoChannelsSwapped,
            delayedChannel: stereoDelayedChannel,
            delayMilliseconds: stereoDelayMilliseconds,
            outputQuality: stereoOutputQuality,
            automaticSampleRateDelay: true,
            delayPerRateStepMilliseconds: stereoDelayPerRateStepMilliseconds,
            delay44_1kHzMilliseconds: stereoDelay44_1Milliseconds
        )
    }

    private func stopStereo(action: String) async {
        guard let leftTransport = selectedDevice?.description?.avTransport,
              let pair = activeStereoPair() else { return }
        await perform(action: action) {
            async let leftStop: Void = self.controller.stop(service: leftTransport)
            async let rightStop: Void = self.secondaryController.stop(service: pair.rightTransport)
            _ = try await (leftStop, rightStop)

            var leftState = "UNKNOWN"
            var rightState = "UNKNOWN"
            for attempt in 0..<5 {
                async let leftInfo = self.controller.transportInfo(service: leftTransport)
                async let rightInfo = self.secondaryController.transportInfo(service: pair.rightTransport)
                let states = try await (leftInfo, rightInfo)
                leftState = states.0.state
                rightState = states.1.state
                if leftState == RendererPlaybackState.stopped.rawValue,
                   rightState == RendererPlaybackState.stopped.rawValue { break }
                if attempt == 1 {
                    async let retryLeft: Void = self.controller.stop(service: leftTransport)
                    async let retryRight: Void = self.secondaryController.stop(service: pair.rightTransport)
                    _ = try await (retryLeft, retryRight)
                }
                if attempt < 4 { try await Task.sleep(for: self.commandConfirmationInterval) }
            }
            guard leftState == RendererPlaybackState.stopped.rawValue,
                  rightState == RendererPlaybackState.stopped.rawValue else {
                throw StereoStopConfirmationError(leftState: leftState, rightState: rightState)
            }
            self.setPlaybackState(.stopped)
            if self.isStereoSynchronizationCheckActive { self.stopServing() }
            self.elapsed = 0
            self.lastConfirmedPosition = 0
        }
    }

    private func warmStereoConnections(leftTransport: UPnPService, rightTransport: UPnPService) async throws {
        async let left = controller.transportInfo(service: leftTransport)
        async let right = secondaryController.transportInfo(service: rightTransport)
        _ = try await (left, right)
    }

    private func waitUntilStereoPrepared(
        leftTransport: UPnPService,
        leftURI: URL,
        rightTransport: UPnPService,
        rightURI: URL
    ) async throws {
        var lastLeftURI: String?
        var lastRightURI: String?
        var lastLeftState = "UNKNOWN"
        var lastRightState = "UNKNOWN"
        var consecutiveReadyChecks = 0
        for attempt in 0..<20 {
            async let leftPosition = controller.positionInfo(service: leftTransport)
            async let rightPosition = secondaryController.positionInfo(service: rightTransport)
            async let leftTransportInfo = controller.transportInfo(service: leftTransport)
            async let rightTransportInfo = secondaryController.transportInfo(service: rightTransport)
            let values = try await (leftPosition, rightPosition, leftTransportInfo, rightTransportInfo)
            lastLeftURI = values.0.trackURI
            lastRightURI = values.1.trackURI
            lastLeftState = values.2.state
            lastRightState = values.3.state
            let leftReady = Self.isStereoRendererPrepared(
                reportedURI: lastLeftURI, expectedURI: leftURI, state: lastLeftState
            )
            let rightReady = Self.isStereoRendererPrepared(
                reportedURI: lastRightURI, expectedURI: rightURI, state: lastRightState
            )
            if leftReady && rightReady {
                consecutiveReadyChecks += 1
                if consecutiveReadyChecks >= 3 {
                    // Some Sony renderers enter PLAYING as soon as they start fetching the
                    // newly assigned URI. Treat that as prepared too, while still requiring
                    // both renderers to report the expected URI for three consecutive checks.
                    try await Task.sleep(for: .milliseconds(250))
                    return
                }
            } else {
                consecutiveReadyChecks = 0
            }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(100)) }
        }
        throw StereoPreparationConfirmationError(
            leftURI: lastLeftURI,
            rightURI: lastRightURI,
            leftState: lastLeftState,
            rightState: lastRightState
        )
    }

    static func isPreparedTransportState(_ state: String) -> Bool {
        state == RendererPlaybackState.stopped.rawValue
            || state == RendererPlaybackState.paused.rawValue
            || state == RendererPlaybackState.playing.rawValue
    }

    static func isStereoRendererPrepared(reportedURI: String?, expectedURI: URL, state: String) -> Bool {
        reportedURI == expectedURI.absoluteString && isPreparedTransportState(state)
    }

    private func invalidateStereoRendering() {
        beginPlaybackGeneration()
        retireActiveServer()
        setPlaybackState(.stopped)
        elapsed = 0
        lastConfirmedPosition = 0
        lastError = nil
        onPresentationChange?()
        scheduleStereoPreparation()
    }

    private func scheduleStereoPreparation() {
        guard isSonyStereoSelected, let media else { return }
        let options = stereoPreparationOptions
        Task(priority: .utility) { [weak self] in
            do { _ = try await self?.preparedStereoMedia(fileURL: media.fileURL, options: options) }
            catch is CancellationError { }
            catch { /* Play reports preparation failures when the user starts playback. */ }
        }
    }

    private func preparedStereoMedia(
        fileURL: URL, options: StereoPreparationOptions
    ) async throws -> StereoMediaFiles {
        let key = try StereoMediaCacheKey(fileURL: fileURL, options: options)
        if let cached = stereoMediaCache.last(where: { $0.key == key }),
           FileManager.default.fileExists(atPath: cached.files.leftURL.path),
           FileManager.default.fileExists(atPath: cached.files.rightURL.path) {
            return cached.files
        }
        if stereoPreparationTaskKey == key, let stereoPreparationTask {
            return try await stereoPreparationTask.value
        }

        cancelStereoPreparation()
        let preparer = stereoPreparer
        let task = Task(priority: .utility) {
            try Task.checkCancellation()
            return try await preparer.prepare(fileURL: fileURL, options: options)
        }
        stereoPreparationTask = task
        stereoPreparationTaskKey = key
        do {
            let files = try await task.value
            guard stereoPreparationTaskKey == key else {
                preparer.remove(files)
                throw CancellationError()
            }
            stereoPreparationTask = nil
            stereoPreparationTaskKey = nil
            preparedStereoFiles.append(files)
            stereoMediaCache.removeAll { $0.key == key }
            stereoMediaCache.append(StereoMediaCacheEntry(key: key, files: files))
            evictStereoMediaCacheIfNeeded()
            return files
        } catch {
            if stereoPreparationTaskKey == key {
                stereoPreparationTask = nil
                stereoPreparationTaskKey = nil
            }
            throw error
        }
    }

    private func evictStereoMediaCacheIfNeeded() {
        while stereoMediaCache.count > 2 {
            let evicted = stereoMediaCache.removeFirst().files
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                guard let self, !self.stereoMediaCache.contains(where: { $0.files == evicted }) else { return }
                self.stereoPreparer.remove(evicted)
                self.preparedStereoFiles.removeAll { $0 == evicted }
            }
        }
    }

    private func cancelStereoPreparation() {
        stereoPreparationTask?.cancel()
        stereoPreparationTask = nil
        stereoPreparationTaskKey = nil
    }

    private func perform(action: String, operation: () async throws -> Void) async {
        isBusy = true
        lastError = nil
        onPresentationChange?()
        do {
            try await operation()
            appendDiagnostic(action: action, outcome: "success")
        } catch { record(error, action: action) }
        isBusy = false
        onPresentationChange?()
    }

    private func serializeCommand(_ operation: @escaping @MainActor () async -> Void) async {
        let predecessor = commandTail
        let task = Task { @MainActor in
            await predecessor?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
        commandTail = task
        await task.value
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollingInterval ?? .seconds(1))
                guard let self, !Task.isCancelled else { return }
                await self.refreshState()
            }
        }
    }

    private func beginPlaybackGeneration() {
        playbackGeneration = UUID()
        localPlayerGeneration = nil
        refreshSequence &+= 1
        completedGeneration = nil
        lastConfirmedPosition = 0
        consecutiveTransportRefreshFailures = 0
        pollingTask?.cancel()
    }

    private func localPlaybackEnded() {
        guard isThisMacSelected,
              localPlayerGeneration == playbackGeneration,
              completedGeneration != playbackGeneration else { return }
        completedGeneration = playbackGeneration
        pollingTask?.cancel()
        elapsed = duration
        lastConfirmedPosition = elapsed
        setPlaybackState(.stopped)
        onPositionChange?(elapsed)
        onTrackFinished?()
    }

    private func localPlaybackFailed(_ message: String) {
        guard isThisMacSelected, localPlayerGeneration == playbackGeneration else { return }
        pollingTask?.cancel()
        setPlaybackState(.stopped)
        lastError = PlaybackDiagnostic(action: "このMacで再生", details: message)
        appendDiagnostic(action: "このMacで再生", outcome: "failure")
        onPresentationChange?()
    }

    private func rendererBecameUnavailable() {
        beginPlaybackGeneration()
        selectedDeviceID = nil
        stereoRightDeviceID = nil
        selectedDiscoveryMisses = 0
        stopServing()
        setPlaybackState(.unknown)
        let diagnostic = PlaybackDiagnostic(action: "SSDP M-SEARCH", details: "選択中のRendererが見つかりません。")
        lastError = diagnostic
        appendDiagnostic(action: diagnostic.action, outcome: "renderer-unavailable")
        onCommunicationFailure?(diagnostic)
    }

    private func isConfirmedCompletion(
        generation: UUID,
        previousState: RendererPlaybackState,
        reportedState: RendererPlaybackState,
        priorPosition: TimeInterval,
        position: PositionInfo
    ) -> Bool {
        guard completedGeneration != generation,
              reportedState == .stopped,
              previousState == .playing || previousState == .transitioning,
              duration > 0 else { return false }
        if let trackURI = position.trackURI, let activeURL = activeServer?.trackURL.absoluteString,
           trackURI != activeURL { return false }
        let endThreshold = max(0, duration - 3)
        return max(priorPosition, position.position ?? 0) >= endThreshold
    }

    private func rendererURIChanged(_ trackURI: String?) -> Bool {
        guard let activeURL = activeServer?.trackURL.absoluteString,
              let trackURI, !trackURI.isEmpty else { return false }
        return trackURI != activeURL
    }

    private func retireActiveServer() {
        let servers = [activeServer, secondaryActiveServer].compactMap { $0 }
        guard !servers.isEmpty else { return }
        activeServer = nil
        secondaryActiveServer = nil
        retiredServers.append(contentsOf: servers)
        for server in servers {
            let identity = ObjectIdentifier(server)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                guard let index = self.retiredServers.firstIndex(where: { ObjectIdentifier($0) == identity }) else { return }
                self.retiredServers.remove(at: index).stop()
            }
        }
    }

    private func stopServing() {
        cancelStereoPreparation()
        activeServer?.stop()
        activeServer = nil
        secondaryActiveServer?.stop()
        secondaryActiveServer = nil
        retiredServers.forEach { $0.stop() }
        retiredServers.removeAll()
        preparedStereoFiles.forEach { stereoPreparer.remove($0) }
        preparedStereoFiles.removeAll()
        stereoMediaCache.removeAll()
        isStereoSynchronizationCheckActive = false
    }
    private func setPlaybackState(_ state: RendererPlaybackState) {
        guard playbackState != state else { return }
        playbackState = state
        activityManager.setPlaybackActive(state == .playing)
        onPlaybackStateChange?(state)
    }
    private func stopSecurityScope() { if let activeScopedURL { fileSelection.stopAccessing(activeScopedURL) }; activeScopedURL = nil }

    private func record(_ error: Error, action: String) {
        if case let HomeStereoError.upnpFailure(failure) = error {
            lastError = PlaybackDiagnostic(action: failure.action, httpStatus: failure.httpStatus, upnpErrorCode: failure.errorCode, details: failure.errorDescription ?? error.localizedDescription)
        } else { lastError = PlaybackDiagnostic(action: action, details: error.localizedDescription) }
        if let lastError {
            appendDiagnostic(
                action: lastError.action,
                outcome: "failure",
                httpStatus: lastError.httpStatus,
                upnpErrorCode: lastError.upnpErrorCode
            )
            onCommunicationFailure?(lastError)
        }
    }

    private func appendDiagnostic(action: String, outcome: String, httpStatus: Int? = nil, upnpErrorCode: Int? = nil) {
        diagnosticEvents.append(PlaybackDiagnosticEvent(
            generationID: playbackGeneration,
            action: action,
            outcome: outcome,
            httpStatus: httpStatus,
            upnpErrorCode: upnpErrorCode
        ))
        if diagnosticEvents.count > 200 { diagnosticEvents.removeFirst(diagnosticEvents.count - 200) }
    }

    private func orderedDevices(_ devices: [RendererDevice]) -> [RendererDevice] {
        devices.sorted { lhs, rhs in
            let lhsSelected = lhs.id == selectedDeviceID
            let rhsSelected = rhs.id == selectedDeviceID
            if lhsSelected != rhsSelected { return lhsSelected }
            let nameOrder = lhs.friendlyName.localizedStandardCompare(rhs.friendlyName)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            let modelOrder = lhs.modelName.localizedStandardCompare(rhs.modelName)
            if modelOrder != .orderedSame { return modelOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

private struct StopConfirmationError: LocalizedError {
    let state: String
    var errorDescription: String? { "停止指示後もRendererの状態がSTOPPEDになりませんでした（現在: \(state)）。" }
}

private struct PauseConfirmationError: LocalizedError {
    let state: String
    var errorDescription: String? { "一時停止指示後もRendererの状態がPAUSED_PLAYBACKになりませんでした（現在: \(state)）。" }
}

private struct StereoStopConfirmationError: LocalizedError {
    let leftState: String
    let rightState: String
    var errorDescription: String? {
        "ステレオ停止を確認できませんでした（LEFT: \(leftState)、RIGHT: \(rightState)）。"
    }
}

private struct StereoPreparationConfirmationError: LocalizedError {
    let leftURI: String?
    let rightURI: String?
    let leftState: String
    let rightState: String
    var errorDescription: String? {
        "左右のスピーカーで新しい曲の読み込みを確認できませんでした（LEFT: \(leftState)、RIGHT: \(rightState)）。もう一度再生してください。"
    }
}

private func deduplicateByStableIdentity(_ devices: [RendererDevice]) -> [RendererDevice] {
    var seen = Set<String>()
    return devices.filter { seen.insert($0.id).inserted }
}
