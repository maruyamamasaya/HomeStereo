import AudioToolbox
import AVFoundation
import Foundation

public enum AudioInputAuthorization {
    public static var status: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "notDetermined"
        @unknown default: "unknown"
        }
    }
}

public struct AudioCaptureReport: Codable, Sendable {
    public let generatedAt: Date
    public let device: AudioInputDevice
    public let hardwareSampleRate: Double
    public let inputBitDepth: Int
    public let inputChannelCount: Int
    public let requestedBufferFrames: UInt32
    public let actualBufferFrames: UInt32
    public let leftChannel: Int
    public let rightChannel: Int
    public let capturedFrames: Int
    public let segments: [StereoSegmentSummary]
}

private final class CaptureContext: @unchecked Sendable {
    let audioUnit: AudioUnit
    let audioBufferList: UnsafeMutablePointer<AudioBufferList>
    let bufferCapacityFrames: Int
    let leftChannel: Int
    let rightChannel: Int
    let writer: StereoSegmentWriter
    let processingQueue = DispatchQueue(label: "SonyStereoBridgeAudio.segment-writer")
    let stateLock = NSLock()
    var capturedFrames = 0
    var processingError: Error?

    init(
        audioUnit: AudioUnit,
        channelCount: Int,
        bufferCapacityFrames: Int,
        leftChannel: Int,
        rightChannel: Int,
        writer: StereoSegmentWriter
    ) {
        self.audioUnit = audioUnit
        self.bufferCapacityFrames = bufferCapacityFrames
        self.leftChannel = leftChannel
        self.rightChannel = rightChannel
        self.writer = writer
        let byteCount = MemoryLayout<AudioBufferList>.size
            + max(0, channelCount - 1) * MemoryLayout<AudioBuffer>.size
        audioBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<AudioBufferList>.alignment
        ).assumingMemoryBound(to: AudioBufferList.self)
        audioBufferList.pointee.mNumberBuffers = UInt32(channelCount)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for index in buffers.indices {
            buffers[index].mNumberChannels = 1
            buffers[index].mDataByteSize = UInt32(bufferCapacityFrames * MemoryLayout<Float>.size)
            buffers[index].mData = UnsafeMutableRawPointer.allocate(
                byteCount: bufferCapacityFrames * MemoryLayout<Float>.size,
                alignment: MemoryLayout<Float>.alignment
            )
        }
    }

    deinit {
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            buffer.mData?.deallocate()
        }
        audioBufferList.deallocate()
    }

    func receive(
        frames: UInt32,
        flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        time: UnsafePointer<AudioTimeStamp>
    ) -> OSStatus {
        guard frames <= bufferCapacityFrames else {
            stateLock.withLock {
                processingError = AudioCaptureError("Audio callback exceeded buffer capacity: \(frames) > \(bufferCapacityFrames)")
            }
            return kAudio_ParamError
        }
        let status = AudioUnitRender(audioUnit, flags, time, 1, frames, audioBufferList)
        guard status == noErr else { return status }
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard let leftData = buffers[leftChannel - 1].mData?.assumingMemoryBound(to: Float.self),
              let rightData = buffers[rightChannel - 1].mData?.assumingMemoryBound(to: Float.self) else {
            return kAudio_ParamError
        }
        let count = Int(frames)
        let left = Array(UnsafeBufferPointer(start: leftData, count: count))
        let right = Array(UnsafeBufferPointer(start: rightData, count: count))
        processingQueue.async { [self] in
            do {
                try writer.append(left: left, right: right)
                stateLock.withLock { capturedFrames += count }
            } catch {
                stateLock.withLock { processingError = error }
            }
        }
        return noErr
    }
}

private let audioInputCallback: AURenderCallback = { reference, flags, time, _, frames, _ in
    let context = Unmanaged<CaptureContext>.fromOpaque(reference).takeUnretainedValue()
    return context.receive(frames: frames, flags: flags, time: time)
}

public final class BlackHoleSegmentCapture {
    public init() {}

    public func capture(
        device: AudioInputDevice,
        outputDirectory: URL,
        duration: TimeInterval,
        segmentSeconds: TimeInterval,
        leftChannel: Int,
        rightChannel: Int,
        bufferFrames: UInt32
    ) throws -> AudioCaptureReport {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioCaptureError(
                "Audio input permission is \(AudioInputAuthorization.status). "
                    + "Allow the terminal or Codex host in System Settings > Privacy & Security > Microphone, then retry."
            )
        }
        guard duration > 0, segmentSeconds > 0 else {
            throw AudioCaptureError("Capture duration and segment duration must be positive")
        }
        guard leftChannel >= 1, rightChannel >= 1,
              leftChannel <= device.inputChannels, rightChannel <= device.inputChannels else {
            throw AudioCaptureError("Channel mapping is outside the device's 1...\(device.inputChannels) input channels")
        }

        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioCaptureError("AUHAL audio component is unavailable")
        }
        var optionalUnit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &optionalUnit), operation: "create AUHAL instance")
        guard let audioUnit = optionalUnit else { throw AudioCaptureError("AUHAL instance was empty") }
        defer { AudioComponentInstanceDispose(audioUnit) }

        var enabled: UInt32 = 1
        try check(AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
            &enabled, UInt32(MemoryLayout<UInt32>.size)
        ), operation: "enable AUHAL input")
        var disabled: UInt32 = 0
        try check(AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
            &disabled, UInt32(MemoryLayout<UInt32>.size)
        ), operation: "disable AUHAL output")
        var deviceID = device.id
        try check(AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size)
        ), operation: "select AUHAL input device")

        var hardwareFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioUnitGetProperty(
            audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
            &hardwareFormat, &formatSize
        ), operation: "read AUHAL hardware format")
        let channelCount = Int(hardwareFormat.mChannelsPerFrame)
        guard channelCount >= max(leftChannel, rightChannel) else {
            throw AudioCaptureError("Selected AUHAL format exposes only \(channelCount) channels")
        }
        let sampleRate = hardwareFormat.mSampleRate
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try check(AudioUnitSetProperty(
            audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
            &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ), operation: "set AUHAL client format")

        let writer = try StereoSegmentWriter(
            outputDirectory: outputDirectory,
            sampleRate: Int(sampleRate.rounded()),
            segmentSeconds: segmentSeconds
        )
        let capacity = max(Int(bufferFrames), Int(device.bufferFrameSize))
        let context = CaptureContext(
            audioUnit: audioUnit,
            channelCount: channelCount,
            bufferCapacityFrames: capacity,
            leftChannel: leftChannel,
            rightChannel: rightChannel,
            writer: writer
        )
        var callback = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(context).toOpaque()
        )
        try check(AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
            &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        ), operation: "install AUHAL input callback")
        try check(AudioUnitInitialize(audioUnit), operation: "initialize AUHAL")
        defer { AudioUnitUninitialize(audioUnit) }
        try check(AudioOutputUnitStart(audioUnit), operation: "start AUHAL input")
        Thread.sleep(forTimeInterval: duration)
        AudioOutputUnitStop(audioUnit)
        context.processingQueue.sync {}
        if let error = context.stateLock.withLock({ context.processingError }) { throw error }
        // A very short callback tail is not useful as a standalone Renderer track and can click.
        try writer.finish(includePartialSegment: false)

        return AudioCaptureReport(
            generatedAt: .now,
            device: device,
            hardwareSampleRate: sampleRate,
            inputBitDepth: 32,
            inputChannelCount: channelCount,
            requestedBufferFrames: bufferFrames,
            actualBufferFrames: device.bufferFrameSize,
            leftChannel: leftChannel,
            rightChannel: rightChannel,
            capturedFrames: context.stateLock.withLock { context.capturedFrames },
            segments: writer.summaries
        )
    }
}
