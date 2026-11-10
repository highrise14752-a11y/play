// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

enum PlayTheme {
    static var background: Color { (UserDefaults.standard.object(forKey: "appearance.pureBlack") as? Bool ?? true) ? .black : color(0x141214) }
    static let surface = Color(red: 0.125, green: 0.12, blue: 0.125)
    static let outline = Color.white.opacity(0.17)
    static var accent: Color {
        let value = UserDefaults.standard.integer(forKey: "appearance.accent")
        return color(value == 0 ? 0xFFB3BB : value)
    }
    static func color(_ hex: Int) -> Color { Color(red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255) }
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom("Poppins-Regular", size: size).weight(weight) }
}

enum TrackTime {
    static func text(_ seconds: Double?, elapsed: Bool = false) -> String {
        guard let seconds = seconds, seconds.isFinite, seconds >= 0, seconds < 10_000_000 else { return "—" }
        let value = Int(elapsed ? floor(seconds) : seconds.rounded())
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var together: TogetherSession
    @EnvironmentObject private var haptics: MusicHaptics
    @EnvironmentObject private var collections: UserCollections
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var home = HomeFeed()
    @State private var tab = 0
    @State private var showingPlayer = false
    @State private var searching = false
    @AppStorage("appearance.accent") private var accent = 0xFFB3BB
    @AppStorage("appearance.pureBlack") private var pureBlack = true
    private let labels = ["Home", "Stats", "History", "Library"]
    private let icons = ["safari.fill", "chart.line.uptrend.xyaxis", "clock.fill", "square.grid.2x2.fill"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    if tab == 0 { Image("PlayLogo").resizable().scaledToFit().frame(width: 32, height: 32) }
                    Text(tab == 0 ? "Play" : labels[tab]).font(PlayTheme.font(28, weight: .bold)).accessibilityIdentifier("page.title")
                    Spacer()
                    Button { searching = true } label: { Image(systemName: "magnifyingglass").font(.system(size: 23)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Search")
                    NavigationLink { SettingsView().navigationBarHidden(false) } label: { Image(systemName: "gearshape").font(.system(size: 23)).frame(width: 44, height: 44) }
                        .accessibilityLabel("Settings").accessibilityIdentifier("open.settings")
                }.foregroundColor(PlayTheme.color(0xEDDADF)).padding(.horizontal, 18).padding(.vertical, 10)
                Group {
                    switch tab {
                    case 1: StatsView()
                    case 2: HistoryView()
                    case 3: LibraryView()
                    default: HomeView(feed: home)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background((pureBlack ? Color.black : PlayTheme.background).ignoresSafeArea()).navigationBarHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    MiniPlayerView(showingPlayer: $showingPlayer)
                    HStack(spacing: 0) {
                        ForEach(0..<4) { index in
                            Button { tab = index } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: icons[index]).font(.system(size: 21, weight: .medium))
                                        .frame(width: 50, height: 31)
                                        .background(Capsule().fill(index == tab ? PlayTheme.color(accent).opacity(0.3) : .clear))
                                    Text(labels[index]).font(PlayTheme.font(11))
                                }.foregroundColor(index == tab ? PlayTheme.color(accent) : Color(red: 0.8, green: 0.73, blue: 0.75))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }.accessibilityIdentifier("tab.\(labels[index].lowercased())")
                        }
                    }.background(RoundedRectangle(cornerRadius: 27).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 27).stroke(PlayTheme.outline, lineWidth: 1))
                }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 5).background(Color.black)
            }
        }.navigationViewStyle(.stack).tint(PlayTheme.color(accent))
        .sheet(isPresented: $showingPlayer) { NavigationView { PlayerView() }.navigationViewStyle(.stack) }
        .sheet(isPresented: $searching) { NavigationView { SearchView() }.navigationViewStyle(.stack) }
        .onChange(of: scenePhase) {
            haptics.setVisible($0 == .active)
            if $0 != .active { collections.flush() }
        }
        .onOpenURL { together.join(link: $0.absoluteString, name: UserDefaults.standard.string(forKey: "together.name") ?? "Listener") }
        .alert("Play", isPresented: Binding(get: { library.error != nil || collections.error != nil }, set: { if !$0 { library.error = nil; collections.error = nil } })) {
            Button("OK") { library.error = nil; collections.error = nil }
        } message: { Text(library.error ?? collections.error ?? "") }
    }
}

@MainActor final class HomeFeed: ObservableObject {
    @Published var category: String?
    @Published private(set) var songs: [Song] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var loaded = false
    private var loadedCategory: String?
    private var loadedLocale = ""
    private var requestID = UUID()
    func load(api: MusicAPI, force: Bool = false) async {
        let locale = (UserDefaults.standard.string(forKey: "content.language") ?? "en") + (UserDefaults.standard.string(forKey: "content.region") ?? "US")
        if loaded && loadedCategory == category && loadedLocale == locale && !force { return }
        let id = UUID(); requestID = id
        loading = true; error = nil
        defer { if requestID == id { loading = false } }
        do {
            let results = try await api.home(category: category)
            guard !Task.isCancelled, requestID == id else { return }
            songs = results; loaded = true; loadedCategory = category; loadedLocale = locale
        } catch {
            if !Task.isCancelled && requestID == id { self.error = error.localizedDescription }
        }
    }
    #if DEBUG
    func loadPreview() { songs = UISampleData.songs; loading = false }
    #endif
}

struct CategoryChips: View {
    let choices: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { choice in
                    Button { selection = choice } label: {
                        Text(choice).font(PlayTheme.font(12)).padding(.horizontal, 15).padding(.vertical, 8)
                            .background(Capsule().fill(selection == choice ? PlayTheme.accent.opacity(0.27) : PlayTheme.surface))
                            .foregroundColor(selection == choice ? PlayTheme.accent : .white.opacity(0.75))
                    }
                }
            }.padding(.horizontal, 16)
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    @ObservedObject var feed: HomeFeed
    private let moods = ["All", "Workout", "Relax", "Focus", "Sleep", "Party", "Romance", "Energy"]
    private var recent: [Song] {
        var seen = Set<String>()
        return collections.state.history.map(\.song).filter { seen.insert($0.id).inserted }.prefix(12).map { $0 }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                CategoryChips(choices: moods, selection: Binding(get: { feed.category ?? "All" }, set: { feed.category = $0 == "All" ? nil : $0 }))
                if feed.loading && feed.songs.isEmpty { ProgressView("Loading suggestions…").frame(maxWidth: .infinity).padding(30) }
                if let error = feed.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(PlayTheme.font(13)).foregroundColor(.secondary)
                        Button("Try again") { Task { await feed.load(api: library.api, force: true) } }
                    }.padding(.horizontal, 20)
                }
                if !feed.songs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(feed.songs.prefix(8))) { song in
                                Button { library.play(song, in: feed.songs) } label: {
                                    ZStack(alignment: .bottomLeading) {
                                        Artwork(url: song.artwork).frame(width: 230, height: 270)
                                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(song.title).font(PlayTheme.font(16, weight: .semibold)).lineLimit(2)
                                            Text(song.artist).font(PlayTheme.font(12)).foregroundColor(.white.opacity(0.75)).lineLimit(1)
                                        }.padding(14)
                                    }.frame(width: 230, height: 270).clipShape(RoundedRectangle(cornerRadius: 23))
                                        .overlay(RoundedRectangle(cornerRadius: 23).stroke(PlayTheme.outline))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16)
                    }
                    HStack {
                        Text("Quick picks").font(PlayTheme.font(21, weight: .medium))
                        Spacer()
                        Button("Play all") { if let song = feed.songs.first { library.play(song, in: feed.songs) } }
                            .font(PlayTheme.font(11)).padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(PlayTheme.surface))
                    }.padding(.horizontal, 18)
                    ForEach(Array(feed.songs.prefix(8))) { song in SongRow(song: song, queue: feed.songs).padding(.horizontal, 16) }
                }
                if !recent.isEmpty {
                    Text("Keep listening").font(PlayTheme.font(21, weight: .medium)).padding(.horizontal, 18)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(recent) { song in
                                Button { library.play(song, in: recent) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Artwork(url: song.artwork).frame(width: 106, height: 106).clipShape(Circle())
                                        Text(song.title).font(PlayTheme.font(12)).lineLimit(1)
                                        Text(song.artist).font(PlayTheme.font(10)).foregroundColor(.secondary).lineLimit(1)
                                    }.frame(width: 106)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 16)
                    }
                }
                if feed.songs.isEmpty && !feed.loading && feed.error == nil {
                    Text("Find your next favorite song using Search.").font(PlayTheme.font(14)).foregroundColor(.secondary).padding(20)
                }
            }.padding(.vertical, 8)
        }.refreshable { await feed.load(api: library.api, force: true) }
        .task(id: feed.category) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") { feed.loadPreview(); return }
            #endif
            await feed.load(api: library.api)
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if collections.state.history.isEmpty { EmptyMusicState(title: "Your listening history", message: "Songs you listen to will appear here.", icon: "clock") }
                ForEach(collections.state.history) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.startedAt, style: .date).font(PlayTheme.font(10)).foregroundColor(.secondary)
                        SongRow(song: entry.song, queue: collections.state.history.map(\.song))
                    }.contextMenu { Button(role: .destructive) { collections.removeHistory(entry) } label: { Label("Remove from history", systemImage: "trash") } }
                }
            }.padding(16)
        }
    }
}

struct StatsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    @State private var period = "All time"
    private var entries: [ListeningEntry] {
        let days = period == "7 days" ? 7 : 30
        let since = Date().addingTimeInterval(-Double(days) * 86400)
        return collections.state.history.filter { $0.startedAt >= since }
    }
    private var totals: [ListeningTotal] {
        if period == "All time" { return collections.state.totals.values.sorted { $0.seconds > $1.seconds } }
        var result: [String: ListeningTotal] = [:]
        for entry in entries {
            var total = result[entry.song.id] ?? ListeningTotal(song: entry.song)
            total.plays += 1; total.seconds += entry.seconds; result[entry.song.id] = total
        }
        return result.values.sorted { $0.seconds > $1.seconds }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                CategoryChips(choices: ["7 days", "30 days", "All time"], selection: $period).padding(.horizontal, -16)
                HStack(spacing: 12) {
                    statCard("Listening time", value: "\(Int(totals.reduce(0) { $0 + $1.seconds } / 60)) min", icon: "headphones")
                    statCard("Songs played", value: "\(totals.reduce(0) { $0 + $1.plays })", icon: "music.note")
                }
                Text("Top songs").font(PlayTheme.font(22, weight: .semibold))
                if totals.isEmpty { EmptyMusicState(title: "Make some music memories", message: "Your listening stats appear after you play music.", icon: "chart.bar") }
                ForEach(Array(totals.prefix(50)), id: \.song.id) { total in
                    VStack(alignment: .leading, spacing: 3) {
                        SongRow(song: total.song, queue: totals.map(\.song))
                        Text("\(total.plays) plays • \(TrackTime.text(total.seconds)) listened").font(PlayTheme.font(10)).foregroundColor(.secondary).padding(.leading, 66)
                    }
                }
            }.padding(16)
        }
    }
    private func statCard(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).foregroundColor(PlayTheme.accent)
            Text(value).font(PlayTheme.font(23, weight: .semibold))
            Text(title).font(PlayTheme.font(11)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(RoundedRectangle(cornerRadius: 22).fill(PlayTheme.surface))
    }
}

struct EmptyMusicState: View {
    let title: String
    let message: String
    let icon: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 34)).foregroundColor(PlayTheme.accent)
            Text(title).font(PlayTheme.font(18, weight: .medium))
            Text(message).font(PlayTheme.font(13)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 50)
    }
}

struct NameEntryView: View {
    let title: String
    let submit: (String) -> Void
    @State var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).padding()
                Spacer()
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .navigationBarTrailing) { Button("Save") { submit(name); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
        }.navigationViewStyle(.stack)
    }
}

struct SongCollectionView: View {
    let title: String
    let songs: [Song]
    var playlistID: String? = nil
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    var body: some View {
        List {
            if !songs.isEmpty {
                HStack {
                    Button { library.play(songs[0], in: songs) } label: { Label("Play all", systemImage: "play.fill") }
                    Spacer()
                    Button { library.player.setShuffle(true); if let song = songs.randomElement() { library.play(song, in: songs) } } label: { Label("Shuffle", systemImage: "shuffle") }
                }.padding(.vertical, 10)
            }
            if songs.isEmpty { Text("No songs yet").foregroundColor(.secondary) }
            ForEach(songs) { song in
                SongRow(song: song, queue: songs)
                    .swipeActions { if let id = playlistID { Button("Remove", role: .destructive) { collections.remove(song, from: id) } } }
                    .listRowBackground(Color.black).listRowSeparator(.hidden)
            }.onMove { from, to in if let id = playlistID { collections.moveSongs(in: id, from: from, to: to) } }
        }.listStyle(.plain).navigationTitle(title).navigationBarTitleDisplayMode(.inline).navigationBarHidden(false)
    }
}

struct AutoCollectionView: View {
    let kind: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    private var songs: [Song] {
        switch kind {
        case "Liked": return library.songs.filter { collections.liked($0) }
        case "Downloaded": return library.songs.filter { $0.localFile != nil }
        default: return collections.state.totals.values.sorted { $0.seconds > $1.seconds }.prefix(50).map(\.song)
        }
    }
    var body: some View { SongCollectionView(title: kind, songs: songs) }
}

struct GroupedCollectionView: View {
    let title: String
    let isAlbum: Bool
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        SongCollectionView(title: title, songs: library.songs.filter { isAlbum ? ($0.album ?? "Unknown album") == title : $0.artist == title })
    }
}
