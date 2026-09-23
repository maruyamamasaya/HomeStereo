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
