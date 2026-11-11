// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import YouTubeKit

actor MusicAPI {
    let lyricCatalog = LyricCatalog()
    private let network = NWPathMonitor()

    init() { network.start(queue: DispatchQueue.global(qos: .utility)) }
    deinit { network.cancel() }

    func lyrics(for song: Song) async throws -> [LyricLine] {
        try await lyricCatalog.lines(for: song)
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    func search(_ query: String) async throws -> [Song] {
        filtered(Self.parseSearch(try await musicRequest("search", parameters: ["query": query, "params": "EgWKAQIIAWoKEAkQBRAKEAMQBA%3D%3D"])))
    }

    func home(category: String? = nil) async throws -> [Song] {
        if let category = category { return try await search(category + " music") }
        let songs = Self.parseSearch(try await musicRequest("browse", parameters: ["browseId": "FEmusic_home"]))
        if songs.isEmpty { return try await search("popular music") }
        return filtered(songs)
    }

    func related(to song: Song) async throws -> [Song] {
        let songs = Self.parseSearch(try await musicRequest("next", parameters: ["videoId": song.id, "isAudioOnly": true]))
        if !songs.isEmpty { return filtered(songs).filter { $0.id != song.id } }
        return try await search(song.artist).filter { $0.id != song.id }
    }

    private func filtered(_ songs: [Song]) -> [Song] {
        let defaults = UserDefaults.standard
        let hideExplicit = defaults.bool(forKey: "content.hideExplicit")
        let hideVideos = defaults.bool(forKey: "content.hideVideos")
        return songs.filter { !(hideExplicit && $0.explicit == true) && !(hideVideos && $0.musicVideo == true) }
    }

    private func musicRequest(_ endpoint: String, parameters: [String: Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/youtubei/v1/\(endpoint)?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("67", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("1.20260114.01.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        var body = parameters
        body["context"] = ["client": ["clientName": "WEB_REMIX", "clientVersion": "1.20260114.01.00",
                                     "hl": UserDefaults.standard.string(forKey: "content.language") ?? "en",
                                     "gl": UserDefaults.standard.string(forKey: "content.region") ?? "US"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try check(response)
        return try JSONSerialization.jsonObject(with: data)
    }

    // Parse only song rows, avoiding duplicate thumbnail/navigation video IDs.
    static func parseSearch(_ json: Any) -> [Song] {
        var songs: [Song] = []
        var seen = Set<String>()
        func text(_ value: Any?) -> String {
            guard let value = value as? [String: Any] else { return "" }
            return value["simpleText"] as? String ?? (value["runs"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined()
        }
        func explicit(_ row: [String: Any]) -> Bool {
            let badges = (row["badges"] as? [[String: Any]] ?? []) + (row["subtitleBadges"] as? [[String: Any]] ?? [])
            return badges.contains {
                let renderer = $0["musicInlineBadgeRenderer"] as? [String: Any]
                let icon = renderer?["icon"] as? [String: Any]
                return icon?["iconType"] as? String == "MUSIC_EXPLICIT_BADGE"
            }
        }
        func video(_ watch: [String: Any]?) -> Bool {
            let config = watch?["watchEndpointMusicSupportedConfigs"] as? [String: Any]
            let music = config?["watchEndpointMusicConfig"] as? [String: Any]
            let type = music?["musicVideoType"] as? String
            return type == "MUSIC_VIDEO_TYPE_OMV" || type == "MUSIC_VIDEO_TYPE_UGC"
        }
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let row = dictionary["playlistPanelVideoRenderer"] as? [String: Any], let id = row["videoId"] as? String {
                    let name = text(row["title"])
                    let image = row["thumbnail"] as? [String: Any]
                    let images = image?["thumbnails"] as? [[String: Any]] ?? []
                    if !name.isEmpty, seen.insert(id).inserted {
                        songs.append(Song(id: id, title: name, artist: text(row["shortBylineText"]),
                                          artwork: (images.last?["url"] as? String).flatMap(URL.init(string:)),
                                          duration: Self.duration(text(row["lengthText"])), explicit: explicit(row),
                                          musicVideo: video((row["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])))
                    }
                    return
                }
                if let row = dictionary["musicTwoRowItemRenderer"] as? [String: Any],
                   let endpoint = row["navigationEndpoint"] as? [String: Any],
                   let watch = endpoint["watchEndpoint"] as? [String: Any], let id = watch["videoId"] as? String {
                    let title = row["title"] as? [String: Any]
                    let subtitle = row["subtitle"] as? [String: Any]
                    let titleRuns = title?["runs"] as? [[String: Any]] ?? []
                    let artistRuns = subtitle?["runs"] as? [[String: Any]] ?? []
                    let thumbnail = row["thumbnailRenderer"] as? [String: Any]
                    let renderer = thumbnail?["musicThumbnailRenderer"] as? [String: Any]
                    let image = renderer?["thumbnail"] as? [String: Any]
                    let images = image?["thumbnails"] as? [[String: Any]] ?? []
                    let name = titleRuns.compactMap { $0["text"] as? String }.joined()
                    if !name.isEmpty, seen.insert(id).inserted {
                        songs.append(Song(id: id, title: name, artist: artistRuns.first?["text"] as? String ?? "Unknown artist",
                                          artwork: (images.last?["url"] as? String).flatMap(URL.init(string:)),
                                          duration: artistRuns.compactMap { ($0["text"] as? String).flatMap(Self.duration) }.last,
                                          explicit: explicit(row), musicVideo: video(watch)))
                    }
                    return
                }
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
                    let duration = columns.indices.dropFirst().flatMap { runs($0) }.compactMap { ($0["text"] as? String).flatMap(Self.duration) }.last
                    let fixed = row["fixedColumns"] as? [[String: Any]] ?? []
                    let fixedDuration = fixed.compactMap { column -> Double? in
                        let renderer = column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any]
                        return Self.duration(text(renderer?["text"]))
                    }.first
                    let albumRun = runs(1).first { run in
                        let nav = run["navigationEndpoint"] as? [String: Any]
                        let browse = nav?["browseEndpoint"] as? [String: Any]
                        return (browse?["browseId"] as? String)?.hasPrefix("MPRE") == true
                    }
                    func browseID(_ run: [String: Any]?) -> String? {
                        let nav = run?["navigationEndpoint"] as? [String: Any]
                        return (nav?["browseEndpoint"] as? [String: Any])?["browseId"] as? String
                    }
                    if let id = id, !title.isEmpty, seen.insert(id).inserted {
                        songs.append(Song(id: id, title: title, artist: artist,
                                          artwork: (thumbnails?.last?["url"] as? String).flatMap(URL.init(string:)), duration: fixedDuration ?? duration,
                                          album: albumRun?["text"] as? String, albumID: browseID(albumRun), artistID: browseID(runs(1).first),
                                          explicit: explicit(row), musicVideo: video(watch ?? (runs(0).first?["navigationEndpoint"] as? [String: Any])?["watchEndpoint"] as? [String: Any])))
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
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return numbers.reduce(0.0) { $0 * 60 + Double($1) }
    }

    func stream(for song: Song) async throws -> URL {
        let streams = try await YouTube(videoID: song.id, methods: [.local]).streams
        let compatible = streams.filterAudioOnly().filter { $0.fileExtension == .m4a }
        let defaults = UserDefaults.standard
        let quality = defaults.string(forKey: "player.quality") ?? "Automatic"
        let metered = defaults.bool(forKey: "player.metered") || network.currentPath.isExpensive || network.currentPath.isConstrained
        let low = quality == "Low" || (quality == "Automatic" && metered)
        let chosen = low ? compatible.min { ($0.averageBitrate ?? $0.bitrate ?? Int.max) < ($1.averageBitrate ?? $1.bitrate ?? Int.max) } : compatible.highestAudioBitrateStream()
        guard let stream = chosen else {
            throw PlayError.message("No compatible audio stream is available for this song.")
        }
        try await stream.waitUntilAvailable()
        return stream.url
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
