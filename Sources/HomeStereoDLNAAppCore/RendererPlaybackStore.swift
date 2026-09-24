import Foundation
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif
import Observation

@MainActor
@Observable
public final class RendererPlaybackStore {
    public var destination: DLNASidebarDestination = .devices
    public private(set) var devices: [RendererDevice] = []
    public var selectedDeviceID: String?
    public private(set) var media: LocalMediaResource?
    public private(set) var selectedLibraryTrackID: UUID?
    public private(set) var playbackState: RendererPlaybackState = .stopped
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var volume: Double = 0
    public private(set) var isDiscovering = false
    public private(set) var isBusy = false
    public private(set) var lastError: PlaybackDiagnostic?
    public private(set) var playbackGeneration = UUID()
    @ObservationIgnored public var onTrackFinished: (@MainActor () -> Void)?
    @ObservationIgnored public var onPositionChange: (@MainActor (TimeInterval) -> Void)?
    @ObservationIgnored public var onCommunicationFailure: (@MainActor (PlaybackDiagnostic) -> Void)?
    @ObservationIgnored public var onPlaybackStateChange: (@MainActor (RendererPlaybackState) -> Void)?
    @ObservationIgnored public var onRendererTrackChanged: (@MainActor () -> Void)?
    @ObservationIgnored public var onPresentationChange: (@MainActor () -> Void)?

    @ObservationIgnored private let discovery: any RendererDiscovering
    @ObservationIgnored private let descriptions: any DeviceDescriptionLoading
    @ObservationIgnored private let fileSelection: any MediaFileSelecting
    @ObservationIgnored private let serverFactory: any MediaServerCreating
    @ObservationIgnored private let controller: any RendererControlling
    @ObservationIgnored private let activityManager: any PlaybackActivityManaging
    @ObservationIgnored private let pollingInterval: Duration
    @ObservationIgnored private var activeServer: (any MediaServerSession)?
    @ObservationIgnored private var retiredServers: [any MediaServerSession] = []
    @ObservationIgnored private var activeScopedURL: URL?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private var completedGeneration: UUID?
    @ObservationIgnored private var lastConfirmedPosition: TimeInterval = 0
    @ObservationIgnored private var refreshSequence: UInt64 = 0
    @ObservationIgnored private var diagnosticEvents: [PlaybackDiagnosticEvent] = []

    public var selectedDevice: RendererDevice? { devices.first { $0.id == selectedDeviceID } }

    public init(
        discovery: any RendererDiscovering,
        descriptions: any DeviceDescriptionLoading,
        fileSelection: any MediaFileSelecting,
        serverFactory: any MediaServerCreating,
        controller: any RendererControlling,
        activityManager: any PlaybackActivityManaging = NoopPlaybackActivityManager(),
        pollingInterval: Duration = .seconds(1)
    ) {
        self.discovery = discovery
        self.descriptions = descriptions
        self.fileSelection = fileSelection
        self.serverFactory = serverFactory
        self.controller = controller
        self.activityManager = activityManager
        self.pollingInterval = pollingInterval
    }

    public func discoverRenderers() async {
        isDiscovering = true
        lastError = nil
        do {
            let responses = try await discovery.discover()
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
                    loaded.append(RendererDevice(discovery: response, descriptionError: error.localizedDescription))
                }
            }
            devices = deduplicateByStableIdentity(loaded)
            if let selectedDeviceID, !devices.contains(where: { $0.id == selectedDeviceID }) {
                rendererBecameUnavailable()
            }
        } catch { record(error, action: "SSDP M-SEARCH") }
        isDiscovering = false
    }

    public func selectDevice(_ id: String?) {
        guard id != selectedDeviceID else { return }
        beginPlaybackGeneration()
        selectedDeviceID = id
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

    public func chooseFile() {
        guard let url = fileSelection.chooseFile() else { return }
        do {
            let resource = try LocalMediaResource(fileURL: url)
            beginPlaybackGeneration()
            retireActiveServer()
            stopSecurityScope()
            activeScopedURL = fileSelection.beginAccessing(url) ? url : nil
            media = resource
            selectedLibraryTrackID = nil
            setPlaybackState(.stopped)
            elapsed = 0
            duration = 0
            lastError = nil
            onPresentationChange?()
        } catch { record(error, action: "ファイル選択") }
    }

    @discardableResult
    public func selectLibraryFile(_ url: URL, expectedDuration: TimeInterval? = nil, trackID: UUID? = nil) -> Bool {
        do {
            let resource = try LocalMediaResource(fileURL: url)
            beginPlaybackGeneration()
            retireActiveServer()
            stopSecurityScope()
            media = resource
            selectedLibraryTrackID = trackID
            setPlaybackState(.stopped)
            elapsed = 0
            duration = expectedDuration ?? 0
            lastError = nil
            onPresentationChange?()
            return true
        } catch {
            record(error, action: "Libraryから再生")
            return false
        }
    }

    public func togglePlayback() async { playbackState == .playing ? await pause() : await play() }

    public func play() async {
        await serializeCommand { [weak self] in
            guard let self, let context = self.playbackContext() else { return }
            await self.perform(action: "Play") {
                if self.activeServer == nil {
                    let server = try self.serverFactory.start(fileURL: context.media.fileURL, rendererAddress: context.device.discovery.sourceAddress)
                    self.activeServer = server
                    let metadata = SOAPRequestBuilder.didlLiteMetadata(resourceURL: server.trackURL, mimeType: server.mimeType, title: context.media.title)
                    try await self.controller.setURI(service: context.transport, uri: server.trackURL, metadata: metadata)
                }
                try await self.controller.play(service: context.transport)
                self.setPlaybackState(.playing)
                self.startPolling()
            }
        }
    }

    public func pause() async {
        await serializeCommand { [weak self] in
            guard let self, let transport = self.selectedDevice?.description?.avTransport else { return }
            await self.perform(action: "Pause") {
                try await self.controller.pause(service: transport)
                self.setPlaybackState(.paused)
            }
        }
    }

    public func stop() async {
        await serializeCommand { [weak self] in
            guard let self, let transport = self.selectedDevice?.description?.avTransport else { return }
            await self.perform(action: "Stop") {
                try await self.controller.stop(service: transport)
                self.setPlaybackState(.stopped)
                self.elapsed = 0
                self.lastConfirmedPosition = 0
            }
        }
    }

    public func seek(to position: TimeInterval) async {
        await serializeCommand { [weak self] in
            guard let self, let transport = self.selectedDevice?.description?.avTransport else { return }
            await self.perform(action: "Seek") {
                try await self.controller.seek(service: transport, position: position)
                self.elapsed = position
                self.lastConfirmedPosition = position
            }
        }
    }

    public func setVolume(_ value: Double) async {
        guard let service = selectedDevice?.description?.renderingControl else { return }
        let clamped = UInt8(min(100, max(0, value)).rounded())
        await perform(action: "SetVolume") { try await self.controller.setVolume(service: service, volume: clamped); self.volume = Double(clamped) }
    }

    public func refreshState() async {
        guard let description = selectedDevice?.description else { return }
        refreshSequence &+= 1
        let sequence = refreshSequence
        let generation = playbackGeneration
        var observedGeneration = generation
        if let transport = description.avTransport {
            do {
                let previousState = playbackState
                let info = try await controller.transportInfo(service: transport)
                guard generation == playbackGeneration, sequence == refreshSequence else { return }
                let reportedState = RendererPlaybackState(rawValue: info.state) ?? .unknown
                let position = try await controller.positionInfo(service: transport)
                guard generation == playbackGeneration, sequence == refreshSequence else { return }
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
                    onTrackFinished?()
                }
            } catch {
                guard observedGeneration == playbackGeneration, sequence == refreshSequence else { return }
                setPlaybackState(.unknown)
                record(error, action: "GetTransportInfo / GetPositionInfo")
            }
        }
        if let rendering = description.renderingControl {
            do {
                let reportedVolume = try await controller.volume(service: rendering)
                guard generation == playbackGeneration, sequence == refreshSequence else { return }
                volume = Double(reportedVolume)
            }
            catch { record(error, action: "GetVolume") }
        }
    }

    public func shutdown() {
        pollingTask?.cancel()
        commandTail?.cancel()
        stopServing()
        stopSecurityScope()
        activityManager.setPlaybackActive(false)
    }

    public func prepareForSystemInterruption() {
        beginPlaybackGeneration()
        pollingTask?.cancel()
        stopServing()
        setPlaybackState(.unknown)
    }

    public func reconnect(udn: String?) async -> Bool {
        await discoverRenderers()
        guard let udn, let device = devices.first(where: { $0.description?.udn == udn }) else { return false }
        selectedDeviceID = device.id
        await refreshState()
        startPolling()
        return lastError == nil
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
        refreshSequence &+= 1
        completedGeneration = nil
        lastConfirmedPosition = 0
        pollingTask?.cancel()
    }

    private func rendererBecameUnavailable() {
        beginPlaybackGeneration()
        selectedDeviceID = nil
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
        guard let server = activeServer else { return }
        activeServer = nil
        retiredServers.append(server)
        let identity = ObjectIdentifier(server)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self else { return }
            guard let index = self.retiredServers.firstIndex(where: { ObjectIdentifier($0) == identity }) else { return }
            self.retiredServers.remove(at: index).stop()
        }
    }

    private func stopServing() {
        activeServer?.stop()
        activeServer = nil
        retiredServers.forEach { $0.stop() }
        retiredServers.removeAll()
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
}

private func deduplicateByStableIdentity(_ devices: [RendererDevice]) -> [RendererDevice] {
    var seen = Set<String>()
    return devices.filter { seen.insert($0.id).inserted }
}
