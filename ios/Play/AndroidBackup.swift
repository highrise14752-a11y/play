// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SQLite3
import ZIPFoundation

enum AndroidBackup {
    private static let database = "song.db"
    private static let limit = 96 * 1024 * 1024

    static func read(_ url: URL, timeZone: TimeZone = .current) throws -> PlayBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= limit else { throw PlayError.message("The Android backup is empty or larger than 96 MB.") }
        let archive = try Archive(url: url, accessMode: .read)
        guard archive[database] != nil else { throw PlayError.message("This ZIP file is missing the Android Play library.") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        var remaining = limit
        for name in [database, database + "-wal"] {
            guard let entry = archive[name] else { continue }
            guard entry.type == .file, entry.uncompressedSize <= UInt64(remaining) else {
                throw PlayError.message("The Android library is too large or contains an invalid entry.")
            }
            if name != database, entry.uncompressedSize == 0 { continue }
            let target = directory.appendingPathComponent(name)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            let file = try FileHandle(forWritingTo: target)
            defer { try? file.close() }
            let checksum = try archive.extract(entry) { data in
                guard data.count <= remaining else { throw PlayError.message("The Android library is too large.") }
                remaining -= data.count
                try file.write(contentsOf: data)
            }
            guard checksum == entry.checksum else { throw PlayError.message("The Android library failed its checksum.") }
        }
        let db = try BackupDatabase(directory.appendingPathComponent(database))
        return try library(db, timeZone: timeZone)
    }

    private static func library(_ db: BackupDatabase, timeZone: TimeZone) throws -> PlayBackup {
        let columns = try db.columns("song")
        guard columns.isSuperset(of: ["id", "title"]) else {
            throw PlayError.message("This Android database version could not be read.")
        }
        let optional = ["duration", "thumbnailUrl", "albumId", "albumName", "explicit", "liked", "totalPlayTime", "isLocal"]
        let fields = optional.map { columns.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        let artists = try artistNames(db)
        var songs: [Song] = []
        var byID: [String: Song] = [:]
        var snapshot = CollectionSnapshot()
        try db.rows("SELECT id,title,\(fields) FROM song ORDER BY id LIMIT 20000") { row in
            guard let id = db.string(row, 0), let title = db.string(row, 1), !title.isEmpty,
                  sqlite3_column_int(row, 9) == 0,
                  CatalogLink.parse("play://song?v=" + id) == .song(id) else { return }
            let thumbnail = db.string(row, 3).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            let length = sqlite3_column_int64(row, 2)
            let song = Song(id: id, title: String(title.prefix(512)), artist: artists[id] ?? "Unknown artist",
                            artwork: thumbnail, duration: length > 0 ? Double(length) : nil,
                            album: db.string(row, 5), albumID: db.string(row, 4), explicit: sqlite3_column_int(row, 6) != 0)
            songs.append(song)
            byID[id] = song
            if sqlite3_column_int(row, 7) != 0 { snapshot.likedIDs.insert(id) }
            let seconds = Double(sqlite3_column_int64(row, 8)) / 1000
            if seconds > 0 { snapshot.totals[id] = ListeningTotal(song: song, seconds: seconds) }
        }
        snapshot.playlists = try playlists(db, songs: byID)
        if try db.columns("event").isSuperset(of: ["id", "songId", "timestamp", "playTime"]) {
            try db.rows("SELECT id,songId,timestamp,playTime FROM event ORDER BY timestamp DESC,id DESC LIMIT 5000") { row in
                guard let id = db.string(row, 1), let song = byID[id] else { return }
                let stamp = sqlite3_column_int64(row, 2)
                let milliseconds = sqlite3_column_int64(row, 3)
                guard stamp > 0, milliseconds >= 0 else { return }
                // Android stores local wall time as if it were UTC.
                let wall = Date(timeIntervalSince1970: Double(stamp) / 1000)
                let date = wall.addingTimeInterval(-Double(timeZone.secondsFromGMT(for: wall)))
                let seconds = Double(milliseconds) / 1000
                let eventID = "android:\(id):\(stamp):\(milliseconds):\(sqlite3_column_int64(row, 0))"
                snapshot.history.append(ListeningEntry(id: eventID, song: song, startedAt: date, seconds: seconds))
                var total = snapshot.totals[id] ?? ListeningTotal(song: song)
                total.plays += 1
                snapshot.totals[id] = total
            }
            var eventSeconds: [String: Double] = [:]
            for entry in snapshot.history { eventSeconds[entry.song.id, default: 0] += entry.seconds }
            for (id, seconds) in eventSeconds {
                if let prior = snapshot.totals[id] { snapshot.totals[id]?.seconds = max(prior.seconds, seconds) }
            }
        }
        return PlayBackup(songs: songs, collections: snapshot)
    }

    private static func artistNames(_ db: BackupDatabase) throws -> [String: String] {
        guard try db.columns("artist").isSuperset(of: ["id", "name"]),
              try db.columns("song_artist_map").isSuperset(of: ["songId", "artistId", "position"]) else { return [:] }
        var artists: [String: [String]] = [:]
        try db.rows("""
            SELECT m.songId,a.name FROM song_artist_map m JOIN artist a ON a.id=m.artistId
            ORDER BY m.songId,m.position LIMIT 100000
            """) { row in
            guard let id = db.string(row, 0), let name = db.string(row, 1),
                  !name.isEmpty, artists[id, default: []].count < 8 else { return }
            artists[id, default: []].append(String(name.prefix(256)))
        }
        return artists.mapValues { $0.joined(separator: ", ") }
    }

    private static func playlists(_ db: BackupDatabase, songs: [String: Song]) throws -> [LocalPlaylist] {
        guard try db.columns("playlist").isSuperset(of: ["id", "name"]) else { return [] }
        var members: [String: [String]] = [:]
        if try db.columns("playlist_song_map").isSuperset(of: ["playlistId", "songId", "position"]) {
            try db.rows("SELECT playlistId,songId FROM playlist_song_map ORDER BY playlistId,position LIMIT 100000") { row in
                guard let playlist = db.string(row, 0), let song = db.string(row, 1), songs[song] != nil else { return }
                members[playlist, default: []].append(song)
            }
        }
        var tags: [String: [String]] = [:]
        if try db.columns("tag").isSuperset(of: ["id", "name"]),
           try db.columns("playlist_tag_map").isSuperset(of: ["tagId", "playlistId"]) {
            try db.rows("SELECT m.playlistId,t.name FROM playlist_tag_map m JOIN tag t ON t.id=m.tagId ORDER BY t.name LIMIT 50000") { row in
                guard let playlist = db.string(row, 0), let tag = db.string(row, 1), tags[playlist, default: []].count < 12 else { return }
                tags[playlist, default: []].append(String(tag.prefix(32)))
            }
        }
        var playlists: [LocalPlaylist] = []
        try db.rows("SELECT id,name FROM playlist ORDER BY id LIMIT 5000") { row in
            guard let id = db.string(row, 0), let name = db.string(row, 1), !id.isEmpty, !name.isEmpty else { return }
            var seen = Set<String>()
            let ordered = (members[id] ?? []).filter { seen.insert($0).inserted }
            playlists.append(LocalPlaylist(id: "android:" + id, name: String(name.prefix(120)), songIDs: ordered, tags: tags[id]))
        }
        return playlists
    }
}

private final class BackupDatabase {
    private let connection: OpaquePointer

    init(_ url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_PRIVATECACHE, nil) == SQLITE_OK,
              let opened = handle else {
            if let handle = handle { sqlite3_close(handle) }
            throw PlayError.message("Could not open the Android Play library.")
        }
        connection = opened
        sqlite3_limit(opened, SQLITE_LIMIT_LENGTH, 1_000_000)
        try rows("PRAGMA trusted_schema=OFF") { _ in }
    }

    deinit { sqlite3_close(connection) }

    func columns(_ table: String) throws -> Set<String> {
        // Table names come only from the importer, never from the ZIP or SQLite data.
        var found = false
        try rows("SELECT 1 FROM sqlite_master WHERE type='table' AND name='\(table)' AND sql LIKE 'CREATE TABLE%'") { _ in found = true }
        guard found else { return [] }
        var result = Set<String>()
        try rows("PRAGMA table_info(\(table))") { row in
            if let name = string(row, 1) { result.insert(name) }
        }
        return result
    }

    func string(_ row: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(row, index) != SQLITE_NULL, sqlite3_column_bytes(row, index) <= 4096,
              let value = sqlite3_column_text(row, index) else { return nil }
        return String(validatingUTF8: UnsafeRawPointer(value).assumingMemoryBound(to: CChar.self))
    }

    func rows(_ query: String, _ read: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK, let row = statement else {
            throw PlayError.message("Could not read the Android Play library.")
        }
        defer { sqlite3_finalize(row) }
        var status = sqlite3_step(row)
        while status == SQLITE_ROW {
            read(row)
            status = sqlite3_step(row)
        }
        guard status == SQLITE_DONE else { throw PlayError.message("The Android library is incomplete or damaged.") }
    }
}
