// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI

struct LocalPlaylist: Identifiable, Codable, Equatable {
    var id = UUID().uuidString
    var name: String
    var songIDs: [String] = []
    var tags: [String]?
}
struct ListeningEntry: Identifiable, Codable {
    var id = UUID().uuidString
    var song: Song
    var startedAt = Date()
    var seconds: Double = 0
}
struct ListeningTotal: Codable {
    var song: Song
    var plays = 0
    var seconds: Double = 0
}
struct CollectionSnapshot: Codable {
    var likedIDs: Set<String> = []
    var playlists: [LocalPlaylist] = []
    var history: [ListeningEntry] = []
    var totals: [String: ListeningTotal] = [:]
}

@MainActor
final class UserCollections: ObservableObject {
    @Published private(set) var state = CollectionSnapshot()
    @Published var error: String?
    private let file: URL
    private var pendingSeconds = 0.0
    private var lastPersisted = Date.distantPast
    private var currentEntry: String?
    private var pendingEntry: ListeningEntry?
    private var minimumListen = 0.0
    var historyPaused: Bool { UserDefaults.standard.bool(forKey: "privacy.pauseHistory") }

    init(directory: URL) {
        file = directory.appendingPathComponent("collections.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { state = try JSONDecoder().decode(CollectionSnapshot.self, from: Data(contentsOf: file)) }
            catch { self.error = "Could not read listening history and playlists: \(error.localizedDescription)" }
        }
    }
    func liked(_ song: Song) -> Bool { state.likedIDs.contains(song.id) }
    func toggleLike(_ song: Song) {
        if state.likedIDs.contains(song.id) { state.likedIDs.remove(song.id) } else { state.likedIDs.insert(song.id) }
        persist()
    }
    func createPlaylist(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.playlists.append(LocalPlaylist(name: String(name.prefix(120))))
        persist()
    }
    func importPlaylist(_ playlist: PublicPlaylist) {
        let name = String(playlist.title.prefix(120))
        var seen = Set<String>()
        let ids = playlist.songs.map(\.id).filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }
        state.playlists.append(LocalPlaylist(name: name, songIDs: ids))
        persist()
    }
    func renamePlaylist(_ id: String, name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = state.playlists.firstIndex(where: { $0.id == id }) else { return }
        state.playlists[index].name = String(value.prefix(120)); persist()
    }
    func deletePlaylist(_ id: String) { state.playlists.removeAll { $0.id == id }; persist() }
    func setTags(_ text: String, for id: String) {
        guard let index = state.playlists.firstIndex(where: { $0.id == id }) else { return }
        var seen = Set<String>()
        let tags = text.split(whereSeparator: { $0 == "," || $0.isNewline }).compactMap { part -> String? in
            let tag = String(part.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
            return !tag.isEmpty && seen.insert(tag.lowercased()).inserted ? tag : nil
        }
        state.playlists[index].tags = Array(tags.prefix(12))
        persist()
    }
    func add(_ song: Song, to playlistID: String) {
        guard let index = state.playlists.firstIndex(where: { $0.id == playlistID }), !state.playlists[index].songIDs.contains(song.id) else { return }
        state.playlists[index].songIDs.append(song.id); persist()
    }
    func remove(_ song: Song, from playlistID: String) {
        guard let index = state.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        state.playlists[index].songIDs.removeAll { $0 == song.id }; persist()
    }
    func moveSongs(in playlistID: String, from: IndexSet, to: Int) {
        guard let index = state.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        state.playlists[index].songIDs.move(fromOffsets: from, toOffset: to); persist()
    }
    func started(_ song: Song) {
        flush()
        currentEntry = nil
        pendingEntry = nil
        guard !historyPaused else { return }
        let entry = ListeningEntry(song: song)
        let setting = UserDefaults.standard.object(forKey: "player.historyMinimum") as? Double ?? 30
        minimumListen = min(120, max(0, setting.isFinite ? setting : 30))
        if minimumListen > 0 { pendingEntry = entry }
        else { record(entry) }
    }
    private func record(_ entry: ListeningEntry) {
        currentEntry = entry.id
        state.history.insert(entry, at: 0)
        if state.history.count > 5000 { state.history.removeLast(state.history.count - 5000) }
        var total = state.totals[entry.song.id] ?? ListeningTotal(song: entry.song)
        total.song = entry.song
        total.plays += 1
        total.seconds += entry.seconds
        state.totals[entry.song.id] = total
        persist()
    }
    func listened(_ seconds: Double) {
        guard !historyPaused, seconds.isFinite, seconds > 0, seconds < 2 else { return }
        if var entry = pendingEntry {
            entry.seconds += seconds
            if entry.seconds >= minimumListen {
                pendingEntry = nil
                record(entry)
            } else { pendingEntry = entry }
            return
        }
        guard currentEntry != nil else { return }
        pendingSeconds += seconds
        if pendingSeconds >= 10 { flush(persistNow: Date().timeIntervalSince(lastPersisted) >= 30) }
    }
    func flush(persistNow: Bool = true) {
        if let id = currentEntry, let index = state.history.firstIndex(where: { $0.id == id }), pendingSeconds > 0 {
            let song = state.history[index].song
            state.history[index].seconds += pendingSeconds
            if var total = state.totals[song.id] { total.seconds += pendingSeconds; state.totals[song.id] = total }
            pendingSeconds = 0
        }
        if persistNow { persist() }
    }
    func clearHistory() {
        currentEntry = nil; pendingEntry = nil; pendingSeconds = 0
        state.history = []; state.totals = [:]; persist()
    }
    func removeHistory(_ entry: ListeningEntry) { state.history.removeAll { $0.id == entry.id }; persist() }
    func restore(_ snapshot: CollectionSnapshot) {
        flush()
        state.likedIDs.formUnion(snapshot.likedIDs)
        var playlistIDs = Set(state.playlists.map(\.id))
        state.playlists.append(contentsOf: snapshot.playlists.prefix(5000).filter { playlistIDs.insert($0.id).inserted })
        var historyIDs = Set(state.history.map(\.id))
        state.history = Array((state.history + snapshot.history.filter { historyIDs.insert($0.id).inserted }).sorted { $0.startedAt > $1.startedAt }.prefix(5000))
        for (id, total) in snapshot.totals where state.totals[id] == nil { state.totals[id] = total }
        persist()
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: file, options: .atomic)
            lastPersisted = Date()
        } catch { self.error = "Could not save playlists and history: \(error.localizedDescription)" }
    }
}
