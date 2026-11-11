// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum DownloadFolder {
    static let bookmarkKey = "storage.folderBookmark"
    static let nameKey = "storage.folderName"

    static func bookmark(for url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw PlayError.message("Play could not access that folder. Choose it again in Files.")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func copy(_ files: [(source: URL, name: String)], bookmark: Data) async throws {
        try await Task.detached(priority: .utility) {
            var stale = false
            let folder = try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
            guard !stale, folder.startAccessingSecurityScopedResource() else {
                throw PlayError.message("Choose the download folder again in Files.")
            }
            defer { folder.stopAccessingSecurityScopedResource() }
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var copyError: Error?
            coordinator.coordinate(writingItemAt: folder, options: [], error: &coordinationError) { target in
                do {
                    for file in files {
                        let destination = try DownloadFile.url(filename: file.name, directory: target)
                        if !FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.copyItem(at: file.source, to: destination)
                        }
                    }
                } catch { copyError = error }
            }
            if let error = coordinationError { throw error }
            if let error = copyError { throw error }
        }.value
    }

    static func fileName(for song: Song, source: URL) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let title = (song.title + " - " + song.artist).components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        var stem = title.isEmpty ? "Song" : String(title.prefix(70))
        while stem.utf8.count > 160 { stem.removeLast() }
        return stem + " - " + source.lastPathComponent
    }
}
