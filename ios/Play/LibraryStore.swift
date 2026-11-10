// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import AVFoundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var songs: [Song] = []
    @Published private(set) var downloading = Set<String>()
    @Published var error: String?
    let api: MusicAPI
    let player: PlaybackController
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let downloads = documents.appendingPathComponent("Downloads", isDirectory: true)
    private let index = documents.appendingPathComponent("library.json")

    init() {
        let api = MusicAPI()
        self.api = api
        self.player = PlaybackController(api: api)
        do {
            try FileManager.default.createDirectory(at: Self.downloads, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) {
                songs = try JSONDecoder().decode([Song].self, from: Data(contentsOf: index))
            }
        } catch { self.error = "Could not load the saved library: \(error.localizedDescription)" }
    }

    func contains(_ song: Song) -> Bool { songs.contains { $0.id == song.id } }
    func saved(_ song: Song) -> Song { songs.first { $0.id == song.id } ?? song }
    func save(_ song: Song) {
        if let i = songs.firstIndex(where: { $0.id == song.id }) {
            var updated = song
            updated.localFile = songs[i].localFile ?? song.localFile
            songs[i] = updated
        } else { songs.append(song) }
        persist()
    }

    func play(_ song: Song, in queue: [Song]) {
        player.play(saved(song), queue: queue.map(saved))
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
            let destination = Self.downloads.appendingPathComponent(name)
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
                let target = Self.downloads.appendingPathComponent(name)
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
        if let file = saved(song).localFile {
            do { try FileManager.default.removeItem(at: Self.downloads.appendingPathComponent(file)) }
            catch { self.error = "Could not remove the audio file: \(error.localizedDescription)"; return }
        }
        songs.removeAll { $0.id == song.id }
        persist()
    }

    private func persist() {
        do { try JSONEncoder().encode(songs).write(to: index, options: .atomic) }
        catch { self.error = "Could not save the library: \(error.localizedDescription)" }
    }
}
