//
//  MediaRemoteAdapterTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import XCTest

final class AdapterNowPlayingTests: XCTestCase {
    func test_dataLine_readsTrackAndArtwork() throws {
        let artwork = Data([0x89, 0x50, 0x4E, 0x47])
        let json = """
        {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.spotify.client","playing":true,\
        "title":"Clair de lune","artist":"Debussy","artworkData":"\(artwork.base64EncodedString())"}}
        """
        let state = try XCTUnwrap(AdapterNowPlaying(line: Data(json.utf8)))
        XCTAssertEqual(
            state,
            AdapterNowPlaying(title: "Clair de lune", artist: "Debussy", isPlaying: true, artworkData: artwork)
        )
    }

    func test_emptyPayload_meansNothingPlaying() {
        let line = Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)
        XCTAssertEqual(AdapterNowPlaying(line: line), AdapterNowPlaying(title: "", artist: "", isPlaying: false))
    }

    func test_otherLines_areIgnored() {
        XCTAssertNil(AdapterNowPlaying(line: Data("not json".utf8)))
        XCTAssertNil(AdapterNowPlaying(line: Data(#"{"type":"other","payload":{}}"#.utf8)))
    }
}

final class LineBufferTests: XCTestCase {
    func test_splitsCompleteLines_andKeepsTheRest() {
        var buffer = LineBuffer()
        XCTAssertEqual(buffer.append(Data("ab\ncd".utf8)), [Data("ab".utf8)])
        XCTAssertEqual(buffer.append(Data("e\n\nf\n".utf8)), [Data("cde".utf8), Data("f".utf8)])
        XCTAssertEqual(buffer.append(Data("g".utf8)), [])
    }
}
