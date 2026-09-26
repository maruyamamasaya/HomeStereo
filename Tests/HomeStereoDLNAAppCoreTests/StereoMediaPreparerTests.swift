import AVFoundation
import Foundation
import Testing
@testable import HomeStereoDLNAAppCore

@Test
func stable48kHzIsTheDefaultStereoOutputQuality() {
    let options = StereoPreparationOptions(
        swapsChannels: false,
        delayedChannel: .left,
        delayMilliseconds: 0
    )
    #expect(options.outputQuality == .stable48kHz)
}

@Test
func stereoDelayUsesIndependentSampleRateFamilyBases() {
    let options = StereoPreparationOptions(
        swapsChannels: false,
        delayedChannel: .left,
        delayMilliseconds: 105,
        automaticSampleRateDelay: true,
        delayPerRateStepMilliseconds: 10,
        delay44_1kHzMilliseconds: 91
    )

    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 44_100) == 91)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 48_000) == 105)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 88_200) == 101)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 96_000) == 115)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 176_400) == 111)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 192_000) == 125)
}

@Test
func standardStereoDelayUsesCalibratedFamilyBasesAndRateSteps() {
    #expect(StereoPreparationOptions.calibrated44_1kHzDelay(for48kHzBase: 108) == 99)
    #expect(abs(StereoPreparationOptions.calibrated44_1kHzDelay(for48kHzBase: 109) - 99.9) < 0.0001)
    let options = StereoPreparationOptions(
        swapsChannels: false,
        delayedChannel: .left,
        delayMilliseconds: StereoPreparationOptions.standard48kHzDelayMilliseconds,
        automaticSampleRateDelay: true,
        delay44_1kHzMilliseconds: StereoPreparationOptions.standard44_1kHzDelayMilliseconds
    )

    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 44_100) == 99)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 48_000) == 108)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 88_200) == 207)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 96_000) == 216)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 176_400) == 315)
    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 192_000) == 324)
}

@Test
func stableOutputUses48kHzBaseDelay() {
    let options = StereoPreparationOptions(
        swapsChannels: false,
        delayedChannel: .left,
        delayMilliseconds: 105,
        outputQuality: .stable48kHz,
        automaticSampleRateDelay: true,
        delayPerRateStepMilliseconds: 10,
        delay44_1kHzMilliseconds: 91
    )

    #expect(options.appliedDelayMilliseconds(forOutputSampleRate: 48_000) == 105)
}

@Test(arguments: [44_100.0, 48_000.0, 88_200.0, 96_000.0, 192_000.0])
func stableOutputConvertsCommonSourceRatesTo48kHz(sourceRate: Double) async throws {
    let inputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("HomeStereo-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: inputURL) }

    try writeStereoTone(to: inputURL, sampleRate: sourceRate, duration: 0.25)
    let preparer = AVFoundationStereoMediaPreparer()
    let files = try await preparer.prepare(
        fileURL: inputURL,
        options: StereoPreparationOptions(
            swapsChannels: false,
            delayedChannel: .right,
            delayMilliseconds: 0,
            outputQuality: .stable48kHz,
            automaticSampleRateDelay: true
        )
    )
    defer { preparer.remove(files) }

    for outputURL in [files.leftURL, files.rightURL] {
        let output = try AVAudioFile(forReading: outputURL)
        #expect(abs(output.processingFormat.sampleRate - 48_000) < 0.5)
        #expect(output.length > 11_000)
        #expect(output.length < 13_000)
    }
}

@Test
func synchronizationCheckProducesIdenticalClicksWithConfiguredDelay() async throws {
    let delayMilliseconds = 25.0
    let preparer = AVFoundationStereoMediaPreparer()
    let files = try await preparer.prepareSynchronizationCheck(options: StereoPreparationOptions(
        swapsChannels: false,
        delayedChannel: .right,
        delayMilliseconds: delayMilliseconds
    ))
    defer { preparer.remove(files) }

    let left = try AVAudioFile(forReading: files.leftURL)
    let right = try AVAudioFile(forReading: files.rightURL)
    #expect(abs(left.processingFormat.sampleRate - 48_000) < 0.5)
    #expect(abs(right.processingFormat.sampleRate - 48_000) < 0.5)
    #expect(left.length == right.length)
    #expect(left.length == AVAudioFramePosition(16 * 48_000 + 1_200))
    #expect(files.appliedDelayMilliseconds == delayMilliseconds)

    let leftFirstClick = try firstAudibleFrame(in: left)
    let rightFirstClick = try firstAudibleFrame(in: right)
    #expect(rightFirstClick - leftFirstClick == AVAudioFramePosition(1_200))
    let peak = try maximumAbsoluteSample(in: left)
    #expect(peak > 0.11)
    #expect(peak < 0.14)
}

private func maximumAbsoluteSample(in file: AVAudioFile) throws -> Float {
    file.framePosition = 0
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.length)
    ) else { return 0 }
    try file.read(into: buffer)
    guard let samples = buffer.floatChannelData?[0] else { return 0 }
    return (0..<Int(buffer.frameLength)).reduce(Float.zero) { maximum, index in
        max(maximum, abs(samples[index]))
    }
}

private func writeStereoTone(to url: URL, sampleRate: Double, duration: Double) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 24,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(
        forWriting: url,
        settings: settings,
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
    ) else {
        Issue.record("Could not create test audio format")
        return
    }
    let frameCount = AVAudioFrameCount((sampleRate * duration).rounded())
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
          let channels = buffer.floatChannelData else {
        Issue.record("Could not create test audio buffer")
        return
    }
    buffer.frameLength = frameCount
    for frame in 0 ..< Int(frameCount) {
        let sample = Float(sin(2 * Double.pi * 440 * Double(frame) / sampleRate) * 0.1)
        channels[0][frame] = sample
        channels[1][frame] = sample
    }
    try file.write(from: buffer)
}

private func firstAudibleFrame(in file: AVAudioFile) throws -> AVAudioFramePosition {
    let capacity = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity),
          let samples = buffer.floatChannelData?[0] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    try file.read(into: buffer)
    for index in 0..<Int(buffer.frameLength) where abs(samples[index]) > 0.000_01 {
        return AVAudioFramePosition(index)
    }
    throw CocoaError(.fileReadCorruptFile)
}
