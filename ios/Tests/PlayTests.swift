// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import AVFoundation
import UIKit
@testable import Play

final class PlayTests: XCTestCase {
    func testAudioNormalizationAttenuatesLoudSamplesAndDoesNotAmplifySilence() {
        var gain = AdaptiveGain()
        XCTAssertEqual(gain.update(rms: 0, frames: 48000, sampleRate: 48000), 1)
        let lowered = gain.update(rms: 0.5, frames: 48000, sampleRate: 48000)
        XCTAssertLessThan(lowered, 0.4)
        XCTAssertGreaterThan(lowered, 0.29)
        XCTAssertEqual(gain.update(rms: 0, frames: 48000, sampleRate: 48000), lowered)
        XCTAssertEqual(AdaptiveGain.limited(0.8, gain: 1.6), 0.98, accuracy: 0.001)
        XCTAssertEqual(AdaptiveGain.limited(-0.8, gain: 1.6), -0.98, accuracy: 0.001)
    }
    func testTTMLKeepsWordTimesAndSkipsAlternativeText() {
        let text = #"<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div><p begin="00:02.500"><span begin="2.5s">First</span> <span begin="3200ms">line</span><span ttm:role="x-translation">ignore</span></p><p begin="00:04.000">Next line</p></div></body></tt>"#
        let lines = TTMLLyrics.parse(text)
        XCTAssertEqual(lines.map(\.time), [2.5, 4])
        XCTAssertEqual(lines.map(\.text), ["First line", "Next line"])
        XCTAssertEqual(lines.first?.words.compactMap(\.time), [2.5, 3.2])
        XCTAssertEqual(LyricsParser.activeIndex(in: lines, at: 4), 1)
    }

    func testDisabledLyricsProviderCannotBecomeFirst() {
        XCTAssertEqual(LyricSource.ordered(enabled: [.lrcLib, .kuGou], preferred: .better), [.lrcLib, .kuGou])
        XCTAssertEqual(LyricSource.ordered(enabled: [.lrcLib, .better, .kuGou], preferred: .better), [.better, .lrcLib, .kuGou])
    }

    func testCatalogLinksAcceptYouTubeHostsAndRejectLookalikeURLs() {
        XCTAssertEqual(CatalogLink.parse("https://youtu.be/khnokW3Mw24?t=20"), .song("khnokW3Mw24"))
        XCTAssertEqual(CatalogLink.parse("https://music.youtube.com/playlist?list=PL123"), .playlist("PL123"))
        XCTAssertEqual(CatalogLink.parse("play://song?v=khnokW3Mw24"), .song("khnokW3Mw24"))
        XCTAssertNil(CatalogLink.parse("https://music.youtube.com.example.net/watch?v=khnokW3Mw24"))
        XCTAssertNil(CatalogLink.parse("https://www.youtube.com/watch?v=abc%2F1234567"))
    }

    func testFilesCopyNameCannotEscapeTheChosenFolder() throws {
        let song = Song(id: "1", title: "../" + String(repeating: "音", count: 100), artist: "A/B")
        let folder = URL(fileURLWithPath: "/target")
        let source = URL(fileURLWithPath: "/private/track.m4a")
        let name = DownloadFolder.fileName(for: song, source: source)
        let output = try DownloadFile.url(filename: name, directory: folder)
        XCTAssertEqual(output.deletingLastPathComponent().path, folder.path)
        XCTAssertTrue(name.hasSuffix("track.m4a"))
        XCTAssertLessThan(name.utf8.count, 255)
    }

    @MainActor func testHistoryCountsOnlyTracksReachingTheListeningThreshold() throws {
        let defaults = UserDefaults.standard
        let keys = ["privacy.pauseHistory", "player.historyMinimum"]
        let old = keys.map { defaults.object(forKey: $0) }
        defaults.set(false, forKey: keys[0])
        defaults.set(2.0, forKey: keys[1])
        defer { for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let collections = UserCollections(directory: root)
        let skipped = Song(id: "skip", title: "Skipped", artist: "Artist")
        let played = Song(id: "play", title: "Played", artist: "Artist")
        collections.started(skipped)
        collections.listened(1)
        XCTAssertTrue(collections.state.history.isEmpty)
        collections.started(played)
        collections.listened(1.25)
        collections.listened(1)
        XCTAssertEqual(collections.state.history.map(\.song.id), [played.id])
        XCTAssertEqual(collections.state.totals[played.id]?.seconds, 2.25)
    }

    @MainActor func testTogetherApprovalAndBanOverWebSocket() async throws {
        let host = TogetherSession(player: PlaybackController(api: MusicAPI()))
        let guest = TogetherSession(player: PlaybackController(api: MusicAPI()))
        defer { guest.leave(); host.leave() }
        host.requireApproval = true
        host.host(name: "Host", addressOverride: "127.0.0.1")
        for _ in 0..<100 {
            if host.invite != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let invite = try XCTUnwrap(host.invite)
        guest.join(link: invite, name: "Guest")
        for _ in 0..<100 {
            if guest.status == "Waiting for host approval" && host.participants.count == 2 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(guest.status, "Waiting for host approval")
        let member = try XCTUnwrap(host.participants.first { !$0.isHost })
        XCTAssertTrue(member.isPending)
        host.decide(member, approved: true)
        for _ in 0..<100 {
            if guest.participants.contains(where: { $0.id == member.id && !$0.isPending }) { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(guest.status, "Listening together")
        XCTAssertTrue(guest.participants.contains(where: { $0.id == member.id && !$0.isPending }))
        host.remove(member, ban: true)
        for _ in 0..<100 {
            if !guest.connected { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(guest.connected)
        guest.join(link: invite, name: "Guest")
        for _ in 0..<100 {
            if guest.error != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(guest.error?.contains("blocked") == true)
        XCTAssertEqual(host.participants.count, 1)
    }

    @MainActor func testRestoredQueueStaysPausedAndKeepsPosition() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: "player.persistentQueue")
        defaults.set(true, forKey: "player.persistentQueue")
        defer { defaults.set(old, forKey: "player.persistentQueue") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let first = Song(id: "first", title: "First", artist: "Artist")
        let second = Song(id: "second", title: "Second", artist: "Artist", duration: 180)
        let snapshot = SavedQueue(current: second, songs: [first, second], position: 42, shuffle: true, repeatMode: 2)
        try JSONEncoder().encode(snapshot).write(to: file)
        let player = PlaybackController(api: MusicAPI(), queueFile: file)
        XCTAssertEqual(player.current?.id, second.id)
        XCTAssertEqual(player.queue, [first, second])
        XCTAssertEqual(player.position, 42)
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(player.shuffleEnabled)
        XCTAssertEqual(player.repeatMode, .all)
        defaults.set(false, forKey: "player.persistentQueue")
        player.persistQueue()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTrackTimeFormatsMeasuredAudioAndLongSongs() {
        XCTAssertEqual(TrackTime.text(nil), "—")
        XCTAssertEqual(TrackTime.text(.nan), "—")
        XCTAssertEqual(TrackTime.text(185.97), "3:06")
        XCTAssertEqual(TrackTime.text(185.97, elapsed: true), "3:05")
        XCTAssertEqual(TrackTime.text(3723), "1:02:03")
    }

    func testActualAudioAssetDuration() async throws {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(20036)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1))
        number(UInt32(8000)); number(UInt32(16000)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(20000))
        data.append(Data(repeating: 0, count: 20000))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        let measured = try await AVURLAsset(url: url).load(.duration).seconds
        XCTAssertEqual(measured, 1.25, accuracy: 0.001)
    }

    @MainActor func testPlaylistLikesHistoryAndBackupPersistence() async throws {
        let previous = UserDefaults.standard.object(forKey: "privacy.pauseHistory")
        let minimum = UserDefaults.standard.object(forKey: "player.historyMinimum")
        UserDefaults.standard.set(false, forKey: "privacy.pauseHistory")
        UserDefaults.standard.set(0.0, forKey: "player.historyMinimum")
        defer {
            UserDefaults.standard.set(previous, forKey: "privacy.pauseHistory")
            UserDefaults.standard.set(minimum, forKey: "player.historyMinimum")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let collections = UserCollections(directory: root)
        let song = Song(id: "khnokW3Mw24", title: "Song", artist: "Artist")
        collections.createPlaylist("Favorites")
        let id = try XCTUnwrap(collections.state.playlists.first?.id)
        collections.setTags("Study, study, Favorite", for: id)
        collections.add(song, to: id); collections.add(song, to: id)
        XCTAssertEqual(collections.state.playlists[0].songIDs, [song.id])
        collections.toggleLike(song); XCTAssertTrue(collections.liked(song))
        collections.started(song); collections.listened(0.5); collections.flush()
        XCTAssertEqual(collections.state.totals[song.id]?.plays, 1)
        XCTAssertEqual(collections.state.totals[song.id]?.seconds, 0.5)
        let restored = UserCollections(directory: root)
        XCTAssertEqual(restored.state.playlists.first?.tags, ["Study", "Favorite"])
        XCTAssertTrue(restored.liked(song)); XCTAssertEqual(restored.state.history.count, 1)
        restored.restore(collections.state)
        XCTAssertEqual(restored.state.playlists.count, 1); XCTAssertEqual(restored.state.history.count, 1)
        let backup = PlayBackup(songs: [song], collections: collections.state)
        let decoded = try JSONDecoder().decode(PlayBackup.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(decoded.songs[0].id, song.id)
    }

    @MainActor func testRepeatShuffleSleepAndFont() async throws {
        let player = PlaybackController(api: MusicAPI())
        player.setRepeat(.all); player.setShuffle(true)
        XCTAssertEqual(player.repeatMode, .all); XCTAssertTrue(player.shuffleEnabled)
        player.setSleepTimer(minutes: 0.001)
        for _ in 0..<20 {
            if player.sleepDeadline == nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNil(player.sleepDeadline); XCTAssertTrue(player.isLocallySuspended)
        player.sleepAfterCurrentSong(); XCTAssertTrue(player.stopAtTrackEnd)
        player.setSleepTimer(minutes: nil); XCTAssertFalse(player.stopAtTrackEnd)
        XCTAssertNotNil(UIFont(name: "Poppins-Regular", size: 15))
    }

    func testIPhone7UsesLegacyHapticsWithoutEnablingUnsupportedDevices() {
        for model in ["iPhone9,1", "iPhone9,2", "iPhone9,3", "iPhone9,4"] {
            XCTAssertEqual(HapticBackend.select(coreSupported: false, model: model), .legacyImpact)
        }
        XCTAssertEqual(HapticBackend.select(coreSupported: true, model: "iPhone10,1"), .coreHaptics)
        XCTAssertEqual(HapticBackend.select(coreSupported: false, model: "iPad7,1"), .unavailable)
        XCTAssertEqual(HapticBackend.select(coreSupported: false, model: "iPhone8,4"), .unavailable)
        XCTAssertEqual(HapticBackend.select(coreSupported: false, model: "arm64"), .unavailable)
    }
    @MainActor func testSystemPauseBypassesGuestControlsAndSurvivesSynchronization() async {
        let player = PlaybackController(api: MusicAPI())
        var controls: [String] = []
        player.interceptControl = { action, _ in controls.append(action); return true }
        player.suspendForSystemEvent()
        XCTAssertTrue(player.isLocallySuspended)
        XCTAssertTrue(controls.isEmpty)
        player.synchronize(queue: [], position: 12, playing: true)
        XCTAssertTrue(player.isLocallySuspended)
        XCTAssertFalse(player.isPlaying)
        player.resume()
        XCTAssertFalse(player.isLocallySuspended)
        XCTAssertEqual(controls, ["play"])
    }

    func testLargeSharedQueuesKeepCurrentSongInABoundedWindow() {
        let queue = (0..<5000).map { Song(id: "song-\($0)", title: "Song", artist: "Artist") }
        for index in [0, 2500, 4999] {
            let window = TogetherQueue.window(queue, currentID: queue[index].id)
            XCTAssertLessThanOrEqual(window.count, 200)
            XCTAssertTrue(window.contains { $0.id == queue[index].id })
            XCTAssertEqual(Set(window.map(\.id)).count, window.count)
        }
        XCTAssertTrue(TogetherQueue.window(queue, currentID: nil, limit: 0).isEmpty)
        XCTAssertTrue(TogetherQueue.window([Song(id: "local:1", title: "Local", artist: "Artist")], currentID: "local:1").isEmpty)
    }

    func testSharedTrackValidationBoundsMetadataAndRejectsInvalidIDs() {
        var track = TogetherTrack(Song(id: "khnokW3Mw24", title: "Song", artist: "Artist"))
        track.title = String(repeating: "😀", count: 2000)
        track.artists = [String(repeating: "Artist", count: 2000)]
        track.thumbnailUrl = "file:///private/data"
        track.durationSec = Int.max
        let song = track.validatedSong
        XCTAssertNotNil(song)
        XCTAssertLessThanOrEqual(song!.title.utf8.count, 515)
        XCTAssertLessThanOrEqual(song!.artist.utf8.count, 259)
        XCTAssertNil(song!.artwork)
        XCTAssertEqual(song!.duration, 259200)
        track.id = "../../other"
        XCTAssertNil(track.validatedSong)
        let infinite = TogetherTrack(Song(id: "khnokW3Mw24", title: "Song", artist: "Artist", duration: .infinity))
        XCTAssertEqual(infinite.durationSec, -1)
    }

    func testDurationMetadataSupportsLongSongsAndRejectsInvalidValues() {
        XCTAssertEqual(MusicAPI.duration("5:38"), 338)
        XCTAssertEqual(MusicAPI.duration("1:02:03"), 3723)
        XCTAssertNil(MusicAPI.duration("Artist"))
        XCTAssertNil(MusicAPI.duration("1:99"))
        XCTAssertNil(MusicAPI.duration(":30"))
        XCTAssertEqual(MusicAPI.duration(" 6:10 "), 370)
        XCTAssertNil(MusicAPI.duration("LIVE"))
        XCTAssertNil(MusicAPI.duration("-1:20"))
    }

    func testDurationUsesEachTracksOwnColumnAndQueueLength() throws {
        let json = #"[{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"first"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"First"}]}}},{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Artist"},{"text":"5:38"}]}}}]}},{"musicResponsiveListItemRenderer":{"playlistItemData":{"videoId":"second"},"flexColumns":[{"musicResponsiveListItemFlexColumnRenderer":{"text":{"runs":[{"text":"Second"}]}}}],"fixedColumns":[{"musicResponsiveListItemFixedColumnRenderer":{"text":{"simpleText":"6:10"}}}]}},{"playlistPanelVideoRenderer":{"videoId":"third","title":{"simpleText":"Third"},"shortBylineText":{"runs":[{"text":"Artist"}]},"lengthText":{"simpleText":"1:02:03"}}},{"musicTwoRowItemRenderer":{"navigationEndpoint":{"watchEndpoint":{"videoId":"fourth"}},"title":{"runs":[{"text":"Fourth"}]},"subtitle":{"runs":[{"text":"Artist"},{"text":"LIVE"}]}}}]"#
        let songs = MusicAPI.parseSearch(try JSONSerialization.jsonObject(with: Data(json.utf8)))
        XCTAssertEqual(songs.map(\.duration), [338, 370, 3723, nil])
    }

    @MainActor func testMeasuredDurationSurvivesRestartAndStaleCatalogOrBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(directory: root)
        let stale = Song(id: "song", title: "Song", artist: "Artist", duration: 180)
        var actual = stale; actual.duration = 245.97
        library.recordMeasuredDuration(actual)
        XCTAssertFalse(library.contains(stale))
        let restored = LibraryStore(directory: root)
        XCTAssertEqual(restored.saved(stale).duration, 245.97)
        restored.save(stale)
        restored.merge([stale])
        XCTAssertEqual(restored.songs.first?.duration, 245.97)
        var invalid = stale; invalid.duration = .nan
        restored.recordMeasuredDuration(invalid)
        XCTAssertEqual(restored.saved(stale).duration, 245.97)
    }

    @MainActor func testLibraryPreservesAndReplacesDownloadsAndRemovesMissingFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(directory: root)
        library.save(Song(id: "song", title: "Old", artist: "Artist", localFile: "old.m4a"))
        let remote = Song(id: "song", title: "Updated", artist: "Artist")
        library.save(remote)
        XCTAssertEqual(library.saved(remote).localFile, "old.m4a")
        library.save(Song(id: "song", title: "Updated", artist: "Artist", localFile: "new.m4a"))
        XCTAssertEqual(library.saved(remote).localFile, "new.m4a")
        let restored = LibraryStore(directory: root)
        XCTAssertEqual(restored.saved(remote).localFile, "new.m4a")
        restored.remove(remote)
        XCTAssertFalse(restored.contains(remote))
        XCTAssertNil(restored.error)
    }

    @MainActor func testInvalidDownloadPathCannotDeleteAnUnrelatedFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(directory: root)
        let unrelated = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let song = Song(id: "song", title: "Song", artist: "Artist", localFile: "../keep.txt")
        library.save(song)
        library.remove(song)
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        XCTAssertThrowsError(try DownloadFile.url(filename: "../keep.txt", directory: root))
        XCTAssertThrowsError(try DownloadFile.url(filename: "/absolute.m4a", directory: root))
        XCTAssertThrowsError(try DownloadFile.url(filename: "..\\file", directory: root))
    }

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
