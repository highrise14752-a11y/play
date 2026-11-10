// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import YouTubeKit

actor MusicAPI {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func search(_ query: String) async throws -> [Song] {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260114.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "context": ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20260114.01.00", "hl": "en", "gl": "US"]],
            "query": query,
            "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"
        ])
        let (data, response) = try await session.data(for: request)
        try check(response)
        return Self.parseSearch(try JSONSerialization.jsonObject(with: data))
    }

    // Parse only song rows, avoiding duplicate thumbnail/navigation video IDs.
    static func parseSearch(_ json: Any) -> [Song] {
        var songs: [Song] = []
        var seen = Set<String>()
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let row = dictionary["musicResponsiveListItemRenderer"] as? [String: Any] {
                    let endpoint = row["navigationEndpoint"] as? [String: Any]
                    let watch = endpoint?["watchEndpoint"] as? [String: Any]
                    let playlist = row["playlistItemData"] as? [String: Any]
                    let id = (playlist?["videoId"] ?? watch?["videoId"]) as? String
                    let columns = row["flexColumns"] as? [[String: Any]] ?? []
                    func runs(_ index: Int) -> [[String: Any]] {
                        guard columns.indices.contains(index),
                              let cell = columns[index]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any],
                              let text = cell["text"] as? [String: Any] else { return [] }
                        return text["runs"] as? [[String: Any]] ?? []
                    }
                    let title = runs(0).compactMap { $0["text"] as? String }.joined()
                    let artist = runs(1).compactMap { run -> String? in
                        guard let nav = run["navigationEndpoint"] as? [String: Any], nav["browseEndpoint"] != nil else { return nil }
                        return run["text"] as? String
                    }.first ?? (runs(1).first?["text"] as? String) ?? "Unknown artist"
                    let thumb = row["thumbnail"] as? [String: Any]
                    let renderer = thumb?["musicThumbnailRenderer"] as? [String: Any]
                    let image = renderer?["thumbnail"] as? [String: Any]
                    let thumbnails = image?["thumbnails"] as? [[String: Any]]
                    let duration = runs(1).compactMap { ($0["text"] as? String).flatMap(Self.duration) }.last
                    if let id = id, !title.isEmpty, seen.insert(id).inserted {
                        songs.append(Song(id: id, title: title, artist: artist,
                                          artwork: (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:)), duration: duration))
                    }
                    return
                }
                for key in dictionary.keys.sorted() { if let child = dictionary[key] { visit(child) } }
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(json)
        return songs
    }

    static func duration(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return numbers.reduce(0.0) { $0 * 60 + Double($1) }
    }

    func stream(for song: Song) async throws -> URL {
        let streams = try await YouTube(videoID: song.id, methods: [.local]).streams
        guard let stream = streams.filterAudioOnly().filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() else {
            throw PlayError.message("No compatible audio stream is available for this song.")
        }
        try await stream.waitUntilAvailable()
        return stream.url
    }

    func lyrics(for song: Song) async throws -> [LyricLine] {
        var url = URLComponents(string: "https://lrclib.net/api/search")!
        url.queryItems = [URLQueryItem(name: "track_name", value: song.title), URLQueryItem(name: "artist_name", value: song.artist)]
        var request = URLRequest(url: url.url!)
        request.setValue("Play/1.0 (https://github.com/highrise14752-a11y/play)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try check(response)
        struct Record: Decodable { let duration: Double?; let syncedLyrics: String?; let plainLyrics: String? }
        let records = try JSONDecoder().decode([Record].self, from: data).sorted {
            if ($0.syncedLyrics != nil) != ($1.syncedLyrics != nil) { return $0.syncedLyrics != nil }
            guard let duration = song.duration else { return false }
            return abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration)
        }
        guard let record = records.first else { return [] }
        return LyricsParser.parse(record.syncedLyrics ?? record.plainLyrics ?? "")
    }

    func download(_ url: URL) async throws -> URL {
        let (temporary, response) = try await session.download(from: url)
        try check(response)
        // URLSession owns the returned temporary path; move before returning it.
        let retained = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: temporary, to: retained)
        return retained
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PlayError.message(status == 429 ? "Too many requests. Please wait before trying again." : "The music service returned an error (\(status)). Try again later.")
        }
    }
}
