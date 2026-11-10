// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main
struct PlayApp: App {
    @StateObject private var library = LibraryStore()
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
