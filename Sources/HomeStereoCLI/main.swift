import Foundation
import HomeStereoKit

@main
struct HomeStereoCommand {
    static func main() async {
        do {
            let options = try Options.parse(CommandLine.arguments)
            let fileURL = URL(fileURLWithPath: options.filePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                throw CLIError("Audio file does not exist: \(fileURL.path)")
            }
            let descriptionURL = try SSDPDiscovery.deviceDescriptionURL(rendererIP: options.rendererIP)
            let renderer = try await DeviceDescriptionLoader.load(from: descriptionURL)
            guard let avTransport = renderer.avTransport else { throw HomeStereoError.missingAVTransport }
            let localAddress = try LANAddressResolver.address(reaching: options.rendererIP)
            let server = try TrackHTTPServer(fileURL: fileURL, host: localAddress)
            try server.start(preferredPort: 8765)
            defer { server.stop() }

            let metadata = SOAPRequestBuilder.didlLiteMetadata(
                resourceURL: server.trackURL,
                mimeType: server.mimeType,
                title: fileURL.deletingPathExtension().lastPathComponent
            )
            let controller = UPnPController()
            print("[DLNA] Track URL: \(server.trackURL.absoluteString)")
            print("[DLNA] SetAVTransportURI")
            try await controller.setAVTransportURI(service: avTransport, uri: server.trackURL, metadata: metadata)
            print("[DLNA] Play")
            try await controller.play(service: avTransport)
            print("Playing on \(renderer.friendlyName). Commands: play, pause, stop, seek <seconds>, volume <0-100>, quit")

            while let line = readLine(strippingNewline: true) {
                let parts = line.split(separator: " ")
                guard let command = parts.first?.lowercased() else { continue }
                do {
                    switch command {
                    case "play": try await controller.play(service: avTransport)
                    case "pause": try await controller.pause(service: avTransport)
                    case "stop": try await controller.stop(service: avTransport)
                    case "seek":
                        guard parts.count == 2, let seconds = Double(parts[1]) else { print("usage: seek <seconds>"); continue }
                        try await controller.seek(service: avTransport, position: seconds)
                    case "volume":
                        guard let renderingControl = renderer.renderingControl else { print("RenderingControl is unavailable"); continue }
                        guard parts.count == 2, let volume = UInt8(parts[1]), volume <= 100 else { print("usage: volume <0-100>"); continue }
                        try await controller.setVolume(service: renderingControl, volume: volume)
                    case "quit", "exit": return
                    default: print("Commands: play, pause, stop, seek <seconds>, volume <0-100>, quit")
                    }
                } catch {
                    // A renderer can disappear or reject an action while the server is active.
                    // Keep the session alive so the user can retry, stop, or quit cleanly.
                    print("[DLNA] Command failed: \(error.localizedDescription)")
                }
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }
}

private struct Options {
    let rendererIP: String
    let filePath: String

    static func parse(_ arguments: [String]) throws -> Options {
        var rendererIP: String?
        var filePath: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--renderer":
                index += 1
                if index < arguments.count { rendererIP = arguments[index] }
            case "--file":
                index += 1
                if index < arguments.count { filePath = arguments[index] }
            case "--help", "-h":
                print("Usage: home-stereo --renderer <IPv4> --file <local-audio-file>")
                Foundation.exit(EXIT_SUCCESS)
            default: throw CLIError("Unknown option: \(arguments[index])")
            }
            index += 1
        }
        guard let rendererIP, let filePath else {
            throw CLIError("Usage: home-stereo --renderer <IPv4> --file <local-audio-file>")
        }
        return Options(rendererIP: rendererIP, filePath: filePath)
    }
}

private struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
