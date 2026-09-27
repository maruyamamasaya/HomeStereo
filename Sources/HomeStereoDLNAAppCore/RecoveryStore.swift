import Foundation
import Observation

public enum RecoveryState: Equatable, Sendable {
    case connected
    case sleeping
    case waitingForNetwork
    case reconnecting(attempt: Int)
    case readyToResume
    case disconnected(String)
}

public struct ReconnectPolicy: Equatable, Sendable {
    public let delays: [Duration]
    public init(delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]) { self.delays = delays }
}

@MainActor
@Observable
public final class RecoveryStore {
    public private(set) var state: RecoveryState = .connected
    public private(set) var shouldAskToResume = false

    @ObservationIgnored private let monitor: any SystemEventMonitoring
    @ObservationIgnored private let playback: RendererPlaybackStore
    @ObservationIgnored private let queue: QueueStore
    @ObservationIgnored private let listening: ListeningStore
    @ObservationIgnored private let policy: ReconnectPolicy
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var networkAvailable = true
    @ObservationIgnored private var rendererUDN: String?
    @ObservationIgnored private var wasPlaying = false

    public init(
        monitor: any SystemEventMonitoring, playback: RendererPlaybackStore, queue: QueueStore,
        listening: ListeningStore, policy: ReconnectPolicy = ReconnectPolicy()
    ) {
        self.monitor = monitor; self.playback = playback; self.queue = queue
        self.listening = listening; self.policy = policy
    }

    deinit { reconnectTask?.cancel() }

    public func start() { monitor.start { [weak self] event in self?.handle(event) } }
    public func stop() { reconnectTask?.cancel(); monitor.stop() }

    public func reconnectManually() { beginReconnect() }

    public func resume() async {
        shouldAskToResume = false
        guard case .readyToResume = state else { return }
        await queue.play()
    }

    public func declineResume() { shouldAskToResume = false; state = .connected }

    private func handle(_ event: SystemPlaybackEvent) {
        switch event {
        case .willSleep:
            wasPlaying = playback.playbackState == .playing
            rendererUDN = playback.selectedDevice?.description?.udn
            state = .sleeping
            reconnectTask?.cancel()
            Task { await queue.persistForLifecycle(); await listening.flush() }
            playback.prepareForSystemInterruption()
        case .didWake:
            if playback.isThisMacSelected {
                if wasPlaying {
                    state = .readyToResume
                    shouldAskToResume = true
                } else {
                    state = .connected
                }
                return
            }
            state = networkAvailable ? .reconnecting(attempt: 1) : .waitingForNetwork
            if networkAvailable { beginReconnect() }
        case let .networkAvailable(available):
            networkAvailable = available
            if playback.isThisMacSelected { return }
            if !available {
                reconnectTask?.cancel()
                wasPlaying = wasPlaying || playback.playbackState == .playing
                rendererUDN = rendererUDN ?? playback.selectedDevice?.description?.udn
                playback.prepareForSystemInterruption()
                state = .waitingForNetwork
            } else if state != .connected && state != .readyToResume { beginReconnect() }
        }
    }

    private func beginReconnect() {
        reconnectTask?.cancel()
        guard networkAvailable else { state = .waitingForNetwork; return }
        let udn = rendererUDN ?? playback.selectedDevice?.description?.udn
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            for (index, delay) in policy.delays.enumerated() {
                guard !Task.isCancelled else { return }
                state = .reconnecting(attempt: index + 1)
                if await playback.reconnect(udn: udn) {
                    if wasPlaying { state = .readyToResume; shouldAskToResume = true }
                    else { state = .connected }
                    return
                }
                if index + 1 < policy.delays.count { try? await Task.sleep(for: delay) }
            }
            state = .disconnected("スピーカーを再発見できませんでした。手動で再接続できます。")
        }
    }
}
