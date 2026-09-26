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
    @Bindable var library: LibraryStore
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if queue.items.isEmpty {
                ContentUnavailableView {
                    Label("再生キューは空です", systemImage: "text.line.first.and.arrowtriangle.forward")
                } description: {
                    Text("曲、アルバム、アーティスト、プレイリストから再生する曲を追加してください。")
                } actions: {
                    Button("曲を選ぶ") { playback.destination = .songs }
                }
            } else {
                VStack(spacing: 0) {
                    queueSummary
                    Divider()
                    queueList
                    Divider()
                    selectionBar
                }
            }
        }
        .navigationTitle("次はこちら")
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = queue.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("再生キューを操作できませんでした").font(.callout.bold())
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button("閉じる", systemImage: "xmark") { queue.dismissError() }.labelStyle(.iconOnly)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .toolbar {
            Menu("再生キューを管理", systemImage: "ellipsis.circle") {
                Button("すべて消去", systemImage: "trash", role: .destructive) { confirmsClear = true }
                    .disabled(queue.items.isEmpty)
            }
        }
        .confirmationDialog("再生キューの全項目を削除しますか？", isPresented: $confirmsClear) {
            Button("すべて削除", role: .destructive) { Task { await queue.clear() } }
        } message: {
            Text("音源ファイルは削除されません。現在の再生も停止しません。")
        }
    }

    private var queueSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text("再生キュー").font(.headline)
                Text(queueSummaryText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("ドラッグして曲順を変更")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var queueList: some View {
        List(selection: $queue.selectedItemIDs) {
            ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                queueRow(item, index: index)
                    .tag(item.id)
                    .contextMenu {
                        Button("今すぐ再生") { Task { await queue.playItem(id: item.id) } }
                            .disabled(playback.selectedDevice?.supportsAVTransport != true)
                        if index != queue.currentIndex {
                            Button("次に再生", systemImage: "text.insert") {
                                Task { await queue.moveNext(itemIDs: [item.id]) }
                            }
                        }
                        Divider()
                        Button("再生キューから削除", role: .destructive) {
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
        .accessibilityLabel("再生キュー")
    }

    private func queueRow(_ item: QueueItem, index: Int) -> some View {
        HStack(spacing: 12) {
            queuePosition(index)
            if let track = queue.track(for: item) {
                CachedArtwork(track: track, library: library, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).lineLimit(1)
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if track.scanState == .missing {
                    Label("ファイルが見つかりません", systemImage: "exclamationmark.triangle")
                        .labelStyle(.iconOnly).foregroundStyle(.orange)
                }
                Text(formatQueueDuration(track.duration)).monospacedDigit().foregroundStyle(.secondary)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title2).foregroundStyle(.orange)
                    .frame(width: 42, height: 42)
                Text("ライブラリにない曲").foregroundStyle(.orange)
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { Task { await queue.playItem(id: item.id) } }
        .listRowBackground(index == queue.currentIndex ? Color.accentColor.opacity(0.09) : Color.clear)
    }

    private func queuePosition(_ index: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: queuePositionIcon(index))
                .font(.callout)
                .foregroundStyle(index == queue.currentIndex ? Color.accentColor : Color.secondary)
            Text(queuePositionLabel(index))
                .font(.caption2)
                .foregroundStyle(index == queue.currentIndex ? Color.accentColor : Color.secondary)
        }
        .frame(width: 56)
        .accessibilityElement(children: .combine)
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                selectionSummary
                Spacer()
                selectionActions
            }
            VStack(alignment: .leading, spacing: 9) {
                selectionSummary
                selectionActions
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var selectionSummary: some View {
        Text(queue.selectedItemIDs.isEmpty ? "曲を選択して順番を編集" : "\(queue.selectedItemIDs.count)曲を選択中")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var selectionActions: some View {
        HStack(spacing: 10) {
            Button("次に再生", systemImage: "text.insert") { Task { await queue.moveSelectedNext() } }
                .disabled(movableSelectionCount == 0)
            Button("削除", systemImage: "trash", role: .destructive) { Task { await queue.removeSelected() } }
                .disabled(queue.selectedItemIDs.isEmpty)
        }
    }

    private var movableSelectionCount: Int {
        queue.items.enumerated().reduce(0) { result, value in
            result + (queue.selectedItemIDs.contains(value.element.id) && value.offset != queue.currentIndex ? 1 : 0)
        }
    }

    private var queueSummaryText: String {
        guard let current = queue.currentIndex else { return "\(queue.items.count)曲" }
        let remaining = max(0, queue.items.count - current - 1)
        return "\(queue.items.count)曲 · あと\(remaining)曲"
    }

    private func queuePositionIcon(_ index: Int) -> String {
        guard let current = queue.currentIndex else { return index == 0 ? "text.insert" : "line.3.horizontal" }
        if index < current { return "checkmark" }
        if index == current { return "speaker.wave.2.fill" }
        if index == current + 1 { return "text.insert" }
        return "line.3.horizontal"
    }

    private func queuePositionLabel(_ index: Int) -> String {
        guard let current = queue.currentIndex else { return index == 0 ? "次" : "その後" }
        if index < current { return "再生済み" }
        if index == current { return "再生中" }
        if index == current + 1 { return "次" }
        return "その後"
    }
}

struct QueueModeControls: View {
    @Bindable var queue: QueueStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await queue.toggleShuffle() }
            } label: {
                Image(systemName: queue.shuffleEnabled ? "shuffle.circle.fill" : "shuffle")
            }
            .accessibilityLabel(queue.shuffleEnabled ? "シャッフル：オン" : "シャッフル：オフ")
            .help(queue.shuffleEnabled ? "シャッフルを解除" : "シャッフルを有効にする")

            Button {
                Task { await queue.setRepeatMode(nextRepeatMode) }
            } label: {
                Image(systemName: repeatIcon)
            }
            .accessibilityLabel("リピート：\(repeatLabel)")
            .help("リピートを変更（現在：\(repeatLabel)）")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
    }

    private var nextRepeatMode: QueueRepeatMode {
        switch queue.repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    private var repeatIcon: String {
        switch queue.repeatMode {
        case .off: "repeat"
        case .all: "repeat.circle.fill"
        case .one: "repeat.1.circle.fill"
        }
    }

    private var repeatLabel: String {
        switch queue.repeatMode {
        case .off: "オフ"
        case .all: "全曲"
        case .one: "1曲"
        }
    }
}

private func formatQueueDuration(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "—" }
    let total = Int(seconds.rounded()); return String(format: "%d:%02d", total / 60, total % 60)
}
