import Foundation
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif

public enum DLNASidebarDestination: Hashable, Sendable {
    case devices
    case songs
    case albums
    case artists
    case folders
    case queue
    case playlists
    case favorites
    case history
    case backup
    case playback
}

public enum RendererPlaybackState: String, Sendable {
    case stopped = "STOPPED"
    case playing = "PLAYING"
    case paused = "PAUSED_PLAYBACK"
    case transitioning = "TRANSITIONING"
    case unknown = "UNKNOWN"
}

public enum NowPlayingDisplayState: Equatable, Sendable {
    case empty
    case loading
    case stopped
    case playing
    case paused
    case unknown
}

public struct NowPlayingPresentation: Equatable, Sendable {
    public let trackID: UUID?
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval
    public let elapsed: TimeInterval
    public let state: NowPlayingDisplayState

    public init(
        trackID: UUID? = nil,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        state: NowPlayingDisplayState = .empty
    ) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.state = state
    }

    public var hasMedia: Bool { title != nil }
    public var isQueueTrack: Bool { trackID != nil }
}

public struct RendererDevice: Identifiable, Equatable, Sendable {
    public let discovery: SSDPResponse
    public var description: MediaRenderer?
    public var descriptionError: String?

    public var id: String { description?.udn ?? discovery.id }
    public var friendlyName: String { description?.friendlyName ?? discovery.sourceAddress }
    public var modelName: String { description?.modelName ?? "Device Description未取得" }
    public var supportsAVTransport: Bool { description?.avTransport != nil }

    public init(discovery: SSDPResponse, description: MediaRenderer? = nil, descriptionError: String? = nil) {
        self.discovery = discovery
        self.description = description
        self.descriptionError = descriptionError
    }
}

public struct LocalMediaResource: Equatable, Sendable {
    public let fileURL: URL
    public let title: String
    public let fileExtension: String
    public let mimeType: String

    public init(fileURL: URL) throws {
        self.fileURL = fileURL.standardizedFileURL
        self.title = fileURL.deletingPathExtension().lastPathComponent
        self.fileExtension = fileURL.pathExtension.uppercased()
        self.mimeType = try AudioMIMEType.forFileURL(fileURL)
    }
}

public struct PlaybackDiagnostic: Equatable, Sendable {
    public let action: String
    public let httpStatus: Int?
    public let upnpErrorCode: Int?
    public let details: String

    public init(action: String, httpStatus: Int? = nil, upnpErrorCode: Int? = nil, details: String) {
        self.action = action
        self.httpStatus = httpStatus
        self.upnpErrorCode = upnpErrorCode
        self.details = details
    }
}

public struct PlaybackDiagnosticEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let generationID: UUID
    public let action: String
    public let outcome: String
    public let httpStatus: Int?
    public let upnpErrorCode: Int?

    public init(timestamp: Date = Date(), generationID: UUID, action: String, outcome: String, httpStatus: Int? = nil, upnpErrorCode: Int? = nil) {
        self.timestamp = timestamp
        self.generationID = generationID
        self.action = action
        self.outcome = outcome
        self.httpStatus = httpStatus
        self.upnpErrorCode = upnpErrorCode
    }
}
