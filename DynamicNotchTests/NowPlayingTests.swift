//
//  NowPlayingTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class NowPlayingTrackTrackerTests: XCTestCase {
    func test_firstTitle_isBaseline_notAChange() {
        var tracker = NowPlayingTrackTracker()
        XCTAssertFalse(tracker.update(title: "A"))
    }

    func test_changes_areReportedOnce() {
        var tracker = NowPlayingTrackTracker()
        _ = tracker.update(title: "A")
        XCTAssertFalse(tracker.update(title: "A"))
        XCTAssertTrue(tracker.update(title: "B"))
        XCTAssertFalse(tracker.update(title: "B"))
    }

    func test_emptyTitle_isIgnored() {
        var tracker = NowPlayingTrackTracker()
        _ = tracker.update(title: "A")
        XCTAssertFalse(tracker.update(title: ""))
        XCTAssertFalse(tracker.update(title: "A"))
    }
}

final class PlayerTrackInfoTests: XCTestCase {
    func test_playing_readsTitleAndArtist() {
        let info = PlayerTrackInfo(userInfo: [
            "Player State": "Playing",
            "Name": "Clair de lune",
            "Artist": "Debussy"
        ])
        XCTAssertEqual(info, PlayerTrackInfo(title: "Clair de lune", artist: "Debussy", isPlaying: true))
    }

    func test_paused_keepsTrackButNotPlaying() {
        let info = PlayerTrackInfo(userInfo: ["Player State": "Paused", "Name": "A", "Artist": "B"])
        XCTAssertEqual(info, PlayerTrackInfo(title: "A", artist: "B", isPlaying: false))
    }

    func test_stopped_clearsTrack() {
        let info = PlayerTrackInfo(userInfo: ["Player State": "Stopped", "Name": "A"])
        XCTAssertEqual(info, PlayerTrackInfo(title: "", artist: "", isPlaying: false))
    }

    func test_missingState_isIgnored() {
        XCTAssertNil(PlayerTrackInfo(userInfo: ["Name": "A"]))
        XCTAssertNil(PlayerTrackInfo(userInfo: nil))
    }
}
