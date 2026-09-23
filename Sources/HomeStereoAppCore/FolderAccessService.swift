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
        let data = try folder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        try bookmarks.save(data)
    }

    public func restoreFolder() throws -> URL? {
        guard let data = try bookmarks.load() else { return nil }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            try? bookmarks.remove()
            throw UserFacingError.folderAccessLost
        }
        if isStale { try saveBookmark(for: url) }
        return url
    }

    public func beginAccessing(_ folder: URL) -> Bool {
        folder.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ folder: URL) {
        folder.stopAccessingSecurityScopedResource()
    }
}
