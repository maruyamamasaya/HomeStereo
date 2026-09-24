#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct QueueView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @State private var confirmsClear = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $queue.selectedItemIDs) {
                ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Image(systemName: index == queue.currentIndex ? "speaker.wave.2.fill" : "line.3.horizontal")
                            .foregroundStyle(index == queue.currentIndex ? Color.accentColor : Color.secondary)
                            .accessibilityLabel(index == queue.currentIndex ? "現在再生中" : "Queue項目")
                        if let track = queue.track(for: item) {
                            VStack(alignment: .leading) {
                                Text(track.title)
                                Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(formatQueueDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            Text("Libraryにない曲").foregroundStyle(.orange)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { Task { await queue.playItem(id: item.id) } }
                    .tag(item.id)
                    .contextMenu {
                        Button("今すぐ再生") { Task { await queue.playItem(id: item.id) } }
                        Button("Queueから削除", role: .destructive) {
                            queue.selectedItemIDs = [item.id]
                            Task { await queue.removeSelected() }
                        }
                    }
                }
                .onMove { source, destination in Task { await queue.move(fromOffsets: source, toOffset: destination) } }
                .onDelete { offsets in Task { await queue.remove(atOffsets: offsets) } }
            }
            .onDeleteCommand { Task { await queue.removeSelected() } }
            .dropDestination(for: String.self) { values, _ in
                let ids = values.flatMap(TrackDragPayload.decode)
                guard !ids.isEmpty else { return false }
                Task { await queue.append(trackIDs: ids) }
                return true
            }
            .accessibilityLabel("再生Queue")
            Divider()
            HStack(spacing: 16) {
                Button("前へ", systemImage: "backward.fill") { Task { await queue.previous() } }
                Button(playback.playbackState == .playing ? "一時停止" : "再生", systemImage: playback.playbackState == .playing ? "pause.fill" : "play.fill") {
                    Task { await playback.togglePlayback() }
                }
                Button("次へ", systemImage: "forward.fill") { Task { await queue.next() } }
                Toggle("Shuffle", systemImage: "shuffle", isOn: Binding(
                    get: { queue.shuffleEnabled }, set: { _ in Task { await queue.toggleShuffle() } }
                )).toggleStyle(.button)
                Picker("Repeat", selection: Binding(
                    get: { queue.repeatMode }, set: { value in Task { await queue.setRepeatMode(value) } }
                )) {
                    ForEach(QueueRepeatMode.allCases) { Text($0.rawValue).tag($0) }
                }.frame(minWidth: 100, idealWidth: 120)
                Spacer()
                Button("すべて消去", role: .destructive) { confirmsClear = true }.disabled(queue.items.isEmpty)
            }.padding()
        }
        .navigationTitle("Queue")
        .alert("Queue", isPresented: Binding(
            get: { queue.errorMessage != nil }, set: { if !$0 { queue.dismissError() } }
        )) {
            Button("OK") { queue.dismissError() }
        } message: { Text(queue.errorMessage ?? "") }
        .confirmationDialog("Queueの全項目を削除しますか？", isPresented: $confirmsClear) {
            Button("すべて削除", role: .destructive) { Task { await queue.clear() } }
        } message: {
            Text("音源ファイルは削除されません。現在の再生も停止しません。")
        }
    }
}

private func formatQueueDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded()); return String(format: "%d:%02d", total / 60, total % 60)
}
