import AudioToolbox
import CoreAudio
import Foundation

public struct AudioInputDevice: Codable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let inputChannels: Int
    public let nominalSampleRate: Double
    public let bufferFrameSize: UInt32
    public let inputLatencyFrames: UInt32

    public var inputLatencyMilliseconds: Double {
        guard nominalSampleRate > 0 else { return 0 }
        return Double(inputLatencyFrames) / nominalSampleRate * 1_000
    }
}

public enum AudioDeviceDiscovery {
    public static func inputDevices() throws -> [AudioInputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var byteCount: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount
        ), operation: "read audio device list size")
        guard byteCount > 0 else { return [] }

        var ids = [AudioDeviceID](
            repeating: 0,
            count: Int(byteCount) / MemoryLayout<AudioDeviceID>.size
        )
        try check(AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &byteCount, &ids
        ), operation: "read audio device list")

        return try ids.compactMap { id in
            let channels = try channelCount(deviceID: id, scope: kAudioDevicePropertyScopeInput)
            guard channels > 0 else { return nil }
            return AudioInputDevice(
                id: id,
                name: try stringProperty(id, selector: kAudioObjectPropertyName),
                uid: try stringProperty(id, selector: kAudioDevicePropertyDeviceUID),
                inputChannels: channels,
                nominalSampleRate: try doubleProperty(id, selector: kAudioDevicePropertyNominalSampleRate),
                bufferFrameSize: try uint32Property(id, selector: kAudioDevicePropertyBufferFrameSize),
                inputLatencyFrames: try uint32Property(
                    id,
                    selector: kAudioDevicePropertyLatency,
                    scope: kAudioDevicePropertyScopeInput
                )
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func select(_ selector: String, from devices: [AudioInputDevice]) throws -> AudioInputDevice {
        if let exact = devices.first(where: {
            $0.uid.localizedCaseInsensitiveCompare(selector) == .orderedSame
                || $0.name.localizedCaseInsensitiveCompare(selector) == .orderedSame
        }) {
            return exact
        }
        let matches = devices.filter {
            $0.uid.localizedCaseInsensitiveContains(selector)
                || $0.name.localizedCaseInsensitiveContains(selector)
        }
        guard matches.count == 1, let match = matches.first else {
            let names = devices.map { "\($0.name) [\($0.uid)]" }.joined(separator: ", ")
            if matches.isEmpty {
                throw AudioCaptureError("No input device matched '\(selector)'. Available: \(names.isEmpty ? "none" : names)")
            }
            throw AudioCaptureError("Input device selector '\(selector)' is ambiguous")
        }
        return match
    }

    private static func stringProperty(_ id: AudioObjectID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value), operation: "read audio device text property")
        guard let value else { throw AudioCaptureError("Audio device text property was empty") }
        return value.takeUnretainedValue() as String
    }

    private static func doubleProperty(
        _ id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return 0 }
        var value = Double.zero
        var size = UInt32(MemoryLayout<Double>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value), operation: "read audio device numeric property")
        return value
    }

    private static func uint32Property(
        _ id: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return 0 }
        var value = UInt32.zero
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value), operation: "read audio device numeric property")
        return value
    }

    private static func channelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size), operation: "read stream configuration size")
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, memory), operation: "read stream configuration")
        let list = UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

func check(_ status: OSStatus, operation: String) throws {
    guard status == noErr else {
        throw AudioCaptureError("\(operation) failed (OSStatus \(status))")
    }
}

public struct AudioCaptureError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
