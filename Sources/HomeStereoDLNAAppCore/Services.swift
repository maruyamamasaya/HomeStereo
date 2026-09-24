import AppKit
import CoreServices
import Foundation
import Network
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif
import UniformTypeIdentifiers

public struct RendererDiscoveryService: RendererDiscovering {
    public init() {}
    public func discover() async throws -> [SSDPResponse] {
        try await Task.detached { try SSDPDiscovery.discover() }.value
    }
}

public struct DeviceDescriptionService: DeviceDescriptionLoading {
    public init() {}
    public func load(from url: URL) async throws -> MediaRenderer {
        try await DeviceDescriptionLoader.load(from: url)
    }
}

@MainActor
public final class MediaFileSelectionService: MediaFileSelecting {
    public init() {}

    public func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "SRS-HG1へ配信する音源を1つ選択してください。"
        panel.allowedContentTypes = [
            .mp3, .mpeg4Audio, .wav, .aiff,
            UTType(filenameExtension: "aac"),
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "alac"),
        ].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func beginAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

public final class LocalMediaHTTPServerSession: MediaServerSession, @unchecked Sendable {
    private let server: TrackHTTPServer
    public var trackURL: URL { server.trackURL }
    public var mimeType: String { server.mimeType }

    init(server: TrackHTTPServer) { self.server = server }
    public func stop() { server.stop() }
}

public struct LocalMediaHTTPServerFactory: MediaServerCreating {
    public init() {}

    public func start(fileURL: URL, rendererAddress: String) throws -> any MediaServerSession {
        let localAddress = try LANAddressResolver.address(reaching: rendererAddress)
        let server = try TrackHTTPServer(fileURL: fileURL, host: localAddress)
        try server.start()
        return LocalMediaHTTPServerSession(server: server)
    }
}

public actor UPnPRendererController: RendererControlling {
    private let controller = UPnPController()
    public init() {}

    public func setURI(service: UPnPService, uri: URL, metadata: String) async throws {
        try await controller.setAVTransportURI(service: service, uri: uri, metadata: metadata)
    }
    public func play(service: UPnPService) async throws { try await controller.play(service: service) }
    public func pause(service: UPnPService) async throws { try await controller.pause(service: service) }
    public func stop(service: UPnPService) async throws { try await controller.stop(service: service) }
    public func seek(service: UPnPService, position: TimeInterval) async throws { try await controller.seek(service: service, position: position) }
    public func transportInfo(service: UPnPService) async throws -> TransportInfo { try await controller.getTransportInfo(service: service) }
    public func positionInfo(service: UPnPService) async throws -> PositionInfo { try await controller.getPositionInfo(service: service) }
    public func volume(service: UPnPService) async throws -> UInt8 { try await controller.getVolume(service: service) }
    public func setVolume(service: UPnPService, volume: UInt8) async throws { try await controller.setVolume(service: service, volume: volume) }
}

@MainActor
public final class PlaylistFileService: PlaylistFileServicing {
    public init() {}
    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [UTType(filenameExtension: "m3u8")].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }
    public func chooseExportURL(defaultName: String) -> URL? {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(defaultName).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8")].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
public final class MacSystemEventMonitor: SystemEventMonitoring {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "HomeStereo.NetworkMonitor")
    private var observers: [NSObjectProtocol] = []
    private var handler: (@MainActor (SystemPlaybackEvent) -> Void)?

    public init() {}

    public func start(_ handler: @escaping @MainActor (SystemPlaybackEvent) -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in handler(.willSleep) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in handler(.didWake) }
            }
        ]
        pathMonitor.pathUpdateHandler = { path in
            Task { @MainActor in handler(.networkAvailable(path.status == .satisfied)) }
        }
        pathMonitor.start(queue: queue)
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        pathMonitor.cancel()
        handler = nil
    }
}

@MainActor
public final class FolderChangeMonitor: FolderChangeMonitoring {
    private final class CallbackBox {
        let folderID: UUID
        let handler: @MainActor (UUID) -> Void
        init(folderID: UUID, handler: @escaping @MainActor (UUID) -> Void) { self.folderID = folderID; self.handler = handler }
    }
    private struct Registration { let stream: FSEventStreamRef; let box: Unmanaged<CallbackBox> }
    private var registrations: [Registration] = []

    public init() {}

    public func watch(_ folders: [UUID: URL], handler: @escaping @MainActor (UUID) -> Void) {
        stop()
        for (id, url) in folders {
            let box = Unmanaged.passRetained(CallbackBox(folderID: id, handler: handler))
            var context = FSEventStreamContext(
                version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in box.handler(box.folderID) }
            }
            guard let stream = FSEventStreamCreate(
                nil, callback, &context, [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.75,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
            ) else { box.release(); continue }
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
            registrations.append(Registration(stream: stream, box: box))
        }
    }

    public func stop() {
        for value in registrations {
            FSEventStreamStop(value.stream)
            FSEventStreamInvalidate(value.stream)
            FSEventStreamRelease(value.stream)
            value.box.release()
        }
        registrations = []
    }

}

@MainActor
public final class BackupFileService: BackupFileServicing {
    public init() {}
    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
    public func chooseExportURL() -> URL? {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "HomeStereo-Backup.json"; panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
public final class DiagnosticExportService {
    public init() {}

    public func export(_ data: Data) throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HomeStereo-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

public final class MacPlaybackActivityManager: PlaybackActivityManaging {
    private var token: NSObjectProtocol?

    public init() {}

    @MainActor
    public func setPlaybackActive(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "DLNA music playback"
            )
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
