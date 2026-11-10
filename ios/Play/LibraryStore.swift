// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AVFoundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var downloading = Set<String>()
    @Published var error: String?
    @Published private(set) var measuredDurations: [String: Double] = [:]
    let api: MusicAPI
    let player: PlaybackController
    let collections: UserCollections
    lazy var together = TogetherSession(player: player)
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let downloads = documents.appendingPathComponent("Downloads", isDirectory: true)
    private let index: URL
    private let downloadDirectory: URL
    private var songsByID: [String: Song] = [:]

    init(directory: URL? = nil) {
        let root = directory ?? Self.documents
        index = root.appendingPathComponent("library.json")
        downloadDirectory = root.appendingPathComponent("Downloads", isDirectory: true)
        collections = UserCollections(directory: root)
        let api = MusicAPI()
        self.api = api
        self.player = PlaybackController(api: api)
        player.onTrackStarted = { [weak collections] song in collections?.started(song) }
        player.onListeningTime = { [weak collections] seconds in collections?.listened(seconds) }
        player.onPaused = { [weak collections] in collections?.flush() }
        player.onDurationKnown = { [weak self] song in
            guard let self = self else { return }
            if let duration = song.duration {
                self.measuredDurations[song.id] = duration
                if self.measuredDurations.count > 2000, let old = self.measuredDurations.keys.first(where: { $0 != song.id }) { self.measuredDurations[old] = nil }
            }
            if self.contains(song) { self.save(song) }
        }
        do {
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: index))
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
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            var updated = song
            updated.localFile = song.localFile ?? songs[i].localFile
            songs[i] = updated
        } else { songs.append(song) }
        if let updated = songs.first(where: { $0.id == song.id }) { songsByID[song.id] = updated }
        persist()
    }

    func play(_ song: Song, in queue: [Song]) {
        player.play(saved(song), queue: queue.map(saved))
    }

    func merge(_ incoming: [Song]) {
        for var song in incoming.prefix(20000) {
            if let name = song.localFile {
                if let url = try? DownloadFile.url(filename: name, directory: downloadDirectory), FileManager.default.fileExists(atPath: url.path) { }
                else { song.localFile = nil }
            }
            song.localFile = songsByID[song.id]?.localFile ?? song.localFile
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
