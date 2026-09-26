import Foundation
import Testing
@testable import SonyStereoBridgeAudio

@Test func segmentWriterKeepsLeftAndRightOnOneTimeline() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sony-stereo-segments-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try StereoSegmentWriter(outputDirectory: directory, sampleRate: 10, segmentSeconds: 1)

    try writer.append(left: Array(repeating: 0.25, count: 7), right: Array(repeating: -0.5, count: 7))
    try writer.append(left: Array(repeating: 0.25, count: 8), right: Array(repeating: -0.5, count: 8))
    try writer.finish()

    #expect(writer.summaries.map(\.frames) == [10, 5])
    #expect(writer.summaries.allSatisfy { FileManager.default.fileExists(atPath: $0.leftPath) })
    #expect(writer.summaries.allSatisfy { FileManager.default.fileExists(atPath: $0.rightPath) })
    #expect(abs(writer.summaries[0].leftPeakDBFS - -12.041) < 0.01)
    #expect(abs(writer.summaries[0].rightPeakDBFS - -6.0206) < 0.01)
}

@Test func segmentWriterRejectsMismatchedTimelines() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sony-stereo-segments-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let writer = try StereoSegmentWriter(outputDirectory: directory, sampleRate: 48_000, segmentSeconds: 1)
    #expect(throws: AudioCaptureError.self) {
        try writer.append(left: [0, 0], right: [0])
    }
}

@Test func capturePlaybackPlanLoadsOrderedSafeSegments() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sony-stereo-playback-plan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let leftOne = directory.appendingPathComponent("segment-left-0001.wav")
    let rightOne = directory.appendingPathComponent("segment-right-0001.wav")
    let leftTwo = directory.appendingPathComponent("segment-left-0002.wav")
    let rightTwo = directory.appendingPathComponent("segment-right-0002.wav")
    for url in [leftOne, rightOne, leftTwo, rightTwo] { try Data("wav".utf8).write(to: url) }
    let report = captureReport(segments: [
        StereoSegmentSummary(segment: 2, frames: 48_000, leftPath: leftTwo.path, rightPath: rightTwo.path, leftPeakDBFS: -18, rightPeakDBFS: -20),
        StereoSegmentSummary(segment: 1, frames: 96_000, leftPath: leftOne.path, rightPath: rightOne.path, leftPeakDBFS: -12, rightPeakDBFS: -14),
    ])
    let reportURL = directory.appendingPathComponent("report.json")
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(report).write(to: reportURL)

    let plan = try CapturePlaybackPlan.load(reportURL: reportURL)

    #expect(plan.segments.map(\.number) == [1, 2])
    #expect(plan.segments.map(\.duration) == [2, 1])
    #expect(plan.maximumPeakDBFS == -12)
}

@Test func capturePlaybackPlanRejectsSilentAndUnsafeReports() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sony-stereo-playback-safety-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let left = directory.appendingPathComponent("left.wav")
    let right = directory.appendingPathComponent("right.wav")
    try Data("wav".utf8).write(to: left); try Data("wav".utf8).write(to: right)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601

    for (name, peak) in [("silent", -160.0), ("unsafe", -1.0)] {
        let report = captureReport(segments: [
            StereoSegmentSummary(segment: 1, frames: 48_000, leftPath: left.path, rightPath: right.path, leftPeakDBFS: peak, rightPeakDBFS: peak),
        ])
        let url = directory.appendingPathComponent("\(name).json")
        try encoder.encode(report).write(to: url)
        #expect(throws: AudioCaptureError.self) { try CapturePlaybackPlan.load(reportURL: url) }
    }

    let tiny = captureReport(segments: [
        StereoSegmentSummary(segment: 1, frames: 256, leftPath: left.path, rightPath: right.path, leftPeakDBFS: -20, rightPeakDBFS: -20),
    ])
    let tinyURL = directory.appendingPathComponent("tiny.json")
    try encoder.encode(tiny).write(to: tinyURL)
    #expect(throws: AudioCaptureError.self) { try CapturePlaybackPlan.load(reportURL: tinyURL) }
}

private func captureReport(segments: [StereoSegmentSummary]) -> AudioCaptureReport {
    AudioCaptureReport(
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
        device: AudioInputDevice(
            id: 1, name: "BlackHole 2ch", uid: "BlackHole2ch_UID", inputChannels: 2,
            nominalSampleRate: 48_000, bufferFrameSize: 512, inputLatencyFrames: 0
        ),
        hardwareSampleRate: 48_000,
        inputBitDepth: 32,
        inputChannelCount: 2,
        requestedBufferFrames: 1_024,
        actualBufferFrames: 512,
        leftChannel: 1,
        rightChannel: 2,
        capturedFrames: segments.reduce(0) { $0 + $1.frames },
        segments: segments
    )
}
