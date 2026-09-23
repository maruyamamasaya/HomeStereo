import Foundation
import XCTest
@testable import HomeStereoAppCore

@MainActor
final class FolderAccessServiceTests: XCTestCase {
    func testBookmarkPersistenceBoundaryUsesInjectedStore() throws {
        let storage = MemoryBookmarkStore()
        let service = FolderAccessService(bookmarks: storage)
        let folder = FileManager.default.temporaryDirectory

        try service.saveBookmark(for: folder)
        let restored = try service.restoreFolder()

        XCTAssertNotNil(storage.data)
        XCTAssertEqual(restored?.standardizedFileURL, folder.standardizedFileURL)
    }
}

private final class MemoryBookmarkStore: BookmarkStoring, @unchecked Sendable {
    var data: Data?
    func save(_ data: Data) throws { self.data = data }
    func load() throws -> Data? { data }
    func remove() throws { data = nil }
}
