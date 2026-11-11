// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum CatalogLink: Equatable {
    case song(String)
    case playlist(String)

    static func parse(_ input: String) -> Self? {
        guard let url = URLComponents(string: input), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        let scheme = url.scheme?.lowercased()
        let query = url.queryItems ?? []
        func parameter(_ name: String) -> String? { query.first { $0.name == name }?.value }
        if scheme == "play", host == "song", let id = parameter("v"), valid(id, length: 11...11) { return .song(id) }
        guard scheme == "https", url.port == nil else { return nil }
        let path = url.path.split(separator: "/")
        if host == "youtu.be", path.count == 1 {
            let id = String(path[0])
            return valid(id, length: 11...11) ? .song(id) : nil
        }
        guard ["music.youtube.com", "youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) else { return nil }
        if url.path == "/watch", let id = parameter("v"), valid(id, length: 11...11) { return .song(id) }
        if path.count == 2, path[0] == "shorts" || path[0] == "live" {
            let id = String(path[1])
            return valid(id, length: 11...11) ? .song(id) : nil
        }
        if url.path == "/playlist", let id = parameter("list"), valid(id, length: 2...100) { return .playlist(id) }
        return nil
    }

    private static func valid(_ id: String, length: ClosedRange<Int>) -> Bool {
        length.contains(id.utf8.count) && id.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

struct PublicPlaylist {
    let title: String
    let songs: [Song]
}
