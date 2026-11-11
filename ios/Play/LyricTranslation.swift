// SPDX-License-Identifier: GPL-3.0-only
import Foundation

actor LyricTranslation {
    static let shared = LyricTranslation()
    private var cache: [[LyricLine]: [LyricLine]] = [:]

    func english(_ original: [LyricLine]) async throws -> [LyricLine] {
        if let translated = cache[original] { return translated }
        guard original.count <= 500 else { throw PlayError.message("These lyrics are too long to translate.") }
        var result = original
        var batch: [(index: Int, text: String)] = []
        var size = 0
        for (index, line) in original.enumerated() {
            let text = line.text.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            guard text.utf8.count <= 1_800 else { throw PlayError.message("A lyric line is too long to translate.") }
            if batch.count >= 16 || size + text.utf8.count > 1_800 {
                try await replace(batch, in: &result)
                batch = []
                size = 0
            }
            batch.append((index, text))
            size += text.utf8.count + 1
        }
        if !batch.isEmpty { try await replace(batch, in: &result) }
        try Task.checkCancellation()
        if cache.count >= 8, let oldest = cache.keys.first { cache.removeValue(forKey: oldest) }
        cache[original] = result
        return result
    }

    private func replace(_ batch: [(index: Int, text: String)], in result: inout [LyricLine]) async throws {
        try Task.checkCancellation()
        var url = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        url.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: batch.map(\.text).joined(separator: "\n"))
        ]
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let endpoint = url.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, timeoutInterval: 10))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PlayError.message("English translation is unavailable right now.")
        }
        let replacements = try Self.translatedLines(from: data, expected: batch.count)
        for (source, text) in zip(batch, replacements) {
            let line = result[source.index]
            if line.text != text { result[source.index] = LyricLine(id: line.id, time: line.time, text: text) }
        }
    }

    static func translatedLines(from data: Data, expected: Int) throws -> [String] {
        let root = try JSONSerialization.jsonObject(with: data) as? [Any]
        let segments = root?.first as? [[Any]] ?? []
        let text = segments.compactMap { $0.first as? String }.joined()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count == expected, lines.allSatisfy({ !$0.isEmpty }) else {
            throw PlayError.message("Could not match the translation to the song’s timing.")
        }
        return lines
    }
}
