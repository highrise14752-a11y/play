// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct Song: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var artist: String
    var artwork: URL?
    var duration: Double?
    // A relative filename, never an expiring stream URL or absolute sandbox path.
    var localFile: String?
    var isLocal: Bool { id.hasPrefix("local:") }
}

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: Double?
    let text: String
}

enum LyricsParser {
    static func parse(_ text: String) -> [LyricLine] {
        let expression = try! NSRegularExpression(pattern: #"\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        var timed: [(Double, String)] = []
        var plain: [String] = []
        var offset = 0.0
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("[offset:"), let end = line.firstIndex(of: "]") {
                offset = (Double(line[line.index(line.startIndex, offsetBy: 8)..<end]) ?? 0) / 1000
                continue
            }
            let matches = expression.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else {
                if !line.isEmpty && !line.hasPrefix("[") { plain.append(line) }
                continue
            }
            let lyric = expression.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                func part(_ i: Int) -> String {
                    Range(match.range(at: i), in: line).map { String(line[$0]) } ?? ""
                }
                let fraction = part(3)
                let seconds = (Double(part(1)) ?? 0) * 60 + (Double(part(2)) ?? 0)
                timed.append((seconds + (fraction.isEmpty ? 0 : (Double("0." + fraction) ?? 0)), lyric))
            }
        }
        if !timed.isEmpty {
            return timed.enumerated().sorted {
                $0.element.0 == $1.element.0 ? $0.offset < $1.offset : $0.element.0 < $1.element.0
            }.enumerated().map { index, value in
                LyricLine(id: index, time: max(0, value.element.0 + offset), text: value.element.1)
            }
        }
        return plain.enumerated().map { LyricLine(id: $0.offset, time: nil, text: $0.element) }
    }

    static func activeIndex(in lines: [LyricLine], at seconds: Double) -> Int? {
        guard seconds.isFinite else { return nil }
        return lines.lastIndex { $0.time.map { $0 <= seconds } ?? false }
    }
}

enum PlayError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
