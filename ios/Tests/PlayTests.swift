// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Play

final class PlayTests: XCTestCase {
    func testLRCFractionsRepeatedTimestampsAndMetadata() {
        let lines = LyricsParser.parse("[ar:Artist]\n[00:01.50][00:03.005]Hello\n[00:02.7]World")
        XCTAssertEqual(lines.map(\.text), ["Hello", "World", "Hello"])
        XCTAssertEqual(lines.compactMap(\.time), [1.5, 2.7, 3.005])
        XCTAssertEqual(lines.map(\.id), [0, 1, 2])
    }

    func testOffsetAndUnicodeArePreserved() {
        let lines = LyricsParser.parse("[offset:-500]\n[00:01.00]世界\n[00:05.00]مرحبا")
        XCTAssertEqual(lines.compactMap(\.time), [0.5, 4.5])
        XCTAssertEqual(lines.map(\.text), ["世界", "مرحبا"])
    }

    func testActiveLineRecomputesAfterSongChangesAndSeek() {
        let first = LyricsParser.parse("[00:01.00]A\n[00:05.00]B")
        let next = LyricsParser.parse("[00:10.00]C\n[00:20.00]D")
        XCTAssertEqual(LyricsParser.activeIndex(in: first, at: 8), 1)
        XCTAssertNil(LyricsParser.activeIndex(in: next, at: 0))
        XCTAssertEqual(LyricsParser.activeIndex(in: next, at: 11), 0)
        XCTAssertEqual(LyricsParser.activeIndex(in: next, at: 22), 1)
        XCTAssertEqual(LyricsParser.activeIndex(in: next, at: 10), 0)
        XCTAssertNil(LyricsParser.activeIndex(in: next, at: .nan))
    }

    func testPlainLyricsNeverInventSynchronization() {
        let lines = LyricsParser.parse("First line\n\nSecond line")
        XCTAssertEqual(lines.map(\.text), ["First line", "Second line"])
        XCTAssertTrue(lines.allSatisfy { $0.time == nil })
        XCTAssertNil(LyricsParser.activeIndex(in: lines, at: 100))
    }

    func testSearchParsesSongRowsWithoutDuplicates() throws {
        let fixture = #"{"contents":[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"song-1"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Title"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist","navigationEndpoint":{"browseEndpoint":{"browseId":"artist-1"}}}]}}}]}},{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"song-1"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Duplicate"}]}}}]}}]}"#
        let songs = MusicAPI.parseSearch(try JSONSerialization.jsonObject(with: Data(fixture.utf8)))
        XCTAssertEqual(songs.count, 1)
        XCTAssertEqual(songs[0].id, "song-1")
        XCTAssertEqual(songs[0].title, "Title")
        XCTAssertEqual(songs[0].artist, "Artist")
    }

    func testLibrarySongRoundTripKeepsRelativeDownloadPath() throws {
        let song = Song(id: "local:1", title: "Audio", artist: "Artist", duration: 120, localFile: "test.m4a")
        let restored = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        XCTAssertEqual(restored, song)
        XCTAssertTrue(restored.isLocal)
        XCTAssertEqual(restored.localFile, "test.m4a")
    }
}
