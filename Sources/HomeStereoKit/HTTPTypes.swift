import Foundation

public struct ByteRange: Equatable, Sendable {
    public let lowerBound: Int64
    public let upperBound: Int64

    public var length: Int64 { upperBound - lowerBound + 1 }

    public static func parse(_ header: String?, fileSize: Int64) throws -> ByteRange? {
        guard let header, !header.isEmpty else { return nil }
        guard fileSize > 0, header.lowercased().hasPrefix("bytes=") else {
            throw HomeStereoError.invalidRange
        }
        let spec = header.dropFirst(6)
        guard !spec.contains(","), let dash = spec.firstIndex(of: "-") else {
            throw HomeStereoError.invalidRange
        }
        let left = spec[..<dash]
        let right = spec[spec.index(after: dash)...]
        if left.isEmpty {
            guard let suffix = Int64(right), suffix > 0 else { throw HomeStereoError.invalidRange }
            let length = min(suffix, fileSize)
            return ByteRange(lowerBound: fileSize - length, upperBound: fileSize - 1)
        }
        guard let start = Int64(left), start >= 0, start < fileSize else {
            throw HomeStereoError.invalidRange
        }
        let end: Int64
        if right.isEmpty {
            end = fileSize - 1
        } else {
            guard let requestedEnd = Int64(right), requestedEnd >= start else {
                throw HomeStereoError.invalidRange
            }
            end = min(requestedEnd, fileSize - 1)
        }
        return ByteRange(lowerBound: start, upperBound: end)
    }
}

public enum AudioMIMEType {
    public static func forFileURL(_ url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "mp3": "audio/mpeg"
        case "m4a", "mp4", "alac": "audio/mp4"
        case "aac": "audio/aac"
        case "flac": "audio/flac"
        case "wav", "wave": "audio/wav"
        case "aif", "aiff", "aifc": "audio/aiff"
        default: throw HomeStereoError.unsupportedAudioFormat(url.pathExtension)
        }
    }
}

public enum TrackURLBuilder {
    public static func url(host: String, port: UInt16, trackID: UUID, token: String) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/tracks/\(trackID.uuidString.lowercased())"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }
}

public struct MediaHTTPResponse: Equatable, Sendable {
    public let status: Int
    public let headers: [String: String]
    public let bodyRange: ByteRange?

    public init(status: Int, headers: [String: String], bodyRange: ByteRange?) {
        self.status = status
        self.headers = headers
        self.bodyRange = bodyRange
    }
}

public enum MediaHTTPRequestHandler {
    public static func response(
        method: String,
        target: String,
        headers: [String: String],
        trackID: UUID,
        token: String,
        mimeType: String,
        fileSize: Int64
    ) -> MediaHTTPResponse {
        guard method == "GET" || method == "HEAD",
              let components = URLComponents(string: "http://placeholder\(target)"),
              components.path == "/tracks/\(trackID.uuidString.lowercased())",
              components.queryItems?.first(where: { $0.name == "token" })?.value == token else {
            return MediaHTTPResponse(status: 404, headers: ["Content-Length": "0"], bodyRange: nil)
        }
        do {
            let requestedRange = try ByteRange.parse(headers["range"], fileSize: fileSize)
            let selected = requestedRange ?? ByteRange(lowerBound: 0, upperBound: max(0, fileSize - 1))
            var responseHeaders = [
                "Content-Type": mimeType,
                "Content-Length": String(fileSize == 0 ? 0 : selected.length),
                "Accept-Ranges": "bytes",
            ]
            if requestedRange != nil {
                responseHeaders["Content-Range"] = "bytes \(selected.lowerBound)-\(selected.upperBound)/\(fileSize)"
            }
            return MediaHTTPResponse(
                status: requestedRange == nil ? 200 : 206,
                headers: responseHeaders,
                bodyRange: method == "GET" && fileSize > 0 ? selected : nil
            )
        } catch {
            return MediaHTTPResponse(
                status: 416,
                headers: ["Content-Length": "0", "Content-Range": "bytes */\(fileSize)"],
                bodyRange: nil
            )
        }
    }
}
