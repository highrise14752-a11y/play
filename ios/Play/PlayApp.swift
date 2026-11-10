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
                .tint(.cyan)
                .preferredColorScheme(.dark)
        }
    }
}
