import Foundation

public struct StereoSegmentSummary: Codable, Equatable, Sendable {
    public let segment: Int
    public let frames: Int
    public let leftPath: String
    public let rightPath: String
    public let leftPeakDBFS: Double
    public let rightPeakDBFS: Double
}

public final class StereoSegmentWriter: @unchecked Sendable {
    private let outputDirectory: URL
    private let sampleRate: Int
    private let framesPerSegment: Int
    private var left: [Float] = []
    private var right: [Float] = []
    private var nextSegment = 1
    private(set) public var summaries: [StereoSegmentSummary] = []

    public init(outputDirectory: URL, sampleRate: Int, segmentSeconds: Double) throws {
        guard sampleRate > 0, segmentSeconds > 0 else {
            throw AudioCaptureError("Sample rate and segment duration must be positive")
        }
        self.outputDirectory = outputDirectory
        self.sampleRate = sampleRate
        self.framesPerSegment = Int((Double(sampleRate) * segmentSeconds).rounded())
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        left.reserveCapacity(framesPerSegment)
        right.reserveCapacity(framesPerSegment)
    }

    public func append(left newLeft: [Float], right newRight: [Float]) throws {
        guard newLeft.count == newRight.count else {
            throw AudioCaptureError("LEFT and RIGHT buffers must share one frame timeline")
        }
        var offset = 0
        while offset < newLeft.count {
            let count = min(framesPerSegment - left.count, newLeft.count - offset)
            left.append(contentsOf: newLeft[offset..<(offset + count)])
            right.append(contentsOf: newRight[offset..<(offset + count)])
            offset += count
            if left.count == framesPerSegment { try flush() }
        }
    }

    public func finish(includePartialSegment: Bool = true) throws {
        if includePartialSegment, !left.isEmpty { try flush() }
    }

    private func flush() throws {
        let leftURL = outputDirectory.appendingPathComponent(String(format: "segment-left-%04d.wav", nextSegment))
        let rightURL = outputDirectory.appendingPathComponent(String(format: "segment-right-%04d.wav", nextSegment))
        try WAV16Writer.write(samples: left, sampleRate: sampleRate, to: leftURL)
        try WAV16Writer.write(samples: right, sampleRate: sampleRate, to: rightURL)
        summaries.append(StereoSegmentSummary(
            segment: nextSegment,
            frames: left.count,
            leftPath: leftURL.path,
            rightPath: rightURL.path,
            leftPeakDBFS: Self.peakDBFS(left),
            rightPeakDBFS: Self.peakDBFS(right)
        ))
        nextSegment += 1
        left.removeAll(keepingCapacity: true)
        right.removeAll(keepingCapacity: true)
    }

    private static func peakDBFS(_ samples: [Float]) -> Double {
        let peak = samples.reduce(Float.zero) { max($0, abs($1)) }
        return peak > 0 ? 20 * log10(Double(peak)) : -160
    }
}

enum WAV16Writer {
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data()
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        data.appendASCII("RIFF")
        data.appendLE(UInt32(36) + dataSize)
        data.appendASCII("WAVEfmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(1))
        data.appendLE(UInt32(sampleRate))
        data.appendLE(UInt32(sampleRate * MemoryLayout<Int16>.size))
        data.appendLE(UInt16(MemoryLayout<Int16>.size))
        data.appendLE(UInt16(16))
        data.appendASCII("data")
        data.appendLE(dataSize)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            let value = Int16((clipped * Float(Int16.max)).rounded())
            data.appendLE(UInt16(bitPattern: value))
        }
        try data.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) { append(contentsOf: value.utf8) }
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
