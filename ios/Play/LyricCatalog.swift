// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum LyricSource: String, CaseIterable, Identifiable {
    case lrcLib = "LRCLIB"
    case better = "BetterLyrics"
    case simp = "SimpMusic"
    case kuGou = "KuGou"

    var id: String { rawValue }
    var setting: String { "lyrics.source." + rawValue }

    static func ordered(enabled: [Self], preferred: Self) -> [Self] {
        guard enabled.contains(preferred) else { return enabled }
        return [preferred] + enabled.filter { $0 != preferred }
    }
}

actor LyricCatalog {
    private struct CacheKey: Hashable {
        let id: String
        let duration: Double?
        let sources: [LyricSource]
    }
    private var cache: [CacheKey: [LyricLine]] = [:]

    func lines(for song: Song) async throws -> [LyricLine] {
        let defaults = UserDefaults.standard
        let enabled = LyricSource.allCases.filter { defaults.object(forKey: $0.setting) as? Bool ?? true }
        let preferred = LyricSource(rawValue: defaults.string(forKey: "lyrics.preferredSource") ?? "") ?? .lrcLib
        let sources = LyricSource.ordered(enabled: enabled, preferred: preferred)
        let key = CacheKey(id: song.id, duration: song.duration, sources: sources)
        if let found = cache[key] { return found }
        var plain: [LyricLine] = []
        for source in sources {
            try Task.checkCancellation()
            guard let lines = try? await fetch(song, source: source), !lines.isEmpty else { continue }
            try Task.checkCancellation()
            if lines.contains(where: { $0.time != nil }) { return remember(lines, key: key) }
            if plain.isEmpty { plain = lines }
        }
        return plain.isEmpty ? [] : remember(plain, key: key)
    }

    private func remember(_ lines: [LyricLine], key: CacheKey) -> [LyricLine] {
        if cache.count >= 48, let oldest = cache.keys.first { cache.removeValue(forKey: oldest) }
        cache[key] = lines
        return lines
    }

    private func fetch(_ song: Song, source: LyricSource) async throws -> [LyricLine] {
        let seconds = song.duration.flatMap { $0.isFinite && $0 > 0 && $0 < 864_000 ? Int($0.rounded()) : nil }
        switch source {
        case .lrcLib:
            let records: [Record] = try await get("https://lrclib.net/api/search", [
                "track_name": song.title, "artist_name": song.artist
            ])
            return Self.best(records, duration: seconds)
        case .better:
            struct Response: Decodable { let ttml: String }
            var query = ["s": song.title, "a": song.artist]
            query["al"] = song.album
            query["d"] = seconds.map { String($0) }
            let response: Response = try await get("https://lyrics-api.boidu.dev/getLyrics", query)
            return TTMLLyrics.parse(response.ttml)
        case .simp:
            struct Response: Decodable { let type: String?; let data: [Record]? }
            guard !song.isLocal, song.id.count == 11,
                  song.id.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return [] }
            let response: Response = try await get("https://api-lyrics.simpmusic.org/v1/" + song.id)
            return response.type == "success" ? Self.best(response.data ?? [], duration: seconds) : []
        case .kuGou:
            struct Candidate: Decodable { let id: Int64; let accesskey: String }
            struct Matches: Decodable { let candidates: [Candidate] }
            struct Download: Decodable { let content: String? }
            struct Songs: Decodable {
                struct Results: Decodable {
                    struct SongResult: Decodable { let hash: String; let duration: Int }
                    let info: [SongResult]
                }
                let data: Results?
            }
            let keyword = song.title + " - " + song.artist
            let endpoint = "https://lyrics.kugou.com/search"
            let base = ["ver": "1", "man": "yes", "client": "pc"]
            let tracks: Songs? = try? await get("https://mobileservice.kugou.com/api/v3/search/song", [
                "version": "9108", "plat": "0", "pagesize": "5", "showtype": "0", "keyword": keyword
            ])
            try Task.checkCancellation()
            var match: Candidate?
            if let candidate = tracks?.data?.info.first(where: { track in
                seconds.map { abs(Double(track.duration) - Double($0)) <= 5 } ?? true
            }) {
                var query = base
                query["hash"] = candidate.hash
                let matches: Matches? = try? await get(endpoint, query)
                match = matches?.candidates.first
            }
            if match == nil {
                var query = base
                query["keyword"] = keyword
                query["duration"] = seconds.map { String($0 * 1000) }
                let matches: Matches = try await get(endpoint, query)
                match = matches.candidates.first
            }
            guard let match = match else { return [] }
            let result: Download = try await get("https://lyrics.kugou.com/download", [
                "ver": "1", "client": "pc", "fmt": "lrc", "charset": "utf8",
                "id": String(match.id), "accesskey": match.accesskey
            ])
            guard let encoded = result.content, let data = Data(base64Encoded: encoded),
                  let text = String(data: data, encoding: .utf8) else { return [] }
            return LyricsParser.parse(text)
        }
    }

    private struct Record: Decodable {
        let duration: Double?
        let durationSeconds: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
        let plainLyric: String?
    }

    private static func best(_ records: [Record], duration: Int?) -> [LyricLine] {
        func distance(_ record: Record) -> Double {
            guard let duration = duration, let value = record.duration ?? record.durationSeconds else { return .infinity }
            return abs(value - Double(duration))
        }
        let candidates = records.filter { $0.syncedLyrics != nil || $0.plainLyrics != nil || $0.plainLyric != nil }
        let match = candidates.min { left, right in
            if (left.syncedLyrics != nil) != (right.syncedLyrics != nil) { return left.syncedLyrics != nil }
            return distance(left) < distance(right)
        }
        return LyricsParser.parse(match?.syncedLyrics ?? match?.plainLyrics ?? match?.plainLyric ?? "")
    }

    private func get<Response: Decodable>(_ endpoint: String, _ parameters: [String: String] = [:]) async throws -> Response {
        guard var components = URLComponents(string: endpoint) else { throw URLError(.badURL) }
        if !parameters.isEmpty { components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Play/1.1 (https://github.com/highrise14752-a11y/play)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

final class TTMLLyrics: NSObject, XMLParserDelegate {
    private var lines: [LyricLine] = []
    private var lineStart: Double?
    private var paragraph = false
    private var segments: [LyricWord] = []
    private var timings: [Double?] = []
    private var ignoredDepth = 0

    static func parse(_ source: String) -> [LyricLine] {
        let delegate = TTMLLyrics()
        let parser = XMLParser(data: Data(source.utf8))
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { return [] }
        return delegate.lines.sorted { ($0.time ?? 0) < ($1.time ?? 0) }.enumerated().map { index, line in
            LyricLine(id: index, time: line.time, text: line.text, words: line.words)
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if ignoredDepth > 0 { ignoredDepth += 1; return }
        if name == "p" {
            paragraph = true
            lineStart = Self.time(attributes["begin"])
            segments = []
        } else if paragraph, name == "span" {
            let role = attributes.first { $0.key.split(separator: ":").last == "role" }?.value
            if role == "x-translation" || role == "x-roman" { ignoredDepth = 1; return }
            timings.append(Self.time(attributes["begin"]) ?? timings.last.flatMap { $0 })
        } else if paragraph, name == "br" {
            self.parser(parser, foundCharacters: "\n")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters text: String) {
        guard paragraph, ignoredDepth == 0, !text.isEmpty else { return }
        let time = timings.last.flatMap { $0 }
        if let last = segments.last, last.time == time {
            segments[segments.count - 1] = LyricWord(time: time, text: last.text + text)
        } else {
            segments.append(LyricWord(time: time, text: text))
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if ignoredDepth > 0 { ignoredDepth -= 1; return }
        if name == "span", !timings.isEmpty { timings.removeLast() }
        if name == "p", paragraph {
            paragraph = false
            let text = segments.map(\.text).joined()
            let start = lineStart ?? segments.compactMap(\.time).first
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append(LyricLine(id: lines.count, time: start, text: text, words: segments))
            }
        }
    }

    private static func time(_ value: String?) -> Double? {
        guard let value = value else { return nil }
        let parts = value.split(separator: ":")
        let seconds: Double?
        if value.hasSuffix("ms") { seconds = Double(value.dropLast(2)).map { $0 / 1000 } }
        else if value.hasSuffix("s") { seconds = Double(value.dropLast()) }
        else if (1...3).contains(parts.count), parts.allSatisfy({ Double($0) != nil }) {
            seconds = parts.compactMap { Double($0) }.reduce(0) { $0 * 60 + $1 }
        } else { seconds = nil }
        guard let seconds = seconds, seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }
}
