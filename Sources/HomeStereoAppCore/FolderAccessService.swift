import AppKit
import Foundation

public final class UserDefaultsBookmarkStore: BookmarkStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "musicFolderBookmark") {
        self.defaults = defaults
        self.key = key
    }

    public func save(_ data: Data) throws { defaults.set(data, forKey: key) }
    public func load() throws -> Data? { defaults.data(forKey: key) }
    public func remove() throws { defaults.removeObject(forKey: key) }
}

@MainActor
public final class FolderAccessService: FolderAccessServicing {
    private let bookmarks: BookmarkStoring

    public init(bookmarks: BookmarkStoring = UserDefaultsBookmarkStore()) {
        self.bookmarks = bookmarks
    }

    public func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "音楽フォルダを選択"
        panel.prompt = "選択"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func saveBookmark(for folder: URL) throws {
        try bookmarks.save(makeBookmark(for: folder))
    }

    public func makeBookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolveBookmark(_ data: Data) throws -> BookmarkResolution {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return BookmarkResolution(
                url: url,
                refreshedBookmark: isStale ? try makeBookmark(for: url) : nil
            )
        } catch {
            throw UserFacingError.folderAccessLost
        }
    }

    public func restoreFolder() throws -> URL? {
        guard let data = try bookmarks.load() else { return nil }
        do {
            let resolution = try resolveBookmark(data)
            if let refreshed = resolution.refreshedBookmark { try bookmarks.save(refreshed) }
            return resolution.url
        } catch {
            try? bookmarks.remove()
            throw UserFacingError.folderAccessLost
        }
    }

    public func beginAccessing(_ folder: URL) -> Bool {
        folder.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ folder: URL) {
        folder.stopAccessingSecurityScopedResource()
    }
}
