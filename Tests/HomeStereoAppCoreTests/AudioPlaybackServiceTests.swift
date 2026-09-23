import Foundation
import XCTest
@testable import HomeStereoAppCore

@MainActor
final class AudioPlaybackServiceTests: XCTestCase {
    func testPlayRebuildsCurrentItemAfterQueueReachedEnd() throws {
        let service = AudioPlaybackService()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let track = Track(url: url, title: "Test")
        try service.load(queue: [track], startingAt: 0)
        service.player.removeAllItems()

        service.play()

        XCTAssertNotNil(service.player.currentItem)
    }
}
