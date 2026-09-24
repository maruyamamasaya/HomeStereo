#if canImport(HomeStereoDLNAAppCore)
import HomeStereoDLNAAppCore
#endif
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import SwiftUI

enum ListeningViewMode: Equatable { case favorites, history }

struct ListeningView: View {
    @Bindable var store: ListeningStore
    @Bindable var queue: QueueStore
    let mode: ListeningViewMode
    @State private var historySection = 0
    @State private var resetConfirmation: ListeningViewMode?

    var body: some View {
        VStack(spacing: 0) {
            if mode == .favorites { favorites }
            else { history }
        }
        .navigationTitle(mode == .favorites ? "Favorite" : "再生履歴")
        .alert("再生データ", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.dismissMessage() } })) {
            Button("OK") { store.dismissMessage() }
        } message: { Text(store.message ?? "") }
        .confirmationDialog(
            resetConfirmation == .favorites ? "Favoriteをすべて解除しますか？" : "再生履歴をすべて削除しますか？",
            isPresented: Binding(get: { resetConfirmation != nil }, set: { if !$0 { resetConfirmation = nil } })
        ) {
            if resetConfirmation == .favorites {
                Button("Favoriteをリセット", role: .destructive) { resetConfirmation = nil; Task { await store.resetFavorites() } }
            } else {
                Button("履歴をリセット", role: .destructive) { resetConfirmation = nil; Task { await store.resetHistory() } }
            }
        }
    }

    private var favorites: some View {
        VStack(spacing: 0) {
            HStack {
                Button("再生", systemImage: "play.fill") { Task { await store.playFavorites(shuffled: false) } }
                Button("Shuffle", systemImage: "shuffle") { Task { await store.playFavorites(shuffled: true) } }
                Spacer()
                Button("Favoriteをリセット", role: .destructive) { resetConfirmation = .favorites }
            }.padding()
            List(store.favorites) { favorite in
                trackRow(trackID: favorite.trackID, detail: favorite.addedAt.formatted())
                    .contextMenu { Button("Favoriteを解除") { Task { await store.toggleFavorite(favorite.trackID) } } }
            }
        }
    }

    private var history: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $historySection) {
                Text("最近再生").tag(0); Text("よく聴く").tag(1); Text("未再生").tag(2)
            }.pickerStyle(.segmented).padding()
            List {
                if historySection == 0 {
                    ForEach(store.events) { event in
                        trackRow(trackID: event.trackID, detail: "\(event.startedAt.formatted()) · \(Int(event.playedSeconds))秒 · \(event.outcome == .completed ? "完走" : "途中停止")")
                    }
                } else if historySection == 1 {
                    ForEach(store.frequentTracks) { value in trackRow(trackID: value.trackID, detail: "\(value.playCount)回") }
                } else {
                    ForEach(store.unplayedTracks) { track in trackRow(trackID: track.id, detail: "未再生") }
                }
            }
            HStack { Spacer(); Button("履歴をリセット", role: .destructive) { resetConfirmation = .history } }.padding()
        }
    }

    private func trackRow(trackID: Track.ID, detail: String) -> some View {
        HStack {
            if let track = store.track(id: trackID) {
                VStack(alignment: .leading) { Text(track.title); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if track.scanState == .missing { Label("missing", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Button("再生", systemImage: "play.fill") { Task { await queue.playNow(trackIDs: [trackID]) } }.labelStyle(.iconOnly)
            } else {
                Label("未解決の曲", systemImage: "exclamationmark.triangle")
                Spacer(); Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
