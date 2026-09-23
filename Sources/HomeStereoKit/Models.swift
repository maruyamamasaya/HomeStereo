import Foundation

public struct UPnPService: Equatable, Sendable {
    public let serviceType: String
    public let serviceID: String
    public let controlURL: URL
    public let eventSubscriptionURL: URL?
    public let descriptionURL: URL?
}

public struct MediaRenderer: Equatable, Sendable {
    public let descriptionURL: URL
    public let deviceType: String
    public let friendlyName: String
    public let manufacturer: String
    public let modelName: String
    public let modelNumber: String?
    public let udn: String
    public let services: [UPnPService]

    public var avTransport: UPnPService? {
        services.first { $0.serviceType.hasPrefix("urn:schemas-upnp-org:service:AVTransport:") }
    }

    public var renderingControl: UPnPService? {
        services.first { $0.serviceType.hasPrefix("urn:schemas-upnp-org:service:RenderingControl:") }
    }
}

public enum HomeStereoError: LocalizedError, Equatable {
    case invalidDeviceDescription
    case missingAVTransport
    case noRendererFound(String)
    case noLANAddress(String)
    case unsupportedAudioFormat(String)
    case invalidRange
    case cannotBindPort(Int)
    case serverFailure(String)
    case soapFailure(action: String, status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .invalidDeviceDescription: "Invalid UPnP device description."
        case .missingAVTransport: "The renderer does not advertise AVTransport."
        case let .noRendererFound(ip): "No MediaRenderer SSDP response was received from \(ip)."
        case let .noLANAddress(ip): "Could not determine a LAN address that can reach \(ip)."
        case let .unsupportedAudioFormat(ext): "Unsupported audio filename extension: \(ext)"
        case .invalidRange: "Invalid HTTP byte range."
        case let .cannotBindPort(port): "Could not bind TCP port \(port) or a later safe port."
        case let .serverFailure(message): "HTTP server failure: \(message)"
        case let .soapFailure(action, status, body): "UPnP \(action) failed (HTTP \(status)): \(body)"
        }
    }
}
