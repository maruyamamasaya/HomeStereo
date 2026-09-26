import AppKit
@preconcurrency import AVFoundation
import CoreServices
import Foundation
import Network
#if canImport(HomeStereoKit)
import HomeStereoKit
#endif
import UniformTypeIdentifiers

public struct RendererDiscoveryService: RendererDiscovering {
    public init() {}
    public func discover() async throws -> [SSDPResponse] {
        try await Task.detached { try SSDPDiscovery.discover() }.value
    }
}

public struct DeviceDescriptionService: DeviceDescriptionLoading {
    public init() {}
    public func load(from url: URL) async throws -> MediaRenderer {
        try await DeviceDescriptionLoader.load(from: url)
    }
}

@MainActor
public final class MediaFileSelectionService: MediaFileSelecting {
    public init() {}

    public func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "SRS-HG1へ配信する音源を1つ選択してください。"
        panel.allowedContentTypes = [
            .mp3, .mpeg4Audio, .wav, .aiff,
            UTType(filenameExtension: "aac"),
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "alac"),
        ].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func beginAccessing(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    public func stopAccessing(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

public final class LocalMediaHTTPServerSession: MediaServerSession, @unchecked Sendable {
    private let server: TrackHTTPServer
    public var trackURL: URL { server.trackURL }
    public var mimeType: String { server.mimeType }

    init(server: TrackHTTPServer) { self.server = server }
    public func stop() { server.stop() }
}

public struct LocalMediaHTTPServerFactory: MediaServerCreating {
    public init() {}

    public func start(fileURL: URL, rendererAddress: String) throws -> any MediaServerSession {
        let localAddress = try resolveLocalAddress(reaching: rendererAddress)
        let server = try TrackHTTPServer(fileURL: fileURL, host: localAddress)
        try server.start()
        return LocalMediaHTTPServerSession(server: server)
    }

    public func startStereoPair(
        leftFileURL: URL,
        leftRendererAddress: String,
        rightFileURL: URL,
        rightRendererAddress: String
    ) throws -> (left: any MediaServerSession, right: any MediaServerSession) {
        let gate = TrackHTTPStartGate(participants: ["left", "right"], timeout: 2)
        let leftHost = try resolveLocalAddress(reaching: leftRendererAddress)
        let rightHost = try resolveLocalAddress(reaching: rightRendererAddress)
        let leftServer = try TrackHTTPServer(
            fileURL: leftFileURL, host: leftHost,
            startGate: gate, startGateParticipant: "left"
        )
        try leftServer.start()
        do {
            let rightServer = try TrackHTTPServer(
                fileURL: rightFileURL, host: rightHost,
                startGate: gate, startGateParticipant: "right"
            )
            try rightServer.start()
            return (
                LocalMediaHTTPServerSession(server: leftServer),
                LocalMediaHTTPServerSession(server: rightServer)
            )
        } catch {
            leftServer.stop()
            throw error
        }
    }

    private func resolveLocalAddress(reaching rendererAddress: String) throws -> String {
        var lastError: Error?
        for attempt in 0..<4 {
            do {
                return try LANAddressResolver.address(reaching: rendererAddress)
            } catch {
                lastError = error
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.15) }
            }
        }
        throw lastError ?? HomeStereoError.noLANAddress(rendererAddress)
    }
}

public struct AVFoundationStereoMediaPreparer: StereoMediaPreparing {
    public init() {}

    public func prepareSynchronizationCheck(options: StereoPreparationOptions) async throws -> StereoMediaFiles {
        let sourceURL = try await Task.detached(priority: .userInitiated) {
            try Self.makeSynchronizationCheckSource()
        }.value
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        return try await prepare(fileURL: sourceURL, options: options)
    }

    public func prepare(fileURL: URL, options: StereoPreparationOptions) async throws -> StereoMediaFiles {
        try await Task.detached(priority: .userInitiated) {
            let input = try AVAudioFile(forReading: fileURL)
            let inputFormat = input.processingFormat
            let outputSampleRate = options.outputQuality == .stable48kHz ? 48_000 : inputFormat.sampleRate
            let outputBitDepth = options.outputQuality == .stable48kHz ? 16 : 24
            let appliedDelayMilliseconds = options.appliedDelayMilliseconds(
                forOutputSampleRate: outputSampleRate
            )
            guard inputFormat.commonFormat == .pcmFormatFloat32,
                  inputFormat.channelCount > 0,
                  let workingFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: outputSampleRate,
                    channels: inputFormat.channelCount,
                    interleaved: false
                  ),
                  let monoFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: outputSampleRate,
                    channels: 1,
                    interleaved: false
                  ) else {
                throw StereoMediaPreparationError.unsupportedFormat
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HomeStereo-Stereo", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let leftURL = directory.appendingPathComponent("left.wav")
            let rightURL = directory.appendingPathComponent("right.wav")
            do {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: outputSampleRate,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: outputBitDepth,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
                let leftFile = try AVAudioFile(
                    forWriting: leftURL, settings: settings,
                    commonFormat: .pcmFormatFloat32, interleaved: false
                )
                let rightFile = try AVAudioFile(
                    forWriting: rightURL, settings: settings,
                    commonFormat: .pcmFormatFloat32, interleaved: false
                )
                let inputCapacity: AVAudioFrameCount = 16_384
                let outputCapacity = AVAudioFrameCount(ceil(
                    Double(inputCapacity) * max(1, outputSampleRate / inputFormat.sampleRate)
                ) + 64)
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputCapacity),
                      let leftBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outputCapacity),
                      let rightBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outputCapacity) else {
                    throw StereoMediaPreparationError.cannotAllocateBuffer
                }
                let delayFrames = AVAudioFrameCount(
                    (appliedDelayMilliseconds / 1_000 * outputSampleRate).rounded()
                )
                if delayFrames > 0 {
                    let delayedFile = options.delayedChannel == .left ? leftFile : rightFile
                    try Self.writeSilence(frames: delayFrames, format: monoFormat, to: delayedFile)
                }
                let writeChannels: (AVAudioPCMBuffer) throws -> Void = { buffer in
                    let frames = buffer.frameLength
                    guard frames > 0,
                          let source = buffer.floatChannelData,
                          let left = leftBuffer.floatChannelData?[0],
                          let right = rightBuffer.floatChannelData?[0] else { return }
                    leftBuffer.frameLength = frames
                    rightBuffer.frameLength = frames
                    let sourceRightIndex = buffer.format.channelCount > 1 ? 1 : 0
                    let leftSourceIndex = options.swapsChannels ? sourceRightIndex : 0
                    let rightSourceIndex = options.swapsChannels ? 0 : sourceRightIndex
                    left.update(from: source[Int(leftSourceIndex)], count: Int(frames))
                    right.update(from: source[Int(rightSourceIndex)], count: Int(frames))
                    try leftFile.write(from: leftBuffer)
                    try rightFile.write(from: rightBuffer)
                }
                if abs(outputSampleRate - inputFormat.sampleRate) < 0.5 {
                    while input.framePosition < input.length {
                        try input.read(into: inputBuffer, frameCount: inputCapacity)
                        try writeChannels(inputBuffer)
                    }
                } else {
                    guard let converter = AVAudioConverter(from: inputFormat, to: workingFormat),
                          let outputBuffer = AVAudioPCMBuffer(
                            pcmFormat: workingFormat,
                            frameCapacity: outputCapacity
                          ) else {
                        throw StereoMediaPreparationError.cannotCreateConverter
                    }
                    while input.framePosition < input.length {
                        try input.read(into: inputBuffer, frameCount: inputCapacity)
                        guard inputBuffer.frameLength > 0 else { break }
                        outputBuffer.frameLength = 0
                        let chunkState = StereoConverterChunkState()
                        var conversionError: NSError?
                        let status = converter.convert(to: outputBuffer, error: &conversionError) {
                            _, inputStatus in
                            guard !chunkState.suppliedInput else {
                                inputStatus.pointee = .noDataNow
                                return nil
                            }
                            chunkState.suppliedInput = true
                            inputStatus.pointee = .haveData
                            return inputBuffer
                        }
                        if let conversionError { throw conversionError }
                        guard status != .error else {
                            throw StereoMediaPreparationError.cannotCreateConverter
                        }
                        if outputBuffer.frameLength > 0 { try writeChannels(outputBuffer) }
                    }
                    outputBuffer.frameLength = 0
                    var drainError: NSError?
                    let drainStatus = converter.convert(to: outputBuffer, error: &drainError) {
                        _, inputStatus in
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    if let drainError { throw drainError }
                    guard drainStatus != .error else {
                        throw StereoMediaPreparationError.cannotCreateConverter
                    }
                    if outputBuffer.frameLength > 0 { try writeChannels(outputBuffer) }
                }
                if delayFrames > 0 {
                    let undelayedFile = options.delayedChannel == .left ? rightFile : leftFile
                    try Self.writeSilence(frames: delayFrames, format: monoFormat, to: undelayedFile)
                }
                return StereoMediaFiles(
                    leftURL: leftURL,
                    rightURL: rightURL,
                    sourceSampleRate: inputFormat.sampleRate,
                    appliedDelayMilliseconds: appliedDelayMilliseconds
                )
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }.value
    }

    public func remove(_ files: StereoMediaFiles) {
        try? FileManager.default.removeItem(at: files.leftURL.deletingLastPathComponent())
    }

    private static func writeSilence(
        frames: AVAudioFrameCount,
        format: AVAudioFormat,
        to file: AVAudioFile
    ) throws {
        let chunkCapacity: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity),
              let samples = buffer.floatChannelData?[0] else {
            throw StereoMediaPreparationError.cannotAllocateBuffer
        }
        samples.initialize(repeating: 0, count: Int(chunkCapacity))
        var remaining = frames
        while remaining > 0 {
            buffer.frameLength = min(remaining, chunkCapacity)
            try file.write(from: buffer)
            remaining -= buffer.frameLength
        }
    }

    private static func makeSynchronizationCheckSource() throws -> URL {
        let sampleRate = 48_000.0
        let duration = StereoPreparationOptions.synchronizationCheckDuration
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeStereo-SyncCheck", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("synchronization-check.wav")
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
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
            ) else { throw StereoMediaPreparationError.unsupportedFormat }
            let frameCount = AVAudioFrameCount((sampleRate * duration).rounded())
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let channels = buffer.floatChannelData else {
                throw StereoMediaPreparationError.cannotAllocateBuffer
            }
            buffer.frameLength = frameCount
            channels[0].initialize(repeating: 0, count: Int(frameCount))
            channels[1].initialize(repeating: 0, count: Int(frameCount))

            // Three identical broadband ticks followed by a pause. Correct alignment
            // sounds centered and tight; an offset spreads or splits every tick.
            let clickTimes = (0..<8).flatMap { group in
                let start = Double(group) * 2
                return [start + 0.5, start + 1.0, start + 1.5]
            }
            let clickFrames = Int(sampleRate * 0.008)
            let peak = Float(pow(10, -18.0 / 20.0))
            for clickTime in clickTimes {
                let start = Int((clickTime * sampleRate).rounded())
                var noiseState: UInt32 = 0x9E37_79B9 ^ UInt32(start)
                for offset in 0..<clickFrames where start + offset < Int(frameCount) {
                    noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
                    let noise = Float(Int32(bitPattern: noiseState)) / Float(Int32.max)
                    let phase = Double(offset) / Double(max(1, clickFrames - 1))
                    let envelope = Float(0.5 - 0.5 * cos(2 * Double.pi * phase))
                    let sample = noise * envelope * peak
                    channels[0][start + offset] = sample
                    channels[1][start + offset] = sample
                }
            }
            try file.write(from: buffer)
            return url
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}

private final class StereoConverterChunkState: @unchecked Sendable {
    var suppliedInput = false
}

private enum StereoMediaPreparationError: LocalizedError {
    case unsupportedFormat
    case cannotAllocateBuffer
    case cannotCreateConverter

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "この音源をステレオ分離できませんでした。別の音源形式を試してください。"
        case .cannotAllocateBuffer: "ステレオ分離用の音声バッファを作成できませんでした。"
        case .cannotCreateConverter: "音源を同期優先の48kHz PCMへ変換できませんでした。"
        }
    }
}

public actor UPnPRendererController: RendererControlling {
    private let controller = UPnPController()
    public init() {}

    public func setURI(service: UPnPService, uri: URL, metadata: String) async throws {
        try await controller.setAVTransportURI(service: service, uri: uri, metadata: metadata)
    }
    public func play(service: UPnPService) async throws { try await controller.play(service: service) }
    public func pause(service: UPnPService) async throws { try await controller.pause(service: service) }
    public func stop(service: UPnPService) async throws { try await controller.stop(service: service) }
    public func seek(service: UPnPService, position: TimeInterval) async throws { try await controller.seek(service: service, position: position) }
    public func transportInfo(service: UPnPService) async throws -> TransportInfo { try await controller.getTransportInfo(service: service) }
    public func positionInfo(service: UPnPService) async throws -> PositionInfo { try await controller.getPositionInfo(service: service) }
    public func volume(service: UPnPService) async throws -> UInt8 { try await controller.getVolume(service: service) }
    public func setVolume(service: UPnPService, volume: UInt8) async throws { try await controller.setVolume(service: service, volume: volume) }
}

@MainActor
public final class PlaylistFileService: PlaylistFileServicing {
    public init() {}
    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [UTType(filenameExtension: "m3u8")].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }
    public func chooseExportURL(defaultName: String) -> URL? {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "\(defaultName).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8")].compactMap { $0 }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
public final class MacSystemEventMonitor: SystemEventMonitoring {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "HomeStereo.NetworkMonitor")
    private var observers: [NSObjectProtocol] = []
    private var handler: (@MainActor (SystemPlaybackEvent) -> Void)?

    public init() {}

    public func start(_ handler: @escaping @MainActor (SystemPlaybackEvent) -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in handler(.willSleep) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in handler(.didWake) }
            }
        ]
        pathMonitor.pathUpdateHandler = { path in
            Task { @MainActor in handler(.networkAvailable(path.status == .satisfied)) }
        }
        pathMonitor.start(queue: queue)
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers = []
        pathMonitor.cancel()
        handler = nil
    }
}

@MainActor
public final class FolderChangeMonitor: FolderChangeMonitoring {
    private final class CallbackBox {
        let folderID: UUID
        let handler: @MainActor (UUID) -> Void
        init(folderID: UUID, handler: @escaping @MainActor (UUID) -> Void) { self.folderID = folderID; self.handler = handler }
    }
    private struct Registration { let stream: FSEventStreamRef; let box: Unmanaged<CallbackBox> }
    private var registrations: [Registration] = []

    public init() {}

    public func watch(_ folders: [UUID: URL], handler: @escaping @MainActor (UUID) -> Void) {
        stop()
        for (id, url) in folders {
            let box = Unmanaged.passRetained(CallbackBox(folderID: id, handler: handler))
            var context = FSEventStreamContext(
                version: 0, info: box.toOpaque(), retain: nil, release: nil, copyDescription: nil
            )
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
                Task { @MainActor in box.handler(box.folderID) }
            }
            guard let stream = FSEventStreamCreate(
                nil, callback, &context, [url.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.75,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
            ) else { box.release(); continue }
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
            registrations.append(Registration(stream: stream, box: box))
        }
    }

    public func stop() {
        for value in registrations {
            FSEventStreamStop(value.stream)
            FSEventStreamInvalidate(value.stream)
            FSEventStreamRelease(value.stream)
            value.box.release()
        }
        registrations = []
    }

}

@MainActor
public final class BackupFileService: BackupFileServicing {
    public init() {}
    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
    public func chooseExportURL() -> URL? {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "HomeStereo-Backup.json"; panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

@MainActor
public final class MyMusicFileService: MyMusicFileServicing {
    public init() {}

    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func chooseExportURL(defaultFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultFileName; panel.allowedContentTypes = [.json]
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func read(from url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
public final class DiagnosticExportService {
    public init() {}

    public func export(_ data: Data) throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HomeStereo-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

public final class MacPlaybackActivityManager: PlaybackActivityManaging {
    private var token: NSObjectProtocol?

    public init() {}

    @MainActor
    public func setPlaybackActive(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled, .userInitiated],
                reason: "DLNA music playback"
            )
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
