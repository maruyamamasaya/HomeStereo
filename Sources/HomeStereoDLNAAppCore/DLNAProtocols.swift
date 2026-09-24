import Foundation
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif

public protocol RendererDiscovering: Sendable {
    func discover() async throws -> [SSDPResponse]
}

public protocol DeviceDescriptionLoading: Sendable {
    func load(from url: URL) async throws -> MediaRenderer
}

@MainActor
public protocol MediaFileSelecting: AnyObject {
    func chooseFile() -> URL?
    func beginAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public protocol MediaServerSession: AnyObject, Sendable {
    var trackURL: URL { get }
    var mimeType: String { get }
    func stop()
}

public protocol MediaServerCreating: Sendable {
    func start(fileURL: URL, rendererAddress: String) throws -> any MediaServerSession
}

public protocol RendererControlling: Sendable {
    func setURI(service: UPnPService, uri: URL, metadata: String) async throws
    func play(service: UPnPService) async throws
    func pause(service: UPnPService) async throws
    func stop(service: UPnPService) async throws
    func seek(service: UPnPService, position: TimeInterval) async throws
    func transportInfo(service: UPnPService) async throws -> TransportInfo
    func positionInfo(service: UPnPService) async throws -> PositionInfo
    func volume(service: UPnPService) async throws -> UInt8
    func setVolume(service: UPnPService, volume: UInt8) async throws
}

@MainActor
public protocol PlaylistFileServicing: AnyObject {
    func chooseImportURL() -> URL?
    func chooseExportURL(defaultName: String) -> URL?
}

public enum SystemPlaybackEvent: Equatable, Sendable {
    case willSleep
    case didWake
    case networkAvailable(Bool)
}

@MainActor
public protocol SystemEventMonitoring: AnyObject {
    func start(_ handler: @escaping @MainActor (SystemPlaybackEvent) -> Void)
    func stop()
}

@MainActor
public protocol FolderChangeMonitoring: AnyObject {
    func watch(_ folders: [UUID: URL], handler: @escaping @MainActor (UUID) -> Void)
    func stop()
}

@MainActor
public protocol BackupFileServicing: AnyObject {
    func chooseImportURL() -> URL?
    func chooseExportURL() -> URL?
}

public protocol PlaybackActivityManaging: AnyObject {
    @MainActor
    func setPlaybackActive(_ active: Bool)
}

public final class NoopPlaybackActivityManager: PlaybackActivityManaging {
    public init() {}
    @MainActor
    public func setPlaybackActive(_ active: Bool) {}
}
