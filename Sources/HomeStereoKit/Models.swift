import Foundation

public struct UPnPService: Equatable, Sendable {
    public let serviceType: String
    public let serviceID: String
    public let controlURL: URL
    public let eventSubscriptionURL: URL?
    public let descriptionURL: URL?

    public init(serviceType: String, serviceID: String, controlURL: URL, eventSubscriptionURL: URL?, descriptionURL: URL?) {
        self.serviceType = serviceType
        self.serviceID = serviceID
        self.controlURL = controlURL
        self.eventSubscriptionURL = eventSubscriptionURL
        self.descriptionURL = descriptionURL
    }
}

public struct SSDPResponse: Identifiable, Equatable, Sendable {
    public let usn: String
    public let location: URL
    public let searchTarget: String
    public let server: String?
    public let sourceAddress: String

    public var id: String { usn.isEmpty ? location.absoluteString : usn }

    public init(usn: String, location: URL, searchTarget: String, server: String?, sourceAddress: String) {
        self.usn = usn
        self.location = location
        self.searchTarget = searchTarget
        self.server = server
        self.sourceAddress = sourceAddress
    }
}

public struct MediaRenderer: Equatable, Sendable {
    public let descriptionURL: URL
    public let deviceType: String
    public let friendlyName: String
    public let manufacturer: String
    public let modelName: String
    public let modelNumber: String?
    public let udn: String
    public let presentationURL: URL?
    public let services: [UPnPService]

    public init(
        descriptionURL: URL,
        deviceType: String,
        friendlyName: String,
        manufacturer: String,
        modelName: String,
        modelNumber: String?,
        udn: String,
        presentationURL: URL? = nil,
        services: [UPnPService]
    ) {
        self.descriptionURL = descriptionURL
        self.deviceType = deviceType
        self.friendlyName = friendlyName
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.udn = udn
        self.presentationURL = presentationURL
        self.services = services
    }

    public var avTransport: UPnPService? {
        services.first { $0.serviceType.hasPrefix("urn:schemas-upnp-org:service:AVTransport:") }
    }

    public var renderingControl: UPnPService? {
        services.first { $0.serviceType.hasPrefix("urn:schemas-upnp-org:service:RenderingControl:") }
    }

    public var connectionManager: UPnPService? {
        services.first { $0.serviceType.hasPrefix("urn:schemas-upnp-org:service:ConnectionManager:") }
    }
}

public struct TransportInfo: Equatable, Sendable {
    public let state: String
    public let status: String
    public let speed: String

    public init(state: String, status: String, speed: String) {
        self.state = state
        self.status = status
        self.speed = speed
    }
}

public struct PositionInfo: Equatable, Sendable {
    public let duration: TimeInterval?
    public let position: TimeInterval?
    public let trackURI: String?

    public init(duration: TimeInterval?, position: TimeInterval?, trackURI: String?) {
        self.duration = duration
        self.position = position
        self.trackURI = trackURI
    }
}

public struct ProtocolInfo: Equatable, Sendable {
    public let source: [String]
    public let sink: [String]

    public init(source: [String], sink: [String]) {
        self.source = source
        self.sink = sink
    }
}

public struct UPnPFailure: Error, Equatable, Sendable {
    public let action: String
    public let httpStatus: Int
    public let errorCode: Int?
    public let errorDescription: String?

    public init(action: String, httpStatus: Int, errorCode: Int?, errorDescription: String?) {
        self.action = action
        self.httpStatus = httpStatus
        self.errorCode = errorCode
        self.errorDescription = errorDescription
    }
}

public enum HomeStereoError: LocalizedError, Equatable {
    case invalidDeviceDescription
    case invalidServiceDescription
    case missingAVTransport
    case noRendererFound(String)
    case noLANAddress(String)
    case unsupportedAudioFormat(String)
    case invalidRange
    case cannotBindPort(Int)
    case serverFailure(String)
    case soapFailure(action: String, status: Int, body: String)
    case upnpFailure(UPnPFailure)

    public var errorDescription: String? {
        switch self {
        case .invalidDeviceDescription: "Invalid UPnP device description."
        case .invalidServiceDescription: "Invalid UPnP service description."
        case .missingAVTransport: "The renderer does not advertise AVTransport."
        case let .noRendererFound(ip): "No MediaRenderer SSDP response was received from \(ip)."
        case let .noLANAddress(ip): "Could not determine a LAN address that can reach \(ip)."
        case let .unsupportedAudioFormat(ext): "Unsupported audio filename extension: \(ext)"
        case .invalidRange: "Invalid HTTP byte range."
        case let .cannotBindPort(port): "Could not bind TCP port \(port) or a later safe port."
        case let .serverFailure(message): "HTTP server failure: \(message)"
        case let .soapFailure(action, status, body): "UPnP \(action) failed (HTTP \(status)): \(body)"
        case let .upnpFailure(failure):
            "UPnP \(failure.action) failed (HTTP \(failure.httpStatus), code \(failure.errorCode.map(String.init) ?? "unknown")): \(failure.errorDescription ?? "Unknown error")"
        }
    }
}
