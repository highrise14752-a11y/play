// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main
struct PlayApp: App {
    @StateObject private var library: LibraryStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Play-UI-" + UUID().uuidString)
            let store = LibraryStore(directory: directory)
            UISampleData.songs.forEach(store.save)
            var snapshot = CollectionSnapshot()
            if let first = UISampleData.songs.first {
                snapshot.likedIDs.insert(first.id)
                snapshot.playlists = [LocalPlaylist(name: "Favorites", songIDs: UISampleData.songs.prefix(4).map(\.id))]
            }
            for song in UISampleData.songs.prefix(3) {
                snapshot.history.append(ListeningEntry(song: song, seconds: 180))
                snapshot.totals[song.id] = ListeningTotal(song: song, plays: 1, seconds: 180)
            }
            store.collections.restore(snapshot)
            _library = StateObject(wrappedValue: store)
            return
        }
        #endif
        _library = StateObject(wrappedValue: LibraryStore())
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(library.player)
                .environmentObject(library.together)
                .environmentObject(library.player.haptics)
                .environmentObject(library.collections)
                .tint(PlayTheme.accent)
                .font(.custom("Poppins-Regular", size: 15))
                .preferredColorScheme(.dark)
        }
    }
}
