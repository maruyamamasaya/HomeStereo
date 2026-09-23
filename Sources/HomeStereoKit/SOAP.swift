import Foundation

public enum UPnPTime {
    public static func parse(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":")
        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]),
              minutes >= 0, minutes < 60, seconds >= 0, seconds < 60 else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

public enum SOAPRequestBuilder {
    public static func envelope(serviceType: String, action: String, arguments: [(String, String)]) -> Data {
        let values = arguments.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(serviceType)">\(values)</u:\(action)></s:Body></s:Envelope>
        """
        return Data(xml.utf8)
    }

    public static func didlLiteMetadata(resourceURL: URL, mimeType: String, title: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="0" parentID="-1" restricted="1"><dc:title>\(escape(title))</dc:title><upnp:class>object.item.audioItem.musicTrack</upnp:class><res protocolInfo="http-get:*:\(mimeType):*">\(escape(resourceURL.absoluteString))</res></item></DIDL-Lite>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

public actor UPnPController {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func setAVTransportURI(service: UPnPService, uri: URL, metadata: String) async throws {
        try await invoke(service: service, action: "SetAVTransportURI", arguments: [
            ("InstanceID", "0"), ("CurrentURI", uri.absoluteString), ("CurrentURIMetaData", metadata),
        ])
    }

    public func play(service: UPnPService) async throws {
        try await invoke(service: service, action: "Play", arguments: [("InstanceID", "0"), ("Speed", "1")])
    }

    public func pause(service: UPnPService) async throws {
        try await invoke(service: service, action: "Pause", arguments: [("InstanceID", "0")])
    }

    public func stop(service: UPnPService) async throws {
        try await invoke(service: service, action: "Stop", arguments: [("InstanceID", "0")])
    }

    public func seek(service: UPnPService, position: TimeInterval) async throws {
        try await invoke(service: service, action: "Seek", arguments: [
            ("InstanceID", "0"), ("Unit", "REL_TIME"), ("Target", UPnPTime.format(position)),
        ])
    }

    public func setVolume(service: UPnPService, volume: UInt8) async throws {
        try await invoke(service: service, action: "SetVolume", arguments: [
            ("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", String(min(volume, 100))),
        ])
    }

    private func invoke(service: UPnPService, action: String, arguments: [(String, String)]) async throws {
        var request = URLRequest(url: service.controlURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service.serviceType)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = SOAPRequestBuilder.envelope(serviceType: service.serviceType, action: action, arguments: arguments)
        print("[DLNA] \(action) -> \(service.controlURL.absoluteString)")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        print("[DLNA] Renderer response: HTTP \(status)")
        guard (200..<300).contains(status) else {
            throw HomeStereoError.soapFailure(action: action, status: status, body: String(decoding: data, as: UTF8.self))
        }
    }
}
