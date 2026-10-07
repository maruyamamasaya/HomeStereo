#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

struct PlaylistTagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: PlaylistStore
    let playlist: Playlist
    let suggestedTags: [String]
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(store: PlaylistStore, playlist: Playlist, suggestedTags: [String]) {
        self.store = store
        self.playlist = playlist
        self.suggestedTags = suggestedTags
        _tags = State(initialValue: playlist.tags)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(playlist.name)のタグ").font(.title2.bold())
            Text("タグは20個まで、1個につき40文字以内。MyMusicとのJSON連携にも含まれます。")
                .foregroundStyle(.secondary)
            List {
                ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                    HStack {
                        Label(tag, systemImage: "tag")
                        Spacer()
                        Button("削除", systemImage: "minus.circle") { tags.remove(at: index) }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("\(tag)を削除")
                    }
                }
            }
            HStack {
                TextField("新しいタグ", text: $newTag).onSubmit { addTag(newTag) }
                Button("追加") { addTag(newTag) }
                    .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Menu("既存のタグから選ぶ") {
                    ForEach(suggestedTags, id: \.self) { tag in
                        Button(tag) { addTag(tag) }
                    }
                }.disabled(suggestedTags.isEmpty)
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isSaving ? "保存中…" : "保存") {
                    isSaving = true
                    Task {
                        if await store.setTags(tags, for: playlist.id) { dismiss() }
                        else { errorMessage = store.message ?? "保存できませんでした。" }
                        isSaving = false
                    }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 400)
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
    }

    private func addTag(_ value: String) {
        do {
            tags = try PlaylistTagRules.validatedTags(tags + [value])
            newTag = ""
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
}
