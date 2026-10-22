#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QueueView: View {
    @Bindable var playback: RendererPlaybackStore
    @Bindable var queue: QueueStore
    @Bindable var library: LibraryStore
    @State private var clearConfirmation = false
    @State private var showsPlayedItems = false
    @State private var isAppendTargeted = false
    @State private var dropOffset: Int?
    var body: some View {
        Group {
            if queue.items.isEmpty {
                ContentUnavailableView {
                    Label("再生キューは空です", systemImage: "text.line.first.and.arrowtriangle.forward")
                } description: {
                    Text("曲をここへドラッグするか、曲、アルバム、プレイリストから追加してください。")
                } actions: {
                    Button("曲を選ぶ") { playback.destination = .songs }
                }
                .background(isAppendTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                .dropDestination(for: String.self) { values, _ in handleAppendDrop(values) }
                    isTargeted: { isAppendTargeted = $0 }
            } else {
                VStack(spacing: 0) {
                    queueSummary
                    Divider()
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            queueList
                                .frame(height: min(CGFloat(visibleQueueEntries.count) * 70 + 16,
                                    max(0, geometry.size.height - 90)))
                            queueAppendArea
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
        }
        .background {
            QueueDropIndicatorCleanup(isActive: dropOffset != nil) { dropOffset = nil }
        }
        .onChange(of: isAppendTargeted) { _, targeted in
            if targeted { dropOffset = nil }
        }
        .onDisappear { dropOffset = nil }
        .navigationTitle("次はこちら")
        .confirmationDialog("再生キューをすべてクリアしますか？", isPresented: $clearConfirmation) {
            Button("キューをすべてクリア", role: .destructive) { Task { await queue.clear() } }
        } message: {
            Text("再生中の曲はそのまま続きます。音源・プレイリスト・再生履歴は削除されません。")
        }
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
                .homeStereoThemeBar()
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }

    private var queueSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("再生キュー（最大\(QueueStore.maximumItemCount)曲）").font(.headline)
                    Text(queueSummaryText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Button("すべてクリア", systemImage: "trash") { clearConfirmation = true }
                    .buttonStyle(.borderless)
                    .disabled(queue.isTransitioning)
                    .help("再生キューの全項目をクリア")
                Spacer(minLength: 0)
                if playedItemCount > 0 {
                    Button(showsPlayedItems ? "再生済みを隠す" : "再生済みを表示（\(playedItemCount)）",
                           systemImage: showsPlayedItems ? "eye.slash" : "eye") {
                        showsPlayedItems.toggle()
                        if !showsPlayedItems {
                            queue.selectedItemIDs.formIntersection(Set(visibleQueueEntries.map(\.item.id)))
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(14)
    }

    private var queueList: some View {
        List(selection: $queue.selectedItemIDs) {
            ForEach(visibleQueueEntries, id: \.item.id) { entry in
                let index = entry.index
                let item = entry.item
                queueRow(item, index: index)
                    .tag(item.id)
                    .modifier(QueueInsertionTarget(
                        index: index,
                        minimumOffset: showsPlayedItems ? 0 : (queue.currentIndex.map { $0 + 1 } ?? 0),
                        dropOffset: $dropOffset,
                        perform: { values, offset in handleDrop(values, at: offset) }
                    ))
                    .contextMenu {
                        Button("今すぐ再生") { Task { await queue.playItem(id: item.id) } }
                            .disabled(!playback.canPlaySelectedOutput)
                        if index != queue.currentIndex {
                            Button("次に再生", systemImage: "text.insert") {
                                Task { await queue.moveNext(itemIDs: [item.id]) }
                            }
                        }
                        Button("1つ上へ", systemImage: "arrow.up") {
                            Task { await queue.moveItem(id: item.id, by: -1) }
                        }
                        .disabled(
                            index == queue.currentIndex ||
                            index == 0 ||
                            (!showsPlayedItems && index == (queue.currentIndex ?? -2) + 1)
                        )
                        Button("1つ下へ", systemImage: "arrow.down") {
                            Task { await queue.moveItem(id: item.id, by: 1) }
                        }
                        .disabled(index == queue.currentIndex || index == queue.items.count - 1)
                        Divider()
                        Button("再生キューから削除", role: .destructive) {
                            queue.selectedItemIDs = [item.id]
                            Task { await queue.removeSelected() }
                        }
                    }
            }
            .onDelete { offsets in removeVisibleItems(at: offsets) }
        }
        .onDeleteCommand { Task { await queue.removeSelected() } }
        .accessibilityLabel("再生キュー")
    }

    private var queueAppendArea: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.badge.plus").font(.title2)
            Text(isAppendTargeted ? "ここにドロップしてキューの最後に追加" : "曲をここへドラッグして最後に追加")
                .font(.callout).multilineTextAlignment(.center)
        }
        .foregroundStyle(isAppendTargeted ? Color.accentColor : Color.secondary)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isAppendTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isAppendTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: isAppendTargeted ? 2 : 1, dash: [6, 4]))
                .padding(10)
        }
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in handleAppendDrop(values) }
            isTargeted: { isAppendTargeted = $0 }
        .accessibilityLabel("再生キューの最後へのドラッグ追加領域")
    }

    private func handleAppendDrop(_ values: [String]) -> Bool {
        if let movingID = values.compactMap(QueueItemDragPayload.decode).first {
            guard !queue.items.enumerated().contains(where: { $0.offset == queue.currentIndex && $0.element.id == movingID }) else { return false }
            Task { await queue.move(itemID: movingID, toOffset: queue.items.count) }
            return true
        }
        let ids = values.flatMap(TrackDragPayload.decode).filter { library.track(id: $0)?.scanState == .available }
        guard !ids.isEmpty else { return false }
        Task { await queue.append(trackIDs: ids) }
        return true
    }

    private func queueRow(_ item: QueueItem, index: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                if let track = queue.track(for: item) {
                    CachedArtwork(track: track, library: library, size: 42)
                        .overlay(alignment: .bottomLeading) {
                            if index == queue.currentIndex { currentPlaybackIndicator }
                        }
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
                } else {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.title2).foregroundStyle(.orange)
                        .frame(width: 42, height: 42)
                        .overlay(alignment: .bottomLeading) {
                            if index == queue.currentIndex { currentPlaybackIndicator }
                        }
                    Text("ライブラリにない曲").foregroundStyle(.orange)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { Task { await queue.playItem(id: item.id) } }

            Button(role: .destructive) {
                Task { await queue.remove(itemID: item.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("再生キューから削除")
            .accessibilityLabel("\(queue.track(for: item)?.title ?? "この曲")を再生キューから削除")

            reorderHandle(item, index: index)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 50)
        .listRowBackground(queueRowBackground(item, index: index))
    }

    private var currentPlaybackIndicator: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(4)
            .background(Color.accentColor, in: Circle())
            .offset(x: -3, y: 3)
            .accessibilityLabel("再生中")
    }

    @ViewBuilder
    private func reorderHandle(_ item: QueueItem, index: Int) -> some View {
        let handle = Image(systemName: "line.3.horizontal")
            .font(.body.weight(.semibold))
            .foregroundStyle(index == queue.currentIndex ? Color.secondary.opacity(0.35) : Color.secondary)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .accessibilityLabel(index == queue.currentIndex ? "再生中の曲は移動できません" : "ドラッグして曲順を変更")

        if index == queue.currentIndex {
            handle.help("再生中の曲は移動できません")
        } else {
            handle
                .draggable(QueueItemDragPayload.encode(item.id))
                .help("ドラッグして曲順を変更")
        }
    }

    private var playedItemCount: Int {
        min(queue.currentIndex ?? 0, queue.items.count)
    }

    private var visibleQueueEntries: [(index: Int, item: QueueItem)] {
        Array(queue.items.enumerated()).compactMap { index, item in
            if !showsPlayedItems, index < playedItemCount { return nil }
            return (index, item)
        }
    }

    private func removeVisibleItems(at offsets: IndexSet) {
        let entries = visibleQueueEntries
        let absoluteOffsets = IndexSet(offsets.compactMap { entries.indices.contains($0) ? entries[$0].index : nil })
        Task { await queue.remove(atOffsets: absoluteOffsets) }
    }

    private func handleDrop(_ values: [String], at offset: Int) -> Bool {
        dropOffset = nil
        if let movingID = values.compactMap(QueueItemDragPayload.decode).first {
            guard !queue.items.enumerated().contains(where: { $0.offset == queue.currentIndex && $0.element.id == movingID }) else { return false }
            Task { await queue.move(itemID: movingID, toOffset: offset) }
            return true
        }
        let trackIDs = values.flatMap(TrackDragPayload.decode)
            .filter { library.track(id: $0)?.scanState == .available }
        guard !trackIDs.isEmpty else { return false }
        Task { await queue.insert(trackIDs: trackIDs, at: offset) }
        return true
    }

    private func queueRowBackground(_ item: QueueItem, index: Int) -> Color {
        if index == queue.currentIndex { return Color.accentColor.opacity(0.09) }
        return .clear
    }

    private var queueSummaryText: String {
        guard let current = queue.currentIndex else { return "\(queue.items.count)曲" }
        let remaining = max(0, queue.items.count - current - 1)
        return "\(queue.items.count)曲 · あと\(remaining)曲"
    }

}

/// SwiftUI may omit dropExited when a drag is cancelled or ends outside its target.
/// Observe only while a line is visible; this view never intercepts mouse events.
private struct QueueDropIndicatorCleanup: NSViewRepresentable {
    let isActive: Bool
    let clear: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.clear = clear
        view.setActive(isActive)
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.setActive(false) }

    final class MonitorView: NSView {
        var clear: (() -> Void)?
        private var timer: Timer?
        private var escapeMonitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func setActive(_ active: Bool) {
            if active {
                guard timer == nil else { return }
                timer = Timer(timeInterval: 0.05, target: self, selector: #selector(checkDrag), userInfo: nil, repeats: true)
                if let timer { RunLoop.main.add(timer, forMode: .common) }
                escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    if event.keyCode == 53 { self?.endDrag() }
                    return event
                }
            } else {
                timer?.invalidate()
                timer = nil
                if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
                escapeMonitor = nil
            }
        }

        @objc private func checkDrag() {
            guard let window else { endDrag(); return }
            let screenBounds = window.convertToScreen(convert(bounds, to: nil))
            if NSEvent.pressedMouseButtons & 1 == 0 || !screenBounds.contains(NSEvent.mouseLocation) {
                endDrag()
            }
        }

        private func endDrag() {
            setActive(false)
            clear?()
        }
    }
}

private struct QueueInsertionTarget: ViewModifier {
    let index: Int
    let minimumOffset: Int
    @Binding var dropOffset: Int?
    let perform: ([String], Int) -> Bool
    @State private var rowHeight: CGFloat = 58

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rowHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { _, height in rowHeight = height }
                }
            }
            .overlay(alignment: .top) { insertionLine(at: index) }
            .overlay(alignment: .bottom) { insertionLine(at: index + 1) }
            .onDrop(of: [UTType.text], delegate: QueueInsertionDropDelegate(
                index: index, minimumOffset: minimumOffset, rowHeight: rowHeight,
                dropOffset: $dropOffset, perform: perform
            ))
    }

    @ViewBuilder private func insertionLine(at offset: Int) -> some View {
        if dropOffset == offset {
            HStack(spacing: 0) {
                Circle().frame(width: 7, height: 7)
                Rectangle().frame(height: 2)
            }
            .foregroundStyle(Color.blue)
            .allowsHitTesting(false)
            .accessibilityLabel("キューの挿入位置")
        }
    }
}

private struct QueueInsertionDropDelegate: DropDelegate {
    let index: Int
    let minimumOffset: Int
    let rowHeight: CGFloat
    @Binding var dropOffset: Int?
    let perform: ([String], Int) -> Bool

    private func destination(_ info: DropInfo) -> Int {
        max(minimumOffset, index + (info.location.y >= rowHeight / 2 ? 1 : 0))
    }

    func dropEntered(info: DropInfo) { dropOffset = destination(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropOffset = destination(info)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { dropOffset = nil }

    func performDrop(info: DropInfo) -> Bool {
        let offset = destination(info)
        dropOffset = nil
        let providers = info.itemProviders(for: [UTType.text])
        guard !providers.isEmpty else { return false }
        // Decode all providers in drag order before changing the queue.
        Task { @MainActor in
            var values: [String] = []
            for provider in providers {
                let value: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        continuation.resume(returning: object as? String)
                    }
                }
                if let value { values.append(value) }
            }
            _ = perform(values, offset)
        }
        return true
    }
}

private enum QueueItemDragPayload {
    private static let prefix = "home-stereo-queue-item:"

    static func encode(_ id: QueueItem.ID) -> String { prefix + id.uuidString }

    static func decode(_ value: String) -> QueueItem.ID? {
        guard value.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(value.dropFirst(prefix.count)))
    }
}

struct QueueModeControls: View {
    @Bindable var queue: QueueStore
    var largeButtons = false

    @ViewBuilder var body: some View {
        if largeButtons { controls.buttonStyle(PlaybackBarButtonStyle()) }
        else { controls.buttonStyle(.bordered) }
    }

    private var controls: some View {
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
