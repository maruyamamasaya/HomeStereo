import Foundation
import HomeStereoKit

@main
struct SonyStereoBridgeCommand {
    static func main() async {
        do {
            let options = try Options.parse(CommandLine.arguments)
            switch options.command {
            case "probe":
                try await writeProbe(options: options)
            case "play-one":
                try await playOne(options: options)
            case "play-pair":
                try await playPair(options: options)
            default:
                throw CLIError(Options.usage)
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
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

        let baseline = min(options.leftDelayMs, options.rightDelayMs)
        async let playLeft: Void = play(
            label: "LEFT",
            delayMs: options.leftDelayMs - baseline,
            controller: leftController,
            service: leftTransport
        )
        async let playRight: Void = play(
            label: "RIGHT",
            delayMs: options.rightDelayMs - baseline,
            controller: rightController,
            service: rightTransport
        )
        _ = try await (playLeft, playRight)

        let deadline = Date().addingTimeInterval(options.hold)
        while Date() < deadline {
            try await Task.sleep(for: .seconds(1))
            async let leftStatus = status(controller: leftController, service: leftTransport)
            async let rightStatus = status(controller: rightController, service: rightTransport)
            let statuses = await (leftStatus, rightStatus)
            log("LEFT \(statuses.0); RIGHT \(statuses.1)")
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
    ) async throws {
        if delayMs > 0 {
            try await Task.sleep(for: .milliseconds(delayMs))
        }
        log("\(label) Play sent")
        try await controller.play(service: service)
        log("\(label) Play completed")
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
        let milliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        FileHandle.standardError.write(Data("[Bridge \(milliseconds)] \(message)\n".utf8))
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

private struct Options {
    static let usage = """
    Usage:
      sony-stereo-bridge probe [--timeout <seconds>] [--output <path>]
      sony-stereo-bridge play-one --renderer <model-or-name> --file <path> [--timeout <seconds>] [--http-port <port>] [--hold <seconds>]
      sony-stereo-bridge play-pair --left <model-or-name> --left-file <path> --right <model-or-name> --right-file <path> [--left-delay <ms>] [--right-delay <ms>] [--timeout <seconds>] [--http-port <port>] [--hold <seconds>]
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
            rightDelayMs: rightDelayMs
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
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
