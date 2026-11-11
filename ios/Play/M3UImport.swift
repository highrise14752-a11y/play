// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum M3UImport {
    struct Entry: Equatable {
        var id: String?
        var title: String?
        var artist: String?
        var duration: Double?
    }

    static func parse(_ data: Data) throws -> [Entry] {
        guard data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw PlayError.message("Choose a UTF-8 M3U playlist under 2 MB.")
        }
        var entries: [Entry] = []
        var pending: Entry?
        for line in text.components(separatedBy: .newlines) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if value.isEmpty { continue }
            if value.hasPrefix("#EXTINF:") {
                if let previous = pending { entries.append(previous) }
                pending = metadata(String(value.dropFirst(8)))
            } else if !value.hasPrefix("#") {
                var entry = pending ?? Entry()
                if case .song(let id) = CatalogLink.parse(value) { entry.id = id }
                if entry.id != nil || entry.title != nil { entries.append(entry) }
                pending = nil
            }
            guard entries.count <= 5000 else { throw PlayError.message("The playlist has more than 5,000 entries.") }
        }
        if let pending = pending { entries.append(pending) }
        guard !entries.isEmpty else { throw PlayError.message("No songs were found in this M3U file.") }
        return entries
    }

    private static func metadata(_ raw: String) -> Entry {
        guard let comma = raw.firstIndex(of: ",") else { return Entry() }
        let length = raw[..<comma].split(whereSeparator: \.isWhitespace).first.flatMap { Double($0) }
        let label = raw[raw.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = label.range(of: " - ")
        let title = separator.map { String(label[$0.upperBound...]) } ?? label
        let artist = separator.map { String(label[..<$0.lowerBound]).replacingOccurrences(of: ";", with: ", ") }
        return Entry(title: title.isEmpty ? nil : String(title.prefix(512)),
                     artist: artist.map { String($0.prefix(256)) },
                     duration: length.flatMap { $0.isFinite && $0 > 0 ? $0 : nil })
    }

    static func resolve(_ entries: [Entry], saved: [Song], api: MusicAPI) async throws -> [Song] {
        var byID: [String: Song] = [:]
        var byTitle: [String: [Song]] = [:]
        for song in saved {
            byID[song.id] = song
            byTitle[song.title.lowercased(), default: []].append(song)
        }
        var seen = Set<String>()
        var songs: [Song] = []
        var lookups = 0
        let deadline = Date().addingTimeInterval(90)
        for entry in entries {
            try Task.checkCancellation()
            let match: Song?
            if let id = entry.id {
                if let existing = byID[id] { match = existing }
                else if let title = entry.title {
                    match = Song(id: id, title: title, artist: entry.artist ?? "Unknown artist", duration: entry.duration)
                } else if lookups < 150, Date() < deadline {
                    lookups += 1
                    match = try? await api.song(id: id)
                } else { match = nil }
            } else if let title = entry.title {
                if let existing = byTitle[title.lowercased()]?.first(where: { sameArtist($0, entry) }) { match = existing }
                else if lookups < 150, Date() < deadline {
                    lookups += 1
                    let found = (try? await api.search([title, entry.artist].compactMap { $0 }.joined(separator: " "))) ?? []
                    match = found.first { $0.title.caseInsensitiveCompare(title) == .orderedSame && sameArtist($0, entry) }
                } else { match = nil }
            } else { match = nil }
            if let match = match, seen.insert(match.id).inserted { songs.append(match) }
        }
        return songs
    }

    private static func sameArtist(_ song: Song, _ entry: Entry) -> Bool {
        guard let artist = entry.artist, !artist.isEmpty else { return true }
        return song.artist.caseInsensitiveCompare(artist) == .orderedSame
    }
}
