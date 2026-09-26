import Foundation
import Network

public final class TrackHTTPServer: @unchecked Sendable {
    public let host: String
    public private(set) var port: UInt16 = 0
    public let trackID: UUID
    public let token: String
    public let fileURL: URL
    public let mimeType: String

    private let queue = DispatchQueue(label: "HomeStereo.TrackHTTPServer")
    private let startGate: TrackHTTPStartGate?
    private let startGateParticipant: String?
    private var listener: NWListener?

    public init(
        fileURL: URL,
        host: String,
        trackID: UUID = UUID(),
        token: String = UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        startGate: TrackHTTPStartGate? = nil,
        startGateParticipant: String? = nil
    ) throws {
        self.fileURL = fileURL.standardizedFileURL
        self.host = host
        self.trackID = trackID
        self.token = token
        self.mimeType = try AudioMIMEType.forFileURL(fileURL)
        self.startGate = startGate
        self.startGateParticipant = startGateParticipant
    }

    public var trackURL: URL {
        TrackURLBuilder.url(host: host, port: port, trackID: trackID, token: token)
    }

    public func start(preferredPort: UInt16 = 8765, maximumAttempts: Int = 100) throws {
        precondition(preferredPort != 8080, "TCP 8080 is reserved and must never be used.")
        for offset in 0..<maximumAttempts {
            let candidateValue = Int(preferredPort) + offset
            guard candidateValue <= Int(UInt16.max), candidateValue != 8080,
                  let candidate = NWEndpoint.Port(rawValue: UInt16(candidateValue)) else { continue }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: candidate)
            let candidateListener = try NWListener(using: parameters)
            let semaphore = DispatchSemaphore(value: 0)
            let readiness = ListenerReadiness()
            candidateListener.stateUpdateHandler = { state in
                switch state {
                case .ready: readiness.markReady(); semaphore.signal()
                case .failed: semaphore.signal()
                default: break
                }
            }
            candidateListener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            candidateListener.start(queue: queue)
            _ = semaphore.wait(timeout: .now() + 2)
            guard readiness.isReady else {
                candidateListener.cancel()
                continue
            }
            listener = candidateListener
            port = UInt16(candidateValue)
            print("[DLNA] HTTP media server ready")
            return
        }
        throw HomeStereoError.cannotBindPort(Int(preferredPort))
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { print("[DLNA] HTTP connection failed") }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var requestData = accumulated
            if let data { requestData.append(data) }
            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.handle(requestData, on: connection)
            } else if complete || error != nil || requestData.count > 65_536 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, accumulated: requestData)
            }
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else {
            sendSimple(status: "400 Bad Request", on: connection); return
        }
        let lines = request.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        guard requestParts.count >= 2 else { sendSimple(status: "400 Bad Request", on: connection); return }
        let method = String(requestParts[0])
        let target = String(requestParts[1])
        let headers = lines.dropFirst().reduce(into: [String: String]()) { result, line in
            guard let colon = line.firstIndex(of: ":") else { return }
            result[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        print("[DLNA] HTTP request received: \(method)")
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let sizeNumber = attributes[.size] as? NSNumber else { throw HomeStereoError.serverFailure("Missing file size") }
            let size = sizeNumber.int64Value
            let response = MediaHTTPRequestHandler.response(
                method: method,
                target: target,
                headers: headers,
                trackID: trackID,
                token: token,
                mimeType: mimeType,
                fileSize: size
            )
            guard response.status == 200 || response.status == 206 else {
                sendSimple(status: response.status == 416 ? "416 Range Not Satisfiable" : "404 Not Found", additionalHeaders: response.headers, on: connection)
                return
            }
            if response.status == 206, let selected = response.bodyRange {
                print("[DLNA] Range request: bytes=\(selected.lowerBound)-\(selected.upperBound)")
            }
            let statusText = response.status == 206 ? "206 Partial Content" : "200 OK"
            let serializedHeaders = response.headers.map { "\($0.key): \($0.value)" }.sorted()
            let headerData = Data((["HTTP/1.1 \(statusText)"] + serializedHeaders + ["Connection: close"]).joined(separator: "\r\n").appending("\r\n\r\n").utf8)
            connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
                guard error == nil, let selected = response.bodyRange, let self else { connection.cancel(); return }
                let beginStreaming: @Sendable () -> Void = { [weak self] in
                    guard let self else { connection.cancel(); return }
                    self.queue.async { self.sendFile(on: connection, range: selected) }
                }
                if let startGate = self.startGate,
                   let participant = self.startGateParticipant {
                    startGate.arrive(participant: participant, completion: beginStreaming)
                } else {
                    beginStreaming()
                }
            })
        } catch {
            print("[DLNA] HTTP request failed")
            sendSimple(status: "500 Internal Server Error", on: connection)
        }
    }

    private func sendFile(on connection: NWConnection, range: ByteRange) {
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            try handle.seek(toOffset: UInt64(range.lowerBound))
            sendNextChunk(handle: handle, remaining: range.length, on: connection)
        } catch {
            print("[DLNA] File stream failed")
            connection.cancel()
        }
    }

    private func sendNextChunk(handle: FileHandle, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0 else { try? handle.close(); connection.cancel(); return }
        do {
            let data = try handle.read(upToCount: Int(min(remaining, 256 * 1024))) ?? Data()
            guard !data.isEmpty else { try? handle.close(); connection.cancel(); return }
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard error == nil, let self else { try? handle.close(); connection.cancel(); return }
                self.sendNextChunk(handle: handle, remaining: remaining - Int64(data.count), on: connection)
            })
        } catch {
            try? handle.close()
            connection.cancel()
        }
    }

    private func sendSimple(status: String, additionalHeaders: [String: String] = [:], on connection: NWConnection) {
        let headers = additionalHeaders.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\r\n")
        let separator = headers.isEmpty ? "" : "\(headers)\r\n"
        let response = "HTTP/1.1 \(status)\r\n\(separator)Content-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}

public final class TrackHTTPStartGate: @unchecked Sendable {
    private let participants: Set<String>
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var arrived: Set<String> = []
    private var completions: [@Sendable () -> Void] = []
    private var isOpen = false
    private var timeoutWorkItem: DispatchWorkItem?

    public init(participants: Set<String>, timeout: TimeInterval) {
        precondition(!participants.isEmpty)
        self.participants = participants
        self.timeout = max(0, timeout)
    }

    public func arrive(participant: String, completion: @escaping @Sendable () -> Void) {
        let callbacks: [@Sendable () -> Void] = lock.withLock {
            guard !isOpen else { return [completion] }
            guard participants.contains(participant) else { return [completion] }
            arrived.insert(participant)
            completions.append(completion)
            if timeoutWorkItem == nil {
                let workItem = DispatchWorkItem { [weak self] in self?.open() }
                timeoutWorkItem = workItem
                DispatchQueue.global(qos: .userInitiated).asyncAfter(
                    deadline: .now() + timeout, execute: workItem
                )
            }
            guard arrived.isSuperset(of: participants) else { return [] }
            return takeCallbacksLocked()
        }
        callbacks.forEach { $0() }
    }

    private func open() {
        let callbacks = lock.withLock { takeCallbacksLocked() }
        callbacks.forEach { $0() }
    }

    private func takeCallbacksLocked() -> [@Sendable () -> Void] {
        guard !isOpen else { return [] }
        isOpen = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        let callbacks = completions
        completions.removeAll()
        return callbacks
    }
}

private final class ListenerReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false

    var isReady: Bool { lock.withLock { ready } }
    func markReady() { lock.withLock { ready = true } }
}
