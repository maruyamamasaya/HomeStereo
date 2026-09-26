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
    case myMusic
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

    public var id: String {
        if let description { return description.udn }
        if let separator = discovery.usn.range(of: "::") {
            return String(discovery.usn[..<separator.lowerBound])
        }
        return discovery.id
    }
    public var friendlyName: String { description?.friendlyName ?? discovery.sourceAddress }
    public var modelName: String { description?.modelName ?? "Device Description未取得" }
    public var supportsAVTransport: Bool { description?.avTransport != nil }

    public init(discovery: SSDPResponse, description: MediaRenderer? = nil, descriptionError: String? = nil) {
        self.discovery = discovery
        self.description = description
        self.descriptionError = descriptionError
    }
}

public struct StereoRendererPair: Equatable, Sendable {
    public let left: RendererDevice
    public let right: RendererDevice

    public init(left: RendererDevice, right: RendererDevice) {
        self.left = left
        self.right = right
    }
}

public struct StereoMediaFiles: Equatable, Sendable {
    public let leftURL: URL
    public let rightURL: URL
    public let sourceSampleRate: Double
    public let appliedDelayMilliseconds: Double

    public init(
        leftURL: URL,
        rightURL: URL,
        sourceSampleRate: Double = 0,
        appliedDelayMilliseconds: Double = 0
    ) {
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.sourceSampleRate = sourceSampleRate
        self.appliedDelayMilliseconds = appliedDelayMilliseconds
    }
}

public enum StereoChannel: String, CaseIterable, Identifiable, Sendable {
    case left = "LEFT"
    case right = "RIGHT"

    public var id: String { rawValue }
}

public enum StereoOutputQuality: String, CaseIterable, Identifiable, Sendable {
    case highResolution = "ハイレゾ維持"
    case stable48kHz = "安定優先 48kHz"

    public var id: String { rawValue }
}

public struct StereoPreparationOptions: Equatable, Sendable {
    public static let standard44_1kHzDelayMilliseconds: Double = 99
    public static let standard48kHzDelayMilliseconds: Double = 108
    public static let standardRateStepDelayMilliseconds: Double = 108
    public static let synchronizationCheckDuration: TimeInterval = 16

    public static func calibrated44_1kHzDelay(for48kHzBase milliseconds: Double) -> Double {
        (max(0, milliseconds) * 11 / 12 * 10).rounded() / 10
    }

    public let swapsChannels: Bool
    public let delayedChannel: StereoChannel
    /// Base delay for the 48 kHz sample-rate family. Kept under the original
    /// name so existing callers retain their previous behavior.
    public let delayMilliseconds: Double
    public let delay44_1kHzMilliseconds: Double
    public let outputQuality: StereoOutputQuality
    public let automaticSampleRateDelay: Bool
    public let delayPerRateStepMilliseconds: Double

    public init(
        swapsChannels: Bool,
        delayedChannel: StereoChannel,
        delayMilliseconds: Double,
        outputQuality: StereoOutputQuality = .stable48kHz,
        automaticSampleRateDelay: Bool = true,
        delayPerRateStepMilliseconds: Double = Self.standardRateStepDelayMilliseconds,
        delay44_1kHzMilliseconds: Double? = nil
    ) {
        self.swapsChannels = swapsChannels
        self.delayedChannel = delayedChannel
        self.delayMilliseconds = max(0, delayMilliseconds)
        self.delay44_1kHzMilliseconds = max(0, delay44_1kHzMilliseconds ?? delayMilliseconds)
        self.outputQuality = outputQuality
        self.automaticSampleRateDelay = automaticSampleRateDelay
        self.delayPerRateStepMilliseconds = max(0, delayPerRateStepMilliseconds)
    }

    func appliedDelayMilliseconds(forOutputSampleRate sampleRate: Double) -> Double {
        let candidates = (0...4).flatMap { step -> [(rate: Double, baseDelay: Double, step: Int)] in
            let multiplier = pow(2, Double(step))
            return [
                (44_100 * multiplier, delay44_1kHzMilliseconds, step),
                (48_000 * multiplier, delayMilliseconds, step),
            ]
        }
        let closest = candidates.min {
            abs(log(sampleRate / $0.rate)) < abs(log(sampleRate / $1.rate))
        } ?? (48_000, delayMilliseconds, 0)
        let rateStepDelay = automaticSampleRateDelay
            ? Double(closest.step) * delayPerRateStepMilliseconds
            : 0
        return closest.baseDelay + rateStepDelay
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
