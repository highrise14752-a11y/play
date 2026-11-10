// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Play

final class PlayTests: XCTestCase {
    @MainActor func testTogetherHostAndGuestPerformRealWebSocketHandshake() async throws {
        let hostPlayer = PlaybackController(api: MusicAPI())
        let guestPlayer = PlaybackController(api: MusicAPI())
        let host = TogetherSession(player: hostPlayer)
        let guest = TogetherSession(player: guestPlayer)
        defer { guest.leave(); host.leave() }
        host.host(name: "Host", addressOverride: "127.0.0.1")
        for _ in 0..<100 {
            if host.invite != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let invite = try XCTUnwrap(host.invite, host.error ?? "Host did not listen")
        guest.join(link: invite, name: "Guest")
        for _ in 0..<150 {
            if guest.connected && guest.participants.count == 2 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(guest.connected, guest.error ?? "Guest did not connect")
        XCTAssertEqual(Set(guest.participants.map(\.name)), Set(["Host", "Guest"]))
        XCTAssertTrue(host.isHost)
        XCTAssertFalse(guest.isHost)
    }

    func testTogetherInvitationRoundTripAndInvalidSchemes() {
        let invite = TogetherInvite(host: "192.168.1.20", port: 9090, sessionID: "room-1", key: "secret +&key")
        XCTAssertEqual(TogetherInvite.parse(invite.link), invite)
        XCTAssertEqual(TogetherInvite.parse(invite.link.replacingOccurrences(of: "play://", with: "velune://")), invite)
        XCTAssertNil(TogetherInvite.parse("https://example.com/?sid=x&key=y"))
        XCTAssertNil(TogetherInvite.parse("play://together?host=192.168.1.20&port=0&sid=x&key=y"))
        XCTAssertNil(TogetherInvite.parse("play://together?host=192.168.1.20&port=80&sid=x"))
        XCTAssertNil(TogetherInvite.parse("wss://example.com/together?sid=x&key=y"))
    }

    func testAndroidTogetherRoomDecodes() throws {
        let json = #"{"sessionId":"room","hostId":"host","participants":[{"id":"host","name":"Android","isHost":true,"isPending":false,"isConnected":true}],"settings":{"allowGuestsToAddTracks":true,"allowGuestsToControlPlayback":false,"requireHostApprovalToJoin":false},"queue":[{"id":"song","title":"Song","artists":["Artist"],"durationSec":120}],"queueHash":"hash","currentIndex":0,"isPlaying":true,"positionMs":12000,"repeatMode":0,"shuffleEnabled":false,"sentAtElapsedRealtimeMs":12345}"#
        let room = try JSONDecoder().decode(TogetherRoom.self, from: Data(json.utf8))
        XCTAssertEqual(room.queue[0].song.id, "song")
        XCTAssertEqual(room.queue[0].song.artist, "Artist")
        XCTAssertEqual(room.positionMs, 12000)
        XCTAssertFalse(room.settings.allowGuestsToControlPlayback)
    }

    func testHapticFrequencyFiltersAndSilence() {
        func energy(_ frequency: Double, mode: HapticMode) -> Double {
            var analyzer = HapticEnergy(mode: mode)
            var sum = 0.0
            for i in 0..<4410 {
                let sample = Float(sin(2 * .pi * frequency * Double(i) / 44100) * 0.5)
                let value = analyzer.sample(sample)
                if i > 440 { sum += value }
            }
            return sum
        }
        XCTAssertGreaterThan(energy(90, mode: .bass), energy(4000, mode: .bass) * 5)
        XCTAssertGreaterThan(energy(1200, mode: .vocals), energy(60, mode: .vocals) * 2)
        var silence = HapticEnergy()
        XCTAssertEqual(silence.sample(0), 0)
        XCTAssertEqual(silence.sample(.nan), 0)
    }

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
