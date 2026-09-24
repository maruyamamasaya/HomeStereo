import Darwin
import Foundation

public enum SSDPDiscovery {
    public static func discover(timeout: TimeInterval = 4) throws -> [SSDPResponse] {
        try discover(searchTargets: ["urn:schemas-upnp-org:device:MediaRenderer:1", "ssdp:all"], timeout: timeout)
    }

    public static func deviceDescriptionURL(rendererIP: String, timeout: TimeInterval = 4) throws -> URL {
        print("[DLNA] SSDP discovery started for selected renderer")
        if let response = try discover(timeout: timeout).first(where: { $0.sourceAddress == rendererIP }) {
            return response.location
        }
        throw HomeStereoError.noRendererFound(rendererIP)
    }

    public static func parseResponse(_ response: String, sourceAddress: String) -> SSDPResponse? {
        let lines = response.components(separatedBy: "\r\n")
        guard lines.first?.uppercased().hasPrefix("HTTP/1.1 200") == true else { return nil }
        let headers = parseHeaders(response)
        guard let locationValue = headers["location"],
              let location = URL(string: locationValue),
              let searchTarget = headers["st"] else { return nil }
        return SSDPResponse(
            usn: headers["usn"] ?? "",
            location: location,
            searchTarget: searchTarget,
            server: headers["server"],
            sourceAddress: sourceAddress
        )
    }

    private static func discover(searchTargets: [String], timeout: TimeInterval) throws -> [SSDPResponse] {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw HomeStereoError.serverFailure(String(cString: strerror(errno))) }
        defer { close(descriptor) }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, socklen_t(MemoryLayout<timeval>.size))
        var multicastTTL: UInt8 = 2
        setsockopt(descriptor, IPPROTO_IP, IP_MULTICAST_TTL, &multicastTTL, socklen_t(MemoryLayout<UInt8>.size))

        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = in_port_t(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &destination.sin_addr)
        for searchTarget in searchTargets {
            let request = [
                "M-SEARCH * HTTP/1.1",
                "HOST: 239.255.255.250:1900",
                "MAN: \"ssdp:discover\"",
                "MX: 2",
                "ST: \(searchTarget)",
                "",
                "",
            ].joined(separator: "\r\n")
            let sent = request.withCString { bytes in
                withUnsafePointer(to: &destination) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, bytes, strlen(bytes), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            guard sent >= 0 else { throw HomeStereoError.serverFailure(String(cString: strerror(errno))) }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 65_535)
        var responses: [SSDPResponse] = []
        var identifiers = Set<String>()
        while Date() < deadline {
            var source = sockaddr_in()
            var sourceLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let count = withUnsafeMutablePointer(to: &source) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                    recvfrom(descriptor, &buffer, buffer.count, 0, address, &sourceLength)
                }
            }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                throw HomeStereoError.serverFailure(String(cString: strerror(errno)))
            }
            var addressBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var sourceAddress = source.sin_addr
            inet_ntop(AF_INET, &sourceAddress, &addressBuffer, socklen_t(INET_ADDRSTRLEN))
            let sourceIP = String(decoding: addressBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
            let response = String(decoding: buffer.prefix(count), as: UTF8.self)
            guard let parsed = parseResponse(response, sourceAddress: sourceIP) else { continue }
            let identifier = parsed.usn.isEmpty ? parsed.location.absoluteString : parsed.usn
            guard identifiers.insert(identifier).inserted else { continue }
            responses.append(parsed)
        }
        return responses
    }

    public static func deduplicated(_ responses: [SSDPResponse]) -> [SSDPResponse] {
        var identifiers = Set<String>()
        return responses.filter {
            let identifier = $0.usn.isEmpty ? $0.location.absoluteString : $0.usn
            return identifiers.insert(identifier).inserted
        }
    }

    private static func parseHeaders(_ response: String) -> [String: String] {
        response.components(separatedBy: "\r\n").dropFirst().reduce(into: [:]) { result, line in
            guard let colon = line.firstIndex(of: ":") else { return }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
    }
}

public enum LANAddressResolver {
    public static func address(reaching rendererIP: String) throws -> String {
        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { throw HomeStereoError.noLANAddress(rendererIP) }
        defer { close(descriptor) }
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(9).bigEndian
        guard inet_pton(AF_INET, rendererIP, &remote.sin_addr) == 1 else {
            throw HomeStereoError.noLANAddress(rendererIP)
        }
        let connected = withUnsafePointer(to: &remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw HomeStereoError.noLANAddress(rendererIP) }
        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { throw HomeStereoError.noLANAddress(rendererIP) }
        var address = local.sin_addr
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
            throw HomeStereoError.noLANAddress(rendererIP)
        }
        let result = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        guard result != "127.0.0.1", result != "0.0.0.0" else {
            throw HomeStereoError.noLANAddress(rendererIP)
        }
        return result
    }
}

public enum DeviceDescriptionLoader {
    public static func load(from url: URL, session: URLSession = .shared) async throws -> MediaRenderer {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HomeStereoError.invalidDeviceDescription
        }
        let renderer = try DeviceDescriptionParser.parse(data: data, descriptionURL: url)
        print("[DLNA] MediaRenderer description loaded; AVTransport=\(renderer.avTransport != nil)")
        return renderer
    }
}
