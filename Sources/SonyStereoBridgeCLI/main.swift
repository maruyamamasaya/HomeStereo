import Foundation
import HomeStereoKit
import SonyStereoBridgeAudio

@main
struct SonyStereoBridgeCommand {
    static func main() async {
        do {
            let options = try Options.parse(CommandLine.arguments)
            switch options.command {
            case "probe":
                try await writeProbe(options: options)
            case "audio-probe":
                try writeAudioProbe(options: options)
            case "capture-segments":
                try captureSegments(options: options)
            case "play-one":
                try await playOne(options: options)
            case "play-pair":
                try await playPair(options: options)
            case "play-capture":
                try await playCapture(options: options)
            case "prepare-pair":
                try await preparePair(options: options)
            case "pause-pair":
                try await pausePair(options: options)
            case "stop-pair":
                try await stopPair(options: options)
            default:
                throw CLIError(Options.usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func writeAudioProbe(options: Options) throws {
        let report = AudioProbeReport(
            generatedAt: .now,
            audioInputAuthorization: AudioInputAuthorization.status,
            devices: try AudioDeviceDiscovery.inputDevices()
        )
        try writeJSON(report, outputPath: options.outputPath)
    }

    private static func captureSegments(options: Options) throws {
        guard let selector = options.audioDevice, let outputDirectory = options.outputDirectory else {
            throw CLIError("capture-segments requires --device and --output-dir")
        }
        let devices = try AudioDeviceDiscovery.inputDevices()
        let device = try AudioDeviceDiscovery.select(selector, from: devices)
        log("Audio input=\(device.name) uid=\(device.uid) channels=\(device.inputChannels)")
        log("Capture only: no HTTP server, UPnP command, or speaker volume change")
        let report = try BlackHoleSegmentCapture().capture(
            device: device,
            outputDirectory: URL(fileURLWithPath: outputDirectory),
            duration: options.captureDuration,
            segmentSeconds: options.segmentSeconds,
            leftChannel: options.leftChannel,
            rightChannel: options.rightChannel,
            bufferFrames: UInt32(options.bufferFrames)
        )
        for segment in report.segments {
            log("segment=\(segment.segment) frames=\(segment.frames) LEFT=\(String(format: "%.1f", segment.leftPeakDBFS))dBFS RIGHT=\(String(format: "%.1f", segment.rightPeakDBFS))dBFS")
        }
        try writeJSON(report, outputPath: options.outputPath)
    }

    private static func writeJSON<T: Encodable>(_ value: T, outputPath: String?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        if let outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            log("Report written to \(outputPath)")
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func writeProbe(options: Options) async throws {
        let report = try await probe(timeout: options.timeout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        if let outputPath = options.outputPath {
            try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            print("[Bridge] Probe report written to \(outputPath)")
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func playOne(options: Options) async throws {
        guard let selector = options.renderer, let filePath = options.filePath else {
            throw CLIError("play-one requires --renderer and --file")
        }
        let fileURL = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CLIError("Audio file does not exist: \(fileURL.path)")
        }
        let discovered = try await renderers(timeout: options.timeout)
        guard let selected = discovered.first(where: {
            $0.renderer.modelName.localizedCaseInsensitiveCompare(selector) == .orderedSame
                || $0.renderer.friendlyName.localizedCaseInsensitiveCompare(selector) == .orderedSame
        }) else {
            throw CLIError("No renderer matched model or friendly name: \(selector)")
        }
        guard let avTransport = selected.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }
        let localAddress = try LANAddressResolver.address(reaching: selected.response.sourceAddress)
        let server = try TrackHTTPServer(fileURL: fileURL, host: localAddress)
        try server.start(preferredPort: options.httpPort)
        defer { server.stop() }

        let metadata = SOAPRequestBuilder.didlLiteMetadata(
            resourceURL: server.trackURL,
            mimeType: server.mimeType,
            title: fileURL.deletingPathExtension().lastPathComponent
        )
        let controller = UPnPController()
        log("Selected \(selected.renderer.friendlyName) (\(selected.renderer.modelName))")
        log("SetAVTransportURI sent")
        try await controller.setAVTransportURI(service: avTransport, uri: server.trackURL, metadata: metadata)
        log("Play sent")
        try await controller.play(service: avTransport)
        let deadline = Date().addingTimeInterval(options.hold)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(500))
            do {
                let transport = try await controller.getTransportInfo(service: avTransport)
                let position = try await controller.getPositionInfo(service: avTransport)
                log("state=\(transport.state) position=\(position.position.map { String(format: "%.3f", $0) } ?? "unknown")")
            } catch {
                log("status read failed: \(error.localizedDescription)")
            }
        }
    }

    private static func playPair(options: Options) async throws {
        guard let leftSelector = options.leftRenderer,
              let leftPath = options.leftFilePath,
              let rightSelector = options.rightRenderer,
              let rightPath = options.rightFilePath else {
            throw CLIError("play-pair requires --left, --left-file, --right, and --right-file")
        }
        let leftURL = URL(fileURLWithPath: leftPath)
        let rightURL = URL(fileURLWithPath: rightPath)
        guard FileManager.default.fileExists(atPath: leftURL.path),
              FileManager.default.fileExists(atPath: rightURL.path) else {
            throw CLIError("Both LEFT and RIGHT audio files must exist")
        }

        let discovered = try await renderers(timeout: options.timeout)
        let left = try selectedRenderer(leftSelector, from: discovered)
        let right = try selectedRenderer(rightSelector, from: discovered)
        guard left.renderer.udn != right.renderer.udn else {
            throw CLIError("LEFT and RIGHT must resolve to different renderers")
        }
        guard let leftTransport = left.renderer.avTransport,
              let rightTransport = right.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }

        let leftHost = try LANAddressResolver.address(reaching: left.response.sourceAddress)
        let rightHost = try LANAddressResolver.address(reaching: right.response.sourceAddress)
        let leftServer = try TrackHTTPServer(fileURL: leftURL, host: leftHost)
        let rightServer = try TrackHTTPServer(fileURL: rightURL, host: rightHost)
        try leftServer.start(preferredPort: options.httpPort)
        do {
            try rightServer.start(preferredPort: options.httpPort)
        } catch {
            leftServer.stop()
            throw error
        }
        defer {
            leftServer.stop()
            rightServer.stop()
        }

        let leftController = UPnPController()
        let rightController = UPnPController()
        if let volume = options.testVolume {
            try await setPairVolume(
                volume,
                left: left,
                right: right,
                leftController: leftController,
                rightController: rightController
            )
        }
        let leftMetadata = SOAPRequestBuilder.didlLiteMetadata(
            resourceURL: leftServer.trackURL,
            mimeType: leftServer.mimeType,
            title: leftURL.deletingPathExtension().lastPathComponent
        )
        let rightMetadata = SOAPRequestBuilder.didlLiteMetadata(
            resourceURL: rightServer.trackURL,
            mimeType: rightServer.mimeType,
            title: rightURL.deletingPathExtension().lastPathComponent
        )
        log("LEFT=\(left.renderer.friendlyName) (\(left.renderer.modelName)) delay=\(options.leftDelayMs)ms")
        log("RIGHT=\(right.renderer.friendlyName) (\(right.renderer.modelName)) delay=\(options.rightDelayMs)ms")
        let baseline = min(options.leftDelayMs, options.rightDelayMs)
        var results: [PairRunResult] = []
        for run in 1...options.runs {
            log("Test \(String(format: "%02d", run)) started")
            async let setLeft: Void = setURI(
                label: "LEFT",
                controller: leftController,
                service: leftTransport,
                uri: leftServer.trackURL,
                metadata: leftMetadata
            )
            async let setRight: Void = setURI(
                label: "RIGHT",
                controller: rightController,
                service: rightTransport,
                uri: rightServer.trackURL,
                metadata: rightMetadata
            )
            _ = try await (setLeft, setRight)

            async let playLeft = play(
                label: "LEFT",
                delayMs: options.leftDelayMs - baseline,
                controller: leftController,
                service: leftTransport
            )
            async let playRight = play(
                label: "RIGHT",
                delayMs: options.rightDelayMs - baseline,
                controller: rightController,
                service: rightTransport
            )
            let timings = try await (playLeft, playRight)
            results.append(PairRunResult(
                run: run,
                leftPlaySentMs: timings.0.sentMs,
                rightPlaySentMs: timings.1.sentMs,
                sentDeltaMs: timings.1.sentMs - timings.0.sentMs,
                leftPlayCompletedMs: timings.0.completedMs,
                rightPlayCompletedMs: timings.1.completedMs,
                completedDeltaMs: timings.1.completedMs - timings.0.completedMs
            ))

            let deadline = Date().addingTimeInterval(options.hold)
            while Date() < deadline {
                try await Task.sleep(for: .milliseconds(Int(options.statusInterval * 1_000)))
                async let leftStatus = status(controller: leftController, service: leftTransport)
                async let rightStatus = status(controller: rightController, service: rightTransport)
                let statuses = await (leftStatus, rightStatus)
                log("Test \(String(format: "%02d", run)): LEFT \(statuses.0); RIGHT \(statuses.1)")
            }
            if run < options.runs { try await Task.sleep(for: .seconds(1)) }
        }
        if let outputPath = options.outputPath {
            let report = PairTestReport(
                generatedAt: .now,
                leftModel: left.renderer.modelName,
                rightModel: right.renderer.modelName,
                leftDelayMs: options.leftDelayMs,
                rightDelayMs: options.rightDelayMs,
                acousticMeasurement: "not measured; microphone or listening evaluation required",
                runs: results
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
            log("Pair timing report written to \(outputPath)")
        }
    }

    private static func playCapture(options: Options) async throws {
        guard let reportPath = options.captureReportPath,
              let leftSelector = options.leftRenderer,
              let rightSelector = options.rightRenderer else {
            throw CLIError("play-capture requires --capture-report, --left, and --right")
        }
        guard options.routingConfirmed else {
            throw CLIError("Refusing speaker playback until --confirm-routing is provided after LEFT/RIGHT capture verification")
        }
        guard options.lowVolumeConfirmed else {
            throw CLIError("Refusing speaker playback until --confirm-low-volume is provided")
        }

        let plan = try CapturePlaybackPlan.load(
            reportURL: URL(fileURLWithPath: reportPath),
            safetyCeilingDBFS: options.safetyCeilingDBFS
        )
        log(
            "Validated capture device=\(plan.sourceDeviceName) segments=\(plan.segments.count) "
                + "peak=\(String(format: "%.1f", plan.maximumPeakDBFS))dBFS"
        )

        let discovered = try await renderers(timeout: options.timeout)
        let left = try selectedRenderer(leftSelector, from: discovered)
        let right = try selectedRenderer(rightSelector, from: discovered)
        guard left.renderer.udn != right.renderer.udn else {
            throw CLIError("LEFT and RIGHT must resolve to different renderers")
        }
        guard let leftTransport = left.renderer.avTransport,
              let rightTransport = right.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }
        let leftHost = try LANAddressResolver.address(reaching: left.response.sourceAddress)
        let rightHost = try LANAddressResolver.address(reaching: right.response.sourceAddress)
        let leftController = UPnPController()
        let rightController = UPnPController()
        if let volume = options.testVolume {
            try await setPairVolume(
                volume,
                left: left,
                right: right,
                leftController: leftController,
                rightController: rightController
            )
        }
        let baseline = min(options.leftDelayMs, options.rightDelayMs)
        var results: [CapturedSegmentRunResult] = []

        log("LEFT=\(left.renderer.friendlyName) (\(left.renderer.modelName))")
        log("RIGHT=\(right.renderer.friendlyName) (\(right.renderer.modelName))")
        if options.testVolume == nil {
            log("Speaker volume is not changed because --test-volume was omitted")
        }
        for segment in plan.segments {
            try Task.checkCancellation()
            log(
                "Segment \(String(format: "%04d", segment.number)) started "
                    + "duration=\(String(format: "%.3f", segment.duration))s"
            )
            let timing = try await playCapturedSegment(
                segment,
                leftHost: leftHost,
                rightHost: rightHost,
                leftTransport: leftTransport,
                rightTransport: rightTransport,
                leftController: leftController,
                rightController: rightController,
                httpPort: options.httpPort,
                leftDelayMs: options.leftDelayMs - baseline,
                rightDelayMs: options.rightDelayMs - baseline,
                tail: options.segmentTail
            )
            results.append(CapturedSegmentRunResult(
                segment: segment.number,
                duration: segment.duration,
                leftPeakDBFS: segment.leftPeakDBFS,
                rightPeakDBFS: segment.rightPeakDBFS,
                leftPlaySentMs: timing.0.sentMs,
                rightPlaySentMs: timing.1.sentMs,
                sentDeltaMs: timing.1.sentMs - timing.0.sentMs,
                leftPlayCompletedMs: timing.0.completedMs,
                rightPlayCompletedMs: timing.1.completedMs,
                completedDeltaMs: timing.1.completedMs - timing.0.completedMs
            ))
        }

        if let outputPath = options.outputPath {
            try writeJSON(CapturedPlaybackReport(
                generatedAt: .now,
                captureGeneratedAt: plan.generatedAt,
                leftModel: left.renderer.modelName,
                rightModel: right.renderer.modelName,
                safetyCeilingDBFS: options.safetyCeilingDBFS,
                segmentTail: options.segmentTail,
                continuousPlayback: false,
                note: "Each segment uses a new SetAVTransportURI/Play cycle; gaps and acoustic sync require measurement.",
                segments: results
            ), outputPath: outputPath)
        }
    }

    private static func playCapturedSegment(
        _ segment: CapturePlaybackSegment,
        leftHost: String,
        rightHost: String,
        leftTransport: UPnPService,
        rightTransport: UPnPService,
        leftController: UPnPController,
        rightController: UPnPController,
        httpPort: UInt16,
        leftDelayMs: Int,
        rightDelayMs: Int,
        tail: TimeInterval
    ) async throws -> (PlayTiming, PlayTiming) {
        let leftServer = try TrackHTTPServer(fileURL: segment.leftURL, host: leftHost)
        let rightServer = try TrackHTTPServer(fileURL: segment.rightURL, host: rightHost)
        try leftServer.start(preferredPort: httpPort)
        do { try rightServer.start(preferredPort: httpPort) }
        catch { leftServer.stop(); throw error }
        defer { leftServer.stop(); rightServer.stop() }

        let leftMetadata = SOAPRequestBuilder.didlLiteMetadata(
            resourceURL: leftServer.trackURL,
            mimeType: leftServer.mimeType,
            title: segment.leftURL.deletingPathExtension().lastPathComponent
        )
        let rightMetadata = SOAPRequestBuilder.didlLiteMetadata(
            resourceURL: rightServer.trackURL,
            mimeType: rightServer.mimeType,
            title: segment.rightURL.deletingPathExtension().lastPathComponent
        )
        async let setLeft: Void = setURI(
            label: "LEFT", controller: leftController, service: leftTransport,
            uri: leftServer.trackURL, metadata: leftMetadata
        )
        async let setRight: Void = setURI(
            label: "RIGHT", controller: rightController, service: rightTransport,
            uri: rightServer.trackURL, metadata: rightMetadata
        )
        _ = try await (setLeft, setRight)
        async let playLeft = play(
            label: "LEFT", delayMs: leftDelayMs, controller: leftController, service: leftTransport
        )
        async let playRight = play(
            label: "RIGHT", delayMs: rightDelayMs, controller: rightController, service: rightTransport
        )
        let timings = try await (playLeft, playRight)
        try await Task.sleep(for: .milliseconds(Int((segment.duration + tail) * 1_000)))
        let leftStatus = await status(controller: leftController, service: leftTransport)
        let rightStatus = await status(controller: rightController, service: rightTransport)
        log("Segment \(String(format: "%04d", segment.number)): LEFT \(leftStatus); RIGHT \(rightStatus)")
        return timings
    }

    private static func stopPair(options: Options) async throws {
        guard let leftSelector = options.leftRenderer,
              let rightSelector = options.rightRenderer else {
            throw CLIError("stop-pair requires --left and --right")
        }
        let discovered = try await renderers(timeout: options.timeout)
        let left = try selectedRenderer(leftSelector, from: discovered)
        let right = try selectedRenderer(rightSelector, from: discovered)
        guard left.renderer.udn != right.renderer.udn else {
            throw CLIError("LEFT and RIGHT must resolve to different renderers")
        }
        guard let leftTransport = left.renderer.avTransport,
              let rightTransport = right.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }
        let leftController = UPnPController()
        let rightController = UPnPController()
        async let leftStopError = stopError(controller: leftController, service: leftTransport)
        async let rightStopError = stopError(controller: rightController, service: rightTransport)
        let stopErrors = await (leftStopError, rightStopError)
        if let error = stopErrors.0 { log("LEFT Stop response: \(error)") }
        if let error = stopErrors.1 { log("RIGHT Stop response: \(error)") }

        async let leftState = waitForStopped(controller: leftController, service: leftTransport)
        async let rightState = waitForStopped(controller: rightController, service: rightTransport)
        let states = await (leftState, rightState)
        log("LEFT stop observed state=\(states.0)")
        log("RIGHT stop observed state=\(states.1)")
        guard states.0 == "STOPPED", states.1 == "STOPPED" else {
            throw CLIError("Renderer did not reach STOPPED: LEFT=\(states.0), RIGHT=\(states.1)")
        }
    }

    private static func pausePair(options: Options) async throws {
        guard let leftSelector = options.leftRenderer,
              let rightSelector = options.rightRenderer else {
            throw CLIError("pause-pair requires --left and --right")
        }
        let discovered = try await renderers(timeout: options.timeout)
        let left = try selectedRenderer(leftSelector, from: discovered)
        let right = try selectedRenderer(rightSelector, from: discovered)
        guard left.renderer.udn != right.renderer.udn else {
            throw CLIError("LEFT and RIGHT must resolve to different renderers")
        }
        guard let leftTransport = left.renderer.avTransport,
              let rightTransport = right.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }
        let leftController = UPnPController()
        let rightController = UPnPController()
        async let pauseLeft = pauseError(controller: leftController, service: leftTransport)
        async let pauseRight = pauseError(controller: rightController, service: rightTransport)
        let pauseErrors = await (pauseLeft, pauseRight)
        if let error = pauseErrors.0 { log("LEFT Pause response: \(error)") }
        if let error = pauseErrors.1 { log("RIGHT Pause response: \(error)") }

        async let leftState = waitForState("PAUSED_PLAYBACK", controller: leftController, service: leftTransport)
        async let rightState = waitForState("PAUSED_PLAYBACK", controller: rightController, service: rightTransport)
        let states = await (leftState, rightState)
        log("LEFT pause observed state=\(states.0)")
        log("RIGHT pause observed state=\(states.1)")
        guard states.0 == "PAUSED_PLAYBACK", states.1 == "PAUSED_PLAYBACK" else {
            throw CLIError("Renderer did not reach PAUSED_PLAYBACK: LEFT=\(states.0), RIGHT=\(states.1)")
        }
    }

    private static func preparePair(options: Options) async throws {
        guard let leftSelector = options.leftRenderer,
              let rightSelector = options.rightRenderer,
              let volume = options.testVolume else {
            throw CLIError("prepare-pair requires --left, --right, and --test-volume")
        }
        let discovered = try await renderers(timeout: options.timeout)
        let left = try selectedRenderer(leftSelector, from: discovered)
        let right = try selectedRenderer(rightSelector, from: discovered)
        guard left.renderer.udn != right.renderer.udn else {
            throw CLIError("LEFT and RIGHT must resolve to different renderers")
        }
        guard let leftTransport = left.renderer.avTransport,
              let rightTransport = right.renderer.avTransport else {
            throw HomeStereoError.missingAVTransport
        }
        let leftController = UPnPController()
        let rightController = UPnPController()
        try await setPairVolume(
            volume,
            left: left,
            right: right,
            leftController: leftController,
            rightController: rightController
        )
        async let leftState = transportState(controller: leftController, service: leftTransport)
        async let rightState = transportState(controller: rightController, service: rightTransport)
        let states = await (leftState, rightState)
        log("Pair prepared without playback: LEFT state=\(states.0), RIGHT state=\(states.1)")
    }

    private static func stopError(controller: UPnPController, service: UPnPService) async -> String? {
        do {
            try await controller.stop(service: service)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func pauseError(controller: UPnPController, service: UPnPService) async -> String? {
        do {
            try await controller.pause(service: service)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func waitForStopped(controller: UPnPController, service: UPnPService) async -> String {
        await waitForState("STOPPED", controller: controller, service: service)
    }

    private static func waitForState(
        _ expectedState: String,
        controller: UPnPController,
        service: UPnPService
    ) async -> String {
        var lastState = "UNKNOWN"
        for attempt in 0..<5 {
            lastState = await transportState(controller: controller, service: service)
            if lastState == expectedState { return lastState }
            if attempt < 4 { try? await Task.sleep(for: .milliseconds(250)) }
        }
        return lastState
    }

    private static func transportState(controller: UPnPController, service: UPnPService) async -> String {
        do {
            return try await controller.getTransportInfo(service: service).state
        } catch {
            return "UNKNOWN (\(error.localizedDescription))"
        }
    }

    private static func setPairVolume(
        _ volume: UInt8,
        left: (response: SSDPResponse, renderer: MediaRenderer),
        right: (response: SSDPResponse, renderer: MediaRenderer),
        leftController: UPnPController,
        rightController: UPnPController
    ) async throws {
        guard volume <= 10 else {
            throw CLIError("Test volume is limited to 0...10")
        }
        guard let leftRendering = left.renderer.renderingControl,
              let rightRendering = right.renderer.renderingControl else {
            throw CLIError("Both renderers must expose RenderingControl for an explicit test volume")
        }
        log("Setting explicit test volume to \(volume)/100 on both renderers")
        async let setLeft: Void = leftController.setVolume(service: leftRendering, volume: volume)
        async let setRight: Void = rightController.setVolume(service: rightRendering, volume: volume)
        _ = try await (setLeft, setRight)
        async let leftVolume = leftController.getVolume(service: leftRendering)
        async let rightVolume = rightController.getVolume(service: rightRendering)
        let confirmed = try await (leftVolume, rightVolume)
        log("Volume confirmed LEFT=\(confirmed.0)/100 RIGHT=\(confirmed.1)/100")
        guard confirmed.0 == volume, confirmed.1 == volume else {
            throw CLIError("Volume verification failed: LEFT=\(confirmed.0), RIGHT=\(confirmed.1)")
        }
    }

    private static func selectedRenderer(
        _ selector: String,
        from discovered: [(response: SSDPResponse, renderer: MediaRenderer)]
    ) throws -> (response: SSDPResponse, renderer: MediaRenderer) {
        guard let selected = discovered.first(where: {
            $0.renderer.modelName.localizedCaseInsensitiveCompare(selector) == .orderedSame
                || $0.renderer.friendlyName.localizedCaseInsensitiveCompare(selector) == .orderedSame
        }) else {
            throw CLIError("No renderer matched model or friendly name: \(selector)")
        }
        return selected
    }

    private static func setURI(
        label: String,
        controller: UPnPController,
        service: UPnPService,
        uri: URL,
        metadata: String
    ) async throws {
        log("\(label) SetAVTransportURI sent")
        try await controller.setAVTransportURI(service: service, uri: uri, metadata: metadata)
        log("\(label) SetAVTransportURI completed")
    }

    private static func play(
        label: String,
        delayMs: Int,
        controller: UPnPController,
        service: UPnPService
    ) async throws -> PlayTiming {
        if delayMs > 0 {
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        let sentMs = timestampMs()
        log("\(label) Play sent")
        try await controller.play(service: service)
        let completedMs = timestampMs()
        log("\(label) Play completed")
        return PlayTiming(sentMs: sentMs, completedMs: completedMs)
    }

    private static func status(controller: UPnPController, service: UPnPService) async -> String {
        do {
            let transport = try await controller.getTransportInfo(service: service)
            let position = try await controller.getPositionInfo(service: service)
            return "state=\(transport.state) position=\(position.position.map { String(format: "%.3f", $0) } ?? "unknown")"
        } catch {
            return "status-error=\(error.localizedDescription)"
        }
    }

    private static func renderers(timeout: TimeInterval) async throws -> [(response: SSDPResponse, renderer: MediaRenderer)] {
        log("SSDP discovery started")
        let responses = SSDPDiscovery.deduplicated(try SSDPDiscovery.discover(timeout: timeout)).filter {
            $0.searchTarget.localizedCaseInsensitiveContains("MediaRenderer")
        }
        var result: [(SSDPResponse, MediaRenderer)] = []
        for response in responses {
            if let renderer = try? await DeviceDescriptionLoader.load(from: response.location),
               renderer.deviceType.localizedCaseInsensitiveContains("MediaRenderer") {
                log("Device found: \(renderer.friendlyName) (\(renderer.modelName))")
                result.append((response, renderer))
            }
        }
        return result
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("[Bridge \(timestampMs())] \(message)\n".utf8))
    }

    private static func timestampMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }

    private static func probe(timeout: TimeInterval) async throws -> ProbeReport {
        FileHandle.standardError.write(Data("[Bridge] SSDP discovery started\n".utf8))
        let discovered = try SSDPDiscovery.discover(timeout: timeout)
        let candidates = SSDPDiscovery.deduplicated(discovered).filter {
            $0.searchTarget.localizedCaseInsensitiveContains("MediaRenderer")
        }
        var devices: [DeviceReport] = []
        for response in candidates {
            do {
                let renderer = try await DeviceDescriptionLoader.load(from: response.location)
                guard renderer.deviceType.localizedCaseInsensitiveContains("MediaRenderer") else { continue }
                FileHandle.standardError.write(Data("[Bridge] Device found: \(renderer.friendlyName) (\(renderer.modelName))\n".utf8))
                var services: [ServiceReport] = []
                for service in renderer.services {
                    var actions: [String] = []
                    var error: String?
                    if let descriptionURL = service.descriptionURL {
                        do {
                            actions = try await ServiceDescriptionLoader.load(from: descriptionURL).actions
                        } catch let loadError {
                            error = loadError.localizedDescription
                        }
                    }
                    services.append(ServiceReport(
                        serviceType: service.serviceType,
                        serviceID: service.serviceID,
                        controlURL: service.controlURL.absoluteString,
                        descriptionURL: service.descriptionURL?.absoluteString,
                        actions: actions,
                        error: error
                    ))
                }
                var protocolInfo: ProtocolInfoReport?
                if let connectionManager = renderer.connectionManager {
                    do {
                        let info = try await UPnPController().getProtocolInfo(service: connectionManager)
                        protocolInfo = ProtocolInfoReport(source: info.source, sink: info.sink, error: nil)
                    } catch let protocolError {
                        protocolInfo = ProtocolInfoReport(source: [], sink: [], error: protocolError.localizedDescription)
                    }
                }
                devices.append(DeviceReport(
                    friendlyName: renderer.friendlyName,
                    manufacturer: renderer.manufacturer,
                    modelName: renderer.modelName,
                    modelNumber: renderer.modelNumber,
                    udn: renderer.udn,
                    ipAddress: response.sourceAddress,
                    descriptionURL: renderer.descriptionURL.absoluteString,
                    services: services,
                    protocolInfo: protocolInfo
                ))
            } catch {
                FileHandle.standardError.write(Data("[Bridge] Description failed for \(response.sourceAddress): \(error.localizedDescription)\n".utf8))
            }
        }
        return ProbeReport(
            schemaVersion: 1,
            generatedAt: .now,
            devices: devices.sorted { $0.friendlyName < $1.friendlyName }
        )
    }
}

private struct ProbeReport: Codable {
    let schemaVersion: Int
    let generatedAt: Date
    let devices: [DeviceReport]
}

private struct DeviceReport: Codable {
    let friendlyName: String
    let manufacturer: String
    let modelName: String
    let modelNumber: String?
    let udn: String
    let ipAddress: String
    let descriptionURL: String
    let services: [ServiceReport]
    let protocolInfo: ProtocolInfoReport?
}

private struct ServiceReport: Codable {
    let serviceType: String
    let serviceID: String
    let controlURL: String
    let descriptionURL: String?
    let actions: [String]
    let error: String?
}

private struct ProtocolInfoReport: Codable {
    let source: [String]
    let sink: [String]
    let error: String?
}

private struct PlayTiming {
    let sentMs: Int64
    let completedMs: Int64
}

private struct PairRunResult: Codable {
    let run: Int
    let leftPlaySentMs: Int64
    let rightPlaySentMs: Int64
    let sentDeltaMs: Int64
    let leftPlayCompletedMs: Int64
    let rightPlayCompletedMs: Int64
    let completedDeltaMs: Int64
}

private struct PairTestReport: Codable {
    let generatedAt: Date
    let leftModel: String
    let rightModel: String
    let leftDelayMs: Int
    let rightDelayMs: Int
    let acousticMeasurement: String
    let runs: [PairRunResult]
}

private struct CapturedSegmentRunResult: Codable {
    let segment: Int
    let duration: TimeInterval
    let leftPeakDBFS: Double
    let rightPeakDBFS: Double
    let leftPlaySentMs: Int64
    let rightPlaySentMs: Int64
    let sentDeltaMs: Int64
    let leftPlayCompletedMs: Int64
    let rightPlayCompletedMs: Int64
    let completedDeltaMs: Int64
}

private struct CapturedPlaybackReport: Codable {
    let generatedAt: Date
    let captureGeneratedAt: Date
    let leftModel: String
    let rightModel: String
    let safetyCeilingDBFS: Double
    let segmentTail: TimeInterval
    let continuousPlayback: Bool
    let note: String
    let segments: [CapturedSegmentRunResult]
}

private struct AudioProbeReport: Codable {
    let generatedAt: Date
    let audioInputAuthorization: String
    let devices: [AudioInputDevice]
}

private struct Options {
    static let usage = """
    Usage:
      sony-stereo-bridge probe [--timeout <seconds>] [--output <path>]
      sony-stereo-bridge audio-probe [--output <path>]
      sony-stereo-bridge capture-segments --device <name-or-uid> --output-dir <path> [--duration <seconds>] [--segment-seconds <seconds>] [--left-channel <1-based>] [--right-channel <1-based>] [--buffer-frames <frames>] [--output <report-path>]
      sony-stereo-bridge play-one --renderer <model-or-name> --file <path> [--timeout <seconds>] [--http-port <port>] [--hold <seconds>]
      sony-stereo-bridge play-pair --left <model-or-name> --left-file <path> --right <model-or-name> --right-file <path> [--test-volume <0...10>] [--left-delay <ms>] [--right-delay <ms>] [--runs <count>] [--timeout <seconds>] [--http-port <port>] [--hold <seconds>] [--status-interval <seconds>] [--output <path>]
      sony-stereo-bridge play-capture --capture-report <path> --left <model-or-name> --right <model-or-name> --confirm-routing --confirm-low-volume [--test-volume <0...10>] [--left-delay <ms>] [--right-delay <ms>] [--segment-tail <seconds>] [--safety-ceiling-dbfs <negative-dBFS>] [--timeout <seconds>] [--http-port <port>] [--output <path>]
      sony-stereo-bridge prepare-pair --left <model-or-name> --right <model-or-name> --test-volume <0...10> [--timeout <seconds>]
      sony-stereo-bridge pause-pair --left <model-or-name> --right <model-or-name> [--timeout <seconds>]
      sony-stereo-bridge stop-pair --left <model-or-name> --right <model-or-name> [--timeout <seconds>]
    """
    let command: String
    let timeout: TimeInterval
    let outputPath: String?
    let renderer: String?
    let filePath: String?
    let httpPort: UInt16
    let hold: TimeInterval
    let leftRenderer: String?
    let leftFilePath: String?
    let rightRenderer: String?
    let rightFilePath: String?
    let leftDelayMs: Int
    let rightDelayMs: Int
    let runs: Int
    let statusInterval: TimeInterval
    let audioDevice: String?
    let outputDirectory: String?
    let captureDuration: TimeInterval
    let segmentSeconds: TimeInterval
    let leftChannel: Int
    let rightChannel: Int
    let bufferFrames: Int
    let captureReportPath: String?
    let routingConfirmed: Bool
    let lowVolumeConfirmed: Bool
    let segmentTail: TimeInterval
    let safetyCeilingDBFS: Double
    let testVolume: UInt8?

    static func parse(_ arguments: [String]) throws -> Options {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            Foundation.exit(EXIT_SUCCESS)
        }
        guard arguments.count >= 2 else { throw CLIError(usage) }
        var timeout: TimeInterval = 6
        var outputPath: String?
        var renderer: String?
        var filePath: String?
        var httpPort: UInt16 = 9876
        var hold: TimeInterval = 8
        var leftRenderer: String?
        var leftFilePath: String?
        var rightRenderer: String?
        var rightFilePath: String?
        var leftDelayMs = 0
        var rightDelayMs = 0
        var runs = 1
        var statusInterval: TimeInterval = 1
        var audioDevice: String?
        var outputDirectory: String?
        var captureDuration: TimeInterval = 5
        var segmentSeconds: TimeInterval = 1
        var leftChannel = 1
        var rightChannel = 2
        var bufferFrames = 1_024
        var captureReportPath: String?
        var routingConfirmed = false
        var lowVolumeConfirmed = false
        var segmentTail: TimeInterval = 0.25
        var safetyCeilingDBFS = -6.0
        var testVolume: UInt8?
        var index = 2
        while index < arguments.count {
            switch arguments[index] {
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (1...30).contains(value) else {
                    throw CLIError("--timeout must be between 1 and 30 seconds")
                }
                timeout = value
            case "--output":
                index += 1
                guard index < arguments.count else { throw CLIError("--output requires a path") }
                outputPath = arguments[index]
            case "--renderer":
                index += 1
                guard index < arguments.count else { throw CLIError("--renderer requires a value") }
                renderer = arguments[index]
            case "--file":
                index += 1
                guard index < arguments.count else { throw CLIError("--file requires a path") }
                filePath = arguments[index]
            case "--http-port":
                index += 1
                guard index < arguments.count,
                      let value = UInt16(arguments[index]),
                      value != 8080 else {
                    throw CLIError("--http-port must be a valid port other than 8080")
                }
                httpPort = value
            case "--hold":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (1...600).contains(value) else {
                    throw CLIError("--hold must be between 1 and 600 seconds")
                }
                hold = value
            case "--left":
                index += 1
                guard index < arguments.count else { throw CLIError("--left requires a value") }
                leftRenderer = arguments[index]
            case "--left-file":
                index += 1
                guard index < arguments.count else { throw CLIError("--left-file requires a path") }
                leftFilePath = arguments[index]
            case "--right":
                index += 1
                guard index < arguments.count else { throw CLIError("--right requires a value") }
                rightRenderer = arguments[index]
            case "--right-file":
                index += 1
                guard index < arguments.count else { throw CLIError("--right-file requires a path") }
                rightFilePath = arguments[index]
            case "--left-delay":
                index += 1
                leftDelayMs = try delay(arguments, at: index, option: "--left-delay")
            case "--right-delay":
                index += 1
                rightDelayMs = try delay(arguments, at: index, option: "--right-delay")
            case "--runs":
                index += 1
                guard index < arguments.count,
                      let value = Int(arguments[index]),
                      (1...20).contains(value) else {
                    throw CLIError("--runs must be between 1 and 20")
                }
                runs = value
            case "--status-interval":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (0.5...60).contains(value) else {
                    throw CLIError("--status-interval must be between 0.5 and 60 seconds")
                }
                statusInterval = value
            case "--device":
                index += 1
                guard index < arguments.count else { throw CLIError("--device requires a name or UID") }
                audioDevice = arguments[index]
            case "--output-dir":
                index += 1
                guard index < arguments.count else { throw CLIError("--output-dir requires a path") }
                outputDirectory = arguments[index]
            case "--duration":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (1...600).contains(value) else {
                    throw CLIError("--duration must be between 1 and 600 seconds")
                }
                captureDuration = value
            case "--segment-seconds":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (0.25...5).contains(value) else {
                    throw CLIError("--segment-seconds must be between 0.25 and 5 seconds")
                }
                segmentSeconds = value
            case "--left-channel":
                index += 1
                leftChannel = try positiveInteger(arguments, at: index, option: "--left-channel", maximum: 256)
            case "--right-channel":
                index += 1
                rightChannel = try positiveInteger(arguments, at: index, option: "--right-channel", maximum: 256)
            case "--buffer-frames":
                index += 1
                bufferFrames = try positiveInteger(arguments, at: index, option: "--buffer-frames", maximum: 8_192, minimum: 64)
            case "--capture-report":
                index += 1
                guard index < arguments.count else { throw CLIError("--capture-report requires a path") }
                captureReportPath = arguments[index]
            case "--confirm-routing":
                routingConfirmed = true
            case "--confirm-low-volume":
                lowVolumeConfirmed = true
            case "--segment-tail":
                index += 1
                guard index < arguments.count,
                      let value = TimeInterval(arguments[index]),
                      (0...5).contains(value) else {
                    throw CLIError("--segment-tail must be between 0 and 5 seconds")
                }
                segmentTail = value
            case "--safety-ceiling-dbfs":
                index += 1
                guard index < arguments.count,
                      let value = Double(arguments[index]),
                      (-60 ... -0.1).contains(value) else {
                    throw CLIError("--safety-ceiling-dbfs must be between -60 and -0.1 dBFS")
                }
                safetyCeilingDBFS = value
            case "--test-volume":
                index += 1
                guard index < arguments.count,
                      let value = UInt8(arguments[index]),
                      value <= 10 else {
                    throw CLIError("--test-volume must be between 0 and 10")
                }
                testVolume = value
            default:
                throw CLIError("Unknown option: \(arguments[index])")
            }
            index += 1
        }
        return Options(
            command: arguments[1],
            timeout: timeout,
            outputPath: outputPath,
            renderer: renderer,
            filePath: filePath,
            httpPort: httpPort,
            hold: hold,
            leftRenderer: leftRenderer,
            leftFilePath: leftFilePath,
            rightRenderer: rightRenderer,
            rightFilePath: rightFilePath,
            leftDelayMs: leftDelayMs,
            rightDelayMs: rightDelayMs,
            runs: runs,
            statusInterval: statusInterval,
            audioDevice: audioDevice,
            outputDirectory: outputDirectory,
            captureDuration: captureDuration,
            segmentSeconds: segmentSeconds,
            leftChannel: leftChannel,
            rightChannel: rightChannel,
            bufferFrames: bufferFrames,
            captureReportPath: captureReportPath,
            routingConfirmed: routingConfirmed,
            lowVolumeConfirmed: lowVolumeConfirmed,
            segmentTail: segmentTail,
            safetyCeilingDBFS: safetyCeilingDBFS,
            testVolume: testVolume
        )
    }

    private static func delay(_ arguments: [String], at index: Int, option: String) throws -> Int {
        guard index < arguments.count,
              let value = Int(arguments[index]),
              (-5_000...5_000).contains(value) else {
            throw CLIError("\(option) must be between -5000 and 5000 milliseconds")
        }
        return value
    }

    private static func positiveInteger(
        _ arguments: [String],
        at index: Int,
        option: String,
        maximum: Int,
        minimum: Int = 1
    ) throws -> Int {
        guard index < arguments.count,
              let value = Int(arguments[index]),
              (minimum...maximum).contains(value) else {
            throw CLIError("\(option) must be between \(minimum) and \(maximum)")
        }
        return value
    }
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
