#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct PlaylistAdditionRequest: Identifiable {
    let id = UUID()
    let trackIDs: [Track.ID]
}

struct PlaylistDestinationPicker: View {
    @Bindable var store: PlaylistStore
    let trackIDs: [Track.ID]
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PlaylistKind = .regular
    @State private var tag: String?
    @State private var untaggedOnly = false
    @State private var destinationIDs = Set<UUID>()
    @State private var isSaving = false
    @State private var error: String?

    private var uniqueTrackIDs: [Track.ID] {
        var seen = Set<Track.ID>()
        return trackIDs.filter { seen.insert($0).inserted }
    }
    private var visiblePlaylists: [Playlist] {
        store.playlists(of: kind, tagged: tag, untaggedOnly: untaggedOnly)
    }
    private var selectedDestinations: [Playlist] {
        store.playlists.filter { destinationIDs.contains($0.id) }
    }
    private var missingCount: Int {
        selectedDestinations.reduce(0) { $0 + uniqueTrackIDs.count - store.addedTrackCount(uniqueTrackIDs, in: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("プレイリストに追加").font(.title2.bold())
            Text("対象：\(uniqueTrackIDs.count)曲 · 未追加の曲だけ追加します")
                .foregroundStyle(.secondary)
            Picker("プレイリストの種類", selection: $kind) {
                Text("通常用").tag(PlaylistKind.regular)
                Text("作業用BGM").tag(PlaylistKind.work)
            }.pickerStyle(.segmented)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterButton("すべて", active: tag == nil && !untaggedOnly) { tag = nil; untaggedOnly = false }
                    filterButton("タグなし", active: untaggedOnly) { tag = nil; untaggedOnly = true }
                    ForEach(store.tags(of: kind), id: \.self) { value in
                        filterButton(value, active: tag == value && !untaggedOnly) { tag = value; untaggedOnly = false }
                    }
                }
            }.frame(height: 34)
            List {
                if visiblePlaylists.isEmpty {
                    Text("該当するプレイリストがありません").foregroundStyle(.secondary)
                }
                ForEach(visiblePlaylists) { playlist in
                    let count = store.addedTrackCount(uniqueTrackIDs, in: playlist)
                    Toggle(isOn: Binding(
                        get: { destinationIDs.contains(playlist.id) },
                        set: { if $0 { destinationIDs.insert(playlist.id) } else { destinationIDs.remove(playlist.id) } }
                    )) {
                        HStack {
                            Text(playlist.name).lineLimit(2)
                            Spacer()
                            Text(count == uniqueTrackIDs.count ? "追加済み" : "\(count)／\(uniqueTrackIDs.count)曲追加済み")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(count == uniqueTrackIDs.count)
                }
            }.frame(minHeight: 220, idealHeight: 300, maxHeight: 360)
            Text("追加先：\(selectedDestinations.count)件 · 合計\(missingCount)曲を追加")
            if !selectedDestinations.isEmpty {
                Text(selectedDestinations.map(\.name).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("キャンセル", role: .cancel) { dismiss() }
                Button("追加") {
                    isSaving = true
                    error = nil
                    Task {
                        do {
                            try await store.addUnique(trackIDs: uniqueTrackIDs, to: Array(destinationIDs))
                            dismiss()
                        } catch { self.error = error.localizedDescription; isSaving = false }
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(missingCount == 0)
            }
        }
        .padding(24).frame(width: 560)
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .onChange(of: kind) { _, _ in tag = nil; untaggedOnly = false }
    }

    private func filterButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(active ? Color.accentColor : Color.secondary)
            .fixedSize()
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}
