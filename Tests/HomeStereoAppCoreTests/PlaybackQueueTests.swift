import Foundation
import XCTest
@testable import HomeStereoAppCore

final class PlaybackQueueTests: XCTestCase {
    private let tracks = (0..<3).map {
        Track(url: URL(fileURLWithPath: "/tmp/\($0).m4a"), title: "Track \($0)")
    }

    func testMovesForwardAndStopsAtEnd() {
        var queue = PlaybackQueue(tracks: tracks, currentIndex: 0)
        XCTAssertEqual(queue.moveNext(), tracks[1])
        XCTAssertEqual(queue.moveNext(), tracks[2])
        XCTAssertNil(queue.moveNext())
        XCTAssertEqual(queue.currentTrack, tracks[2])
    }

    func testMovesBackwardAndStopsAtBeginning() {
        var queue = PlaybackQueue(tracks: tracks, currentIndex: 2)
        XCTAssertEqual(queue.movePrevious(), tracks[1])
        XCTAssertEqual(queue.movePrevious(), tracks[0])
        XCTAssertNil(queue.movePrevious())
        XCTAssertEqual(queue.currentTrack, tracks[0])
    }
}
