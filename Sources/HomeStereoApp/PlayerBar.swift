import AVFoundation
import AVKit
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct PlayerBar: View {
    @Bindable var store: PlaybackStore

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(data: store.currentTrack?.artworkData, size: 52, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.currentTrack?.title ?? "再生する曲を選択")
                    .font(.headline)
                    .lineLimit(1)
                Text(store.currentTrack?.artist ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)

            Button(action: store.previous) { Image(systemName: "backward.fill") }
                .disabled(store.currentTrack == nil)
            Button(action: store.togglePlayback) {
                Image(systemName: store.playbackState == .playing ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(store.currentTrack == nil)
            Button(action: store.next) { Image(systemName: "forward.fill") }
                .disabled(store.currentTrack == nil)

            Text(formatTime(store.elapsed))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .trailing)
            Slider(
                value: Binding(get: { store.elapsed }, set: { store.seek(to: $0) }),
                in: 0...max(store.duration, 1)
            )
            .disabled(store.currentTrack == nil || store.duration <= 0)
            Text(formatTime(store.duration))
                .font(.caption.monospacedDigit())
                .frame(width: 42, alignment: .leading)

            AirPlayRoutePicker(player: store.routePickerPlayer)
                .frame(width: 30, height: 30)
                .help("出力先を選択")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(height: 72)
        .background(.bar)
    }
}

private struct AirPlayRoutePicker: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = player
        return view
    }

    func updateNSView(_ view: AVRoutePickerView, context: Context) {
        view.player = player
    }
}

private func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}
