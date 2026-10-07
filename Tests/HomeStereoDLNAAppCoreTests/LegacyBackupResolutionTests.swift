import Foundation
import XCTest
import HomeStereoAppCore
@testable import HomeStereoDLNAAppCore

final class LegacyBackupResolutionTests: XCTestCase {
    func testVersionOneImportKeepsExistingTagsAndCanonicalPlaylistID() throws {
        let existing = Playlist(myMusicPlaylistID: UUID(), name: "Existing", tags: ["Keep"])
        let imported = BackupPlaylist(id: existing.id, name: "Restored", createdAt: existing.createdAt,
                                      updatedAt: existing.updatedAt, tracks: [])
        let document = HomeStereoBackup(exportedAt: .now, appVersion: "test", playlists: [imported],
                                       favorites: [], playbackEvents: [], settings: .init(automaticLibraryUpdates: true))
        let resolved = BackupStore.resolve(document, tracks: [], existingPlaylists: [existing], existingFavorites: [], existingEvents: [])
        XCTAssertEqual(resolved.playlists.first?.tags, existing.tags)
        XCTAssertEqual(resolved.playlists.first?.myMusicPlaylistID, existing.myMusicPlaylistID)
        XCTAssertEqual(resolved.playlists.first?.name, "Restored")
    }
}
