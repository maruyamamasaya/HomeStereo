import Foundation
#if canImport(HomeStereoAppCore)
import HomeStereoAppCore
#endif
import Observation

public struct GenrePresetImportResult: Equatable, Sendable {
    public let added: Int
    public let updated: Int
    public let duplicates: Int
}

@MainActor
@Observable
public final class GenreDisplayPresetStore {
    public private(set) var presets: [GenreDisplayPreset] = []
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var resultMessage: String?

    @ObservationIgnored private let repository: any GenreDisplayPresetPersisting
    @ObservationIgnored private let files: any MyMusicFileServicing
    @ObservationIgnored public var onChange: (@MainActor ([GenreDisplayPreset]) -> Void)?

    public init(repository: any GenreDisplayPresetPersisting, files: any MyMusicFileServicing) {
        self.repository = repository; self.files = files
    }

    public func load() async {
        do { presets = try await repository.loadGenreDisplayPresets(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    public func save(_ preset: GenreDisplayPreset) async {
        guard !isBusy else { return }
        var next = presets
        if let index = next.firstIndex(where: { $0.id == preset.id }) { next[index] = preset }
        else { next.append(preset) }
        await replace(next, message: "プリセットを保存しました。")
    }

    public func delete(_ id: UUID) async {
        await replace(presets.filter { $0.id != id }, message: "プリセットを削除しました。")
    }

    public func move(_ id: UUID, offset: Int) async {
        guard let source = presets.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard presets.indices.contains(destination) else { return }
        var next = presets
        next.swapAt(source, destination)
        await replace(next, message: nil)
    }

    public func importJSON() async {
        guard !isBusy, let url = files.chooseImportURL() else { return }
        isBusy = true; clearMessages()
        defer { isBusy = false }
        do {
            let incoming = try GenreDisplayPresetCodec.decode(files.read(from: url)).presets
            var merged = presets
            var added = 0, updated = 0, duplicates = 0
            var existingIDs = Set(merged.map(\.id))
            for value in incoming {
                let nameKey = GenreDisplayPresetCodec.normalized(value.name)
                if let index = merged.firstIndex(where: { GenreDisplayPresetCodec.normalized($0.name) == nameKey }) {
                    let existingID = merged[index].id
                    merged[index] = GenreDisplayPreset(
                        id: existingID, name: value.name, enabledGenreNames: value.enabledGenreNames,
                        includesUnassignedGenreSetting: value.includesUnassignedGenreSetting
                    )
                    updated += 1; duplicates += 1
                } else {
                    let id = existingIDs.contains(value.id) ? UUID() : value.id
                    merged.append(GenreDisplayPreset(
                        id: id, name: value.name, enabledGenreNames: value.enabledGenreNames,
                        includesUnassignedGenreSetting: value.includesUnassignedGenreSetting
                    ))
                    existingIDs.insert(id); added += 1
                }
            }
            try await repository.replaceGenreDisplayPresets(merged)
            presets = merged; onChange?(merged)
            resultMessage = "読み込み完了：追加 \(added)件、更新 \(updated)件、同名 \(duplicates)件"
        } catch { errorMessage = error.localizedDescription }
    }

    public func exportJSON() async {
        guard !isBusy, let url = files.chooseExportURL(defaultFileName: GenreDisplayPresetCodec.fileName) else { return }
        isBusy = true; clearMessages()
        defer { isBusy = false }
        do {
            try files.write(GenreDisplayPresetCodec.encode(presets), to: url)
            resultMessage = "\(url.lastPathComponent)を書き出しました。"
        } catch { errorMessage = error.localizedDescription }
    }

    public func dismissMessages() { clearMessages() }

    private func replace(_ next: [GenreDisplayPreset], message: String?) async {
        guard !isBusy else { return }
        isBusy = true; clearMessages()
        defer { isBusy = false }
        do {
            try await repository.replaceGenreDisplayPresets(next)
            presets = next; onChange?(next); resultMessage = message
        } catch { errorMessage = error.localizedDescription }
    }

    private func clearMessages() { errorMessage = nil; resultMessage = nil }
}
