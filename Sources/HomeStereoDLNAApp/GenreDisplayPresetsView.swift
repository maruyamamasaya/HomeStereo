#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct GenreDisplayPresetsView: View {
    @Bindable var store: GenreDisplayPresetStore
    @Bindable var library: LibraryStore
    @State private var editor: PresetDraft?
    @State private var deleting: GenreDisplayPreset?

    var body: some View {
        VStack(spacing: 0) {
            if store.presets.isEmpty {
                ContentUnavailableView {
                    Label("ジャンルプリセットがありません", systemImage: "tag")
                } description: {
                    Text("よく使うジャンルの組み合わせを作成すると、曲一覧上部のタグから切り替えられます。")
                } actions: {
                    Button("新規作成", systemImage: "plus") { editor = PresetDraft() }
                }
            } else {
                List {
                    ForEach(Array(store.presets.enumerated()), id: \.element.id) { index, preset in
                        presetRow(preset, index: index)
                    }
                }
            }
        }
        .navigationTitle("ジャンルプリセット")
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
            Group {
                Button("読み込む", systemImage: "square.and.arrow.down") { Task { await store.importJSON() } }
                Button("書き出す", systemImage: "square.and.arrow.up") { Task { await store.exportJSON() } }
                    .disabled(store.presets.isEmpty)
                Button("新規作成", systemImage: "plus") { editor = PresetDraft() }
            }

                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 10).homeStereoThemeBar()
        }
        .disabled(store.isBusy)
        .overlay { if store.isBusy { ProgressView().controlSize(.large) } }
        .sheet(item: $editor) { draft in
            PresetEditorView(draft: draft, libraryGenres: library.genres) { preset in
                Task { await store.save(preset) }
            }
        }
        .alert("プリセットを削除しますか？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("削除", role: .destructive) {
                guard let id = deleting?.id else { return }
                deleting = nil; Task { await store.delete(id) }
            }
            Button("キャンセル", role: .cancel) { deleting = nil }
        } message: { Text(deleting?.name ?? "") }
        .alert("ジャンルプリセット", isPresented: Binding(
            get: { store.errorMessage != nil || store.resultMessage != nil },
            set: { if !$0 { store.dismissMessages() } }
        )) {
            Button("OK") { store.dismissMessages() }
        } message: { Text(store.errorMessage ?? store.resultMessage ?? "") }
    }

    private func presetRow(_ preset: GenreDisplayPreset, index: Int) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name).font(.headline)
                Text(summary(preset)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("上へ", systemImage: "arrow.up") { Task { await store.move(preset.id, offset: -1) } }
                .labelStyle(.iconOnly).disabled(index == 0)
            Button("下へ", systemImage: "arrow.down") { Task { await store.move(preset.id, offset: 1) } }
                .labelStyle(.iconOnly).disabled(index == store.presets.count - 1)
            Button("編集", systemImage: "pencil") { editor = PresetDraft(preset) }
                .labelStyle(.iconOnly)
            Button("削除", systemImage: "trash", role: .destructive) { deleting = preset }
                .labelStyle(.iconOnly)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
    }

    private func summary(_ preset: GenreDisplayPreset) -> String {
        var values = preset.displayGenreNames
        if preset.includesUnassignedGenre { values.append("ジャンル未設定") }
        return "\(values.count)件 · " + (values.isEmpty ? "選択なし" : values.joined(separator: "、"))
    }
}

private struct PresetDraft: Identifiable {
    let id = UUID()
    let presetID: UUID
    var name: String
    var selectedGenres: Set<String>
    var includesUnassigned: Bool

    init() { presetID = UUID(); name = ""; selectedGenres = []; includesUnassigned = false }
    init(_ preset: GenreDisplayPreset) {
        presetID = preset.id; name = preset.name
        selectedGenres = Set(preset.displayGenreNames)
        includesUnassigned = preset.includesUnassignedGenre
    }
}

private struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PresetDraft
    @State private var query = ""
    let libraryGenres: [String]
    let onSave: (GenreDisplayPreset) -> Void

    init(draft: PresetDraft, libraryGenres: [String], onSave: @escaping (GenreDisplayPreset) -> Void) {
        _draft = State(initialValue: draft); self.libraryGenres = libraryGenres; self.onSave = onSave
    }

    private var candidates: [String] {
        let all = Set(libraryGenres).union(draft.selectedGenres)
            .subtracting(GenreDisplayPreset.fixedGenreNames)
            .filter { $0 != GenreDisplayPreset.unassignedGenreID }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return all.filter { needle.isEmpty || $0.localizedCaseInsensitiveContains(needle) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    TextField("プリセット名", text: $draft.name)
                    Toggle("ジャンル未設定を含める", isOn: $draft.includesUnassigned)
                    HStack {
                        Text("\(draft.selectedGenres.count + (draft.includesUnassigned ? 1 : 0))件を選択")
                        Spacer()
                        Button("すべて選択") {
                            draft.selectedGenres.formUnion(libraryGenres.filter { !GenreDisplayPreset.fixedGenreNames.contains($0) })
                        }
                        Button("すべて解除") { draft.selectedGenres.removeAll(); draft.includesUnassigned = false }
                    }
                }
                .formStyle(.grouped)
                List(candidates, id: \.self) { genre in
                    Button {
                        if draft.selectedGenres.contains(genre) { draft.selectedGenres.remove(genre) }
                        else { draft.selectedGenres.insert(genre) }
                    } label: {
                        HStack {
                            Text(genre).foregroundStyle(.primary)
                            Spacer()
                            if draft.selectedGenres.contains(genre) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(genre)、\(draft.selectedGenres.contains(genre) ? "選択中" : "未選択")")
                }
                .searchable(text: $query, prompt: "ジャンルを検索")
            }
            .navigationTitle(draft.name.isEmpty ? "プリセットを作成" : "プリセットを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var genres = draft.selectedGenres.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }.sorted()
                        if draft.includesUnassigned { genres.append(GenreDisplayPreset.unassignedGenreID) }
                        onSave(GenreDisplayPreset(
                            id: draft.presetID, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            enabledGenreNames: genres, includesUnassignedGenreSetting: true
                        ))
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
