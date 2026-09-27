import Foundation
import XCTest
@testable import HomeStereoAppCore

final class MyMusicPlaybackSessionTests: XCTestCase {
    func testPositionDeltasExcludePauseAndSeekAndResumeKeepsEvent() throws {
        let trackID = UUID()
        var session = makeSession(trackID: trackID, duration: 100)
        let eventID = session.eventID
        session.observe(position: 10)
        session.observe(position: 12)
        session.setPlaying(false)
        session.observe(position: 20)
        session.setPlaying(true)
        session.observe(position: 20)
        session.observe(position: 22)
        session.observe(position: 70) // seek
        session.observe(position: 72)

        XCTAssertEqual(session.eventID, eventID)
        XCTAssertEqual(session.listenedSeconds, 6, accuracy: 0.001)
    }

    func testCompletionAndSkipRulesAndDoubleFinalize() throws {
        var short = makeSession(duration: 100)
        short.observe(position: 0)
        short.observe(position: 50)
        short.observe(position: 51) // only the post-seek second is counted
        let skipped = try XCTUnwrap(short.finalize(reason: .userAdvanced))
        XCTAssertFalse(skipped.completed)
        XCTAssertTrue(skipped.skipped)
        XCTAssertNil(short.finalize(reason: .naturalEnd))

        var completed = makeSession(duration: 100)
        completed = sessionWithListenedSeconds(94, duration: 100)
        let advanced = try XCTUnwrap(completed.finalize(reason: .userAdvanced))
        XCTAssertTrue(advanced.completed)
        XCTAssertFalse(advanced.skipped)

        var natural = sessionWithListenedSeconds(94, duration: 100)
        let ended = try XCTUnwrap(natural.finalize(reason: .naturalEnd))
        XCTAssertTrue(ended.completed)
        XCTAssertFalse(ended.skipped)

        var stopped = sessionWithListenedSeconds(10, duration: 100)
        XCTAssertFalse(try XCTUnwrap(stopped.finalize(reason: .stop)).skipped)
        var failed = sessionWithListenedSeconds(10, duration: 100)
        XCTAssertFalse(try XCTUnwrap(failed.finalize(reason: .error)).skipped)
    }

    func testEventIdentityPlatformSelectionAndPlayCountPolicy() throws {
        let session = makeSession(source: .playlist, selection: .userAdvanced)
        XCTAssertTrue(session.eventID.hasPrefix("mac-"))
        XCTAssertNotNil(UUID(uuidString: String(session.eventID.dropFirst(4))))

        var value = session
        let event = try XCTUnwrap(value.finalize(reason: .stop))
        XCTAssertEqual(event.platform, "macOS")
        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.playSource, .playlist)
        XCTAssertEqual(event.selectionType, .userAdvanced)
        var automatic = makeSession(source: .queue, selection: .automatic)
        XCTAssertEqual(try XCTUnwrap(automatic.finalize(reason: .stop)).selectionType, .automatic)
        XCTAssertTrue(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 30, trackDuration: 100))
        XCTAssertFalse(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 29.9, trackDuration: 100))
        XCTAssertTrue(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 10, trackDuration: 20))
        XCTAssertFalse(MyMusicPlaybackPolicy.countsAsPlay(listenedSeconds: 9.9, trackDuration: 20))
        XCTAssertFalse(MyMusicPlaybackPolicy.isCompleted(listenedSeconds: 100, trackDuration: .nan))
        XCTAssertTrue(MyMusicPlaybackPolicy.isEarlySkip(skipped: true, listenedSeconds: 30))
        XCTAssertFalse(MyMusicPlaybackPolicy.isEarlySkip(skipped: true, listenedSeconds: 30.1))
    }

    private func makeSession(
        trackID: UUID = UUID(), duration: TimeInterval = 100,
        source: MyMusicPlaySource = .library, selection: MyMusicSelectionType = .manual
    ) -> MyMusicPlaybackSession {
        MyMusicPlaybackSession(
            eventID: "mac-\(UUID().uuidString.lowercased())", homeStereoTrackID: trackID,
            startedAt: Date(timeIntervalSince1970: 100), trackDuration: duration,
            playSource: source, selectionType: selection
        )
    }

    private func sessionWithListenedSeconds(
        _ seconds: Int, duration: TimeInterval
    ) -> MyMusicPlaybackSession {
        var session = makeSession(duration: duration)
        session.observe(position: 0)
        for position in 1...seconds { session.observe(position: TimeInterval(position)) }
        return session
    }
}
