import Foundation

public struct CapturePlaybackSegment: Equatable, Sendable {
    public let number: Int
    public let leftURL: URL
    public let rightURL: URL
    public let duration: TimeInterval
    public let leftPeakDBFS: Double
    public let rightPeakDBFS: Double
}

public struct CapturePlaybackPlan: Equatable, Sendable {
    public let generatedAt: Date
    public let sourceDeviceName: String
    public let segments: [CapturePlaybackSegment]
    public let maximumPeakDBFS: Double

    public static func load(
        reportURL: URL,
        silenceFloorDBFS: Double = -100,
        safetyCeilingDBFS: Double = -6
    ) throws -> CapturePlaybackPlan {
        let report = try JSONDecoder.withISO8601Dates.decode(
            AudioCaptureReport.self,
            from: Data(contentsOf: reportURL)
        )
        guard report.hardwareSampleRate.isFinite, report.hardwareSampleRate > 0 else {
            throw AudioCaptureError("Capture report has an invalid sample rate")
        }
        guard !report.segments.isEmpty else {
            throw AudioCaptureError("Capture report does not contain any audio segments")
        }

        var seen = Set<Int>()
        let segments = try report.segments.sorted { $0.segment < $1.segment }.map { segment in
            guard seen.insert(segment.segment).inserted else {
                throw AudioCaptureError("Capture report contains duplicate segment \(segment.segment)")
            }
            guard segment.frames > 0 else {
                throw AudioCaptureError("Segment \(segment.segment) has no audio frames")
            }
            let leftURL = URL(fileURLWithPath: segment.leftPath).standardizedFileURL
            let rightURL = URL(fileURLWithPath: segment.rightPath).standardizedFileURL
            let duration = Double(segment.frames) / report.hardwareSampleRate
            guard leftURL.pathExtension.lowercased() == "wav",
                  rightURL.pathExtension.lowercased() == "wav",
                  leftURL != rightURL,
                  FileManager.default.isReadableFile(atPath: leftURL.path),
                  FileManager.default.isReadableFile(atPath: rightURL.path) else {
                throw AudioCaptureError("Segment \(segment.segment) LEFT/RIGHT WAV files are unavailable")
            }
            guard duration >= 0.1 else {
                throw AudioCaptureError("Segment \(segment.segment) is too short for safe Renderer playback")
            }
            guard segment.leftPeakDBFS.isFinite, segment.rightPeakDBFS.isFinite else {
                throw AudioCaptureError("Segment \(segment.segment) has invalid peak measurements")
            }
            return CapturePlaybackSegment(
                number: segment.segment,
                leftURL: leftURL,
                rightURL: rightURL,
                duration: duration,
                leftPeakDBFS: segment.leftPeakDBFS,
                rightPeakDBFS: segment.rightPeakDBFS
            )
        }

        let maximumPeak = segments.reduce(-Double.infinity) {
            max($0, max($1.leftPeakDBFS, $1.rightPeakDBFS))
        }
        guard maximumPeak > silenceFloorDBFS else {
            throw AudioCaptureError("Captured audio is silent; verify the Audio Hijack session before speaker playback")
        }
        guard maximumPeak <= safetyCeilingDBFS else {
            throw AudioCaptureError(
                "Captured peak \(String(format: "%.1f", maximumPeak)) dBFS exceeds the safe test ceiling "
                    + "\(String(format: "%.1f", safetyCeilingDBFS)) dBFS; lower the Audio Hijack output and capture again"
            )
        }

        return CapturePlaybackPlan(
            generatedAt: report.generatedAt,
            sourceDeviceName: report.device.name,
            segments: segments,
            maximumPeakDBFS: maximumPeak
        )
    }
}

private extension JSONDecoder {
    static var withISO8601Dates: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
