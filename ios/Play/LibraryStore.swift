// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AVFoundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var downloading = Set<String>()
    @Published var error: String?
    @Published private(set) var measuredDurations: [String: Double] = [:]
    @Published private(set) var searchHistory: [String] = UserDefaults.standard.stringArray(forKey: "search.history") ?? []
    let api: MusicAPI
    let player: PlaybackController
    let collections: UserCollections
    lazy var together = TogetherSession(player: player)
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let downloads = documents.appendingPathComponent("Downloads", isDirectory: true)
    private let index: URL
    private let durationIndex: URL
    private let downloadDirectory: URL
    private var songsByID: [String: Song] = [:]

    init(directory: URL? = nil) {
        let root = directory ?? Self.documents
        index = root.appendingPathComponent("library.json")
        durationIndex = root.appendingPathComponent("durations.json")
        downloadDirectory = root.appendingPathComponent("Downloads", isDirectory: true)
        collections = UserCollections(directory: root)
        let api = MusicAPI()
        self.api = api
        self.player = PlaybackController(api: api, downloadDirectory: downloadDirectory, queueFile: root.appendingPathComponent("queue.json"))
        player.onTrackStarted = { [weak collections] song in collections?.started(song) }
        player.onListeningTime = { [weak collections] seconds in collections?.listened(seconds) }
        player.onPaused = { [weak collections] in collections?.flush() }
        player.onDurationKnown = { [weak self] song in
            guard let self = self else { return }
            self.recordMeasuredDuration(song)
        }
        do {
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: index))
            }
            if let data = try? Data(contentsOf: durationIndex),
               let cached = try? JSONDecoder().decode([String: Double].self, from: data) {
                measuredDurations = Dictionary(uniqueKeysWithValues: cached.filter { $0.value.isFinite && $0.value > 0 }.prefix(2000).map { ($0.key, $0.value) })
            }
        } catch { self.error = "Could not load the saved library: \(error.localizedDescription)" }
        var seen = Set<String>()
        songs = songs.filter { seen.insert($0.id).inserted }
        songsByID = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
    }

    func contains(_ song: Song) -> Bool { songsByID[song.id] != nil }
    func saved(_ song: Song) -> Song {
        var result = songsByID[song.id] ?? song
        result.duration = measuredDurations[song.id] ?? result.duration
        return result
    }
    func save(_ song: Song) {
        var song = song
        song.duration = measuredDurations[song.id] ?? song.duration
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            var updated = song
            updated.localFile = song.localFile ?? songs[i].localFile
            songs[i] = updated
        } else { songs.append(song) }
        if let updated = songs.first(where: { $0.id == song.id }) { songsByID[song.id] = updated }
        persist()
    }

    // Cache actual media lengths, including tracks not added to the library. Never
    // resolve every search result: that would add network work while scrolling.
    func recordMeasuredDuration(_ song: Song) {
        guard let value = song.duration, value.isFinite, value > 0,
              measuredDurations[song.id].map({ abs($0 - value) > 0.01 }) ?? true else { return }
        measuredDurations[song.id] = value
        if measuredDurations.count > 2000, let old = measuredDurations.keys.first(where: { $0 != song.id }) { measuredDurations[old] = nil }
        if contains(song) { save(song) }
        do { try JSONEncoder().encode(measuredDurations).write(to: durationIndex, options: .atomic) }
        catch { self.error = "Could not save the measured song length: \(error.localizedDescription)" }
    }

    func play(_ song: Song, in queue: [Song]) {
        player.play(saved(song), queue: queue.map(saved))
    }

    func toggleLike(_ song: Song) {
        let track = saved(song)
        if !contains(track) { save(track) }
        collections.toggleLike(track)
        if collections.liked(track), !track.isLocal, track.localFile == nil,
           UserDefaults.standard.bool(forKey: "player.downloadLikes") {
            Task { await download(track) }
        }
    }

    func rememberSearch(_ term: String) {
        guard !UserDefaults.standard.bool(forKey: "privacy.pauseSearch") else { return }
        let term = String(term.trimmingCharacters(in: .whitespacesAndNewlines).prefix(250))
        guard !term.isEmpty else { return }
        searchHistory.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        searchHistory.insert(term, at: 0)
        searchHistory = Array(searchHistory.prefix(30))
        UserDefaults.standard.set(searchHistory, forKey: "search.history")
    }

    func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: "search.history")
    }

    func clearDownloads() {
        for index in songs.indices {
            let song = songs[index]
            guard !song.isLocal, !downloading.contains(song.id), let file = song.localFile else { continue }
            do {
                let url = try DownloadFile.url(filename: file, directory: downloadDirectory)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                songs[index].localFile = nil
                songsByID[song.id] = songs[index]
            } catch { self.error = "Could not remove some downloads: \(error.localizedDescription)" }
        }
        persist()
    }

    func merge(_ incoming: [Song]) {
        for var song in incoming.prefix(20000) {
            if let name = song.localFile {
                if let url = try? DownloadFile.url(filename: name, directory: downloadDirectory), FileManager.default.fileExists(atPath: url.path) { }
                else { song.localFile = nil }
            }
            song.localFile = songsByID[song.id]?.localFile ?? song.localFile
            song.duration = measuredDurations[song.id] ?? song.duration
            songsByID[song.id] = song
        }
        songs = songsByID.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        persist()
    }

    func download(_ song: Song) async {
        guard !downloading.contains(song.id), saved(song).localFile == nil else { return }
        downloading.insert(song.id)
        defer { downloading.remove(song.id) }
        do {
            let stream = try await api.stream(for: song)
            let temporary = try await api.download(stream)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let name = UUID().uuidString + ".m4a"
            let destination = downloadDirectory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            var local = song
            local.localFile = name
            if let value = try? await AVURLAsset(url: destination).load(.duration).seconds,
               value.isFinite, value > 0 { local.duration = value; recordMeasuredDuration(local) }
            save(local)
        } catch { self.error = "Download failed: \(error.localizedDescription)" }
    }

    func importFiles(_ urls: [URL]) async {
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let name = UUID().uuidString + "." + url.pathExtension.lowercased()
                let target = downloadDirectory.appendingPathComponent(name)
                // Copy on a utility executor so large imports do not stall scrolling.
                try await Task.detached(priority: .utility) {
                    try FileManager.default.copyItem(at: url, to: target)
                }.value
                let asset = AVURLAsset(url: target)
                let duration = try? await asset.load(.duration).seconds
                save(Song(id: "local:" + UUID().uuidString,
                          title: url.deletingPathExtension().lastPathComponent, artist: "Local audio",
                          duration: duration?.isFinite == true ? duration : nil, localFile: name))
            } catch { self.error = "Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }

    func remove(_ song: Song) {
        if downloading.contains(song.id) { return }
        if let file = saved(song).localFile, let url = try? DownloadFile.url(filename: file, directory: downloadDirectory) {
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            } catch { self.error = "Could not remove the audio file: \(error.localizedDescription)"; return }
        }
        songs.removeAll { $0.id == song.id }
        songsByID[song.id] = nil
        persist()
    }

    private func persist() {
        do { try JSONEncoder().encode(songs).write(to: index, options: .atomic) }
        catch { self.error = "Could not save the library: \(error.localizedDescription)" }
    }
}
