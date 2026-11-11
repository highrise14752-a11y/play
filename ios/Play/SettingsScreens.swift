// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Image("PlayLogo").resizable().scaledToFit().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Play").font(PlayTheme.font(30, weight: .bold))
                        Text("Music. Your way.").font(PlayTheme.font(12)).foregroundColor(.secondary)
                    }
                    Spacer()
                }.padding(20).background(RoundedRectangle(cornerRadius: 25).fill(PlayTheme.accent.opacity(0.12)))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        quick("Appearance", icon: "paintpalette") { AppearanceSettingsView() }
                        quick("Player", icon: "play.fill") { PlayerSettingsView() }
                        quick("Storage", icon: "externaldrive") { StorageSettingsView() }
                        quick("Privacy", icon: "hand.raised") { PrivacySettingsView() }
                        quick("Together", icon: "person.2") { TogetherView() }
                    }
                }
                group("Interface") {
                    NavigationLink { AppearanceSettingsView() } label: { SettingsRow(title: "Appearance", subtitle: "Theme and lyrics", icon: "paintpalette") }.accessibilityIdentifier("settings.appearance")
                }
                group("Player and content") {
                    NavigationLink { PlayerSettingsView() } label: { SettingsRow(title: "Player and audio", subtitle: "Playback, haptics and sleep timer", icon: "play.fill") }.accessibilityIdentifier("settings.player")
                    NavigationLink { TogetherView() } label: { SettingsRow(title: "Music Together", subtitle: "Listen with friends", icon: "person.2") }.accessibilityIdentifier("settings.together")
                    NavigationLink { ContentSettingsView() } label: { SettingsRow(title: "Content", subtitle: "Language and region", icon: "globe") }.accessibilityIdentifier("settings.content")
                }
                group("Privacy and storage") {
                    NavigationLink { PrivacySettingsView() } label: { SettingsRow(title: "Privacy", subtitle: "Listening history", icon: "hand.raised") }.accessibilityIdentifier("settings.privacy")
                    NavigationLink { StorageSettingsView() } label: { SettingsRow(title: "Storage", subtitle: "Downloads and cache", icon: "externaldrive") }.accessibilityIdentifier("settings.storage")
                    NavigationLink { BackupSettingsView() } label: { SettingsRow(title: "Backup and restore", subtitle: "Library and playlists", icon: "icloud.and.arrow.up") }.accessibilityIdentifier("settings.backup")
                }
                group("App") {
                    NavigationLink { AboutSettingsView() } label: { SettingsRow(title: "About", subtitle: "Play", icon: "info.circle") }.accessibilityIdentifier("settings.about")
                }
            }.padding(16)
        }.background(PlayTheme.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).navigationBarHidden(false)
    }
    private func quick<Destination: View>(_ title: String, icon: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 22)).frame(width: 58, height: 58).background(RoundedRectangle(cornerRadius: 19).fill(PlayTheme.accent.opacity(0.13)))
                Text(title).font(PlayTheme.font(10)).foregroundColor(.primary)
            }.frame(width: 68)
        }
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(PlayTheme.font(10, weight: .medium)).foregroundColor(PlayTheme.accent).padding(.leading, 5)
            VStack(spacing: 0, content: content).background(RoundedRectangle(cornerRadius: 23).fill(PlayTheme.surface))
        }
    }
}

struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(PlayTheme.accent).frame(width: 37, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(PlayTheme.font(14, weight: .medium)).foregroundColor(.primary)
                Text(subtitle).font(PlayTheme.font(10)).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.secondary)
        }.padding(14).contentShape(Rectangle())
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appearance.accent") private var accent = 0xFFB3BB
    @AppStorage("appearance.pureBlack") private var pureBlack = true
    @AppStorage("appearance.mode") private var mode = "Dark"
    @AppStorage("appearance.systemFont") private var systemFont = false
    @AppStorage("appearance.randomAccent") private var randomAccent = false
    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Pure black background", isOn: $pureBlack)
                HStack {
                    Text("Accent color")
                    Spacer()
                    ForEach(PlayTheme.palette, id: \.self) { value in
                        Button { accent = value } label: {
                            Circle().fill(PlayTheme.color(value)).frame(width: 25, height: 25)
                                .overlay(Circle().stroke(.white, lineWidth: accent == value ? 2 : 0))
                        }.buttonStyle(.plain).accessibilityLabel("Accent \(value)")
                    }
                }
            }
            Section("Lyrics") {
                NavigationLink("Lyrics appearance") { LyricsSettingsView() }
            }
            Section("Interface") {
                Picker("Theme", selection: $mode) {
                    ForEach(["System", "Dark", "Light"], id: \.self) { Text($0) }
                }
                Toggle("Use system font", isOn: $systemFont)
                Toggle("Random accent on startup", isOn: $randomAccent)
                NavigationLink("Theme creator") { ThemeCreatorView() }
                NavigationLink("Navigation and library") { LayoutSettingsView() }
                NavigationLink("Player appearance") { PlayerAppearanceSettingsView() }
            }
        }.navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeCreatorView: View {
    @AppStorage("appearance.accent") private var accent = 0xFFB3BB
    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?

    var body: some View {
        Form {
            ColorPicker("Accent color", selection: Binding(get: { PlayTheme.color(accent) }, set: {
                if let rgb = PlayTheme.rgb($0) { accent = rgb }
            }), supportsOpacity: false)
            HStack {
                Image(systemName: "play.circle.fill").font(.largeTitle)
                Text("Play").font(PlayTheme.font(22, weight: .bold))
            }.foregroundColor(PlayTheme.color(accent))
            Button("Export theme") { exporting = true }
            Button("Import theme") { importing = true }
            if let message = message { Text(message).font(.caption) }
        }
        .navigationTitle("Theme creator").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: ThemeDocument(accent: accent), contentType: .json, defaultFilename: "Play Theme") {
            if case .failure(let error) = $0 { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 64_000 else {
                    throw PlayError.message("The theme file is too large.")
                }
                let theme = try JSONDecoder().decode(ThemeDocument.self, from: Data(contentsOf: url))
                guard (0...0xFFFFFF).contains(theme.accent) else { throw PlayError.message("Invalid accent color.") }
                accent = theme.accent
                message = "Theme imported"
            } catch { message = error.localizedDescription }
        }
    }
}

struct ThemeDocument: FileDocument, Codable {
    static let readableContentTypes: [UTType] = [.json]
    let accent: Int
    init(accent: Int) { self.accent = accent }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count < 64_000 else {
            throw PlayError.message("Invalid theme file.")
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try JSONEncoder().encode(self))
    }
}

struct LayoutSettingsView: View {
    @AppStorage("appearance.defaultTab") private var tab = 0
    @AppStorage("appearance.defaultLibrary") private var library = "Playlists"
    @AppStorage("appearance.homeChips") private var chips = true
    @AppStorage("appearance.slimNav") private var slim = false
    @AppStorage("appearance.swipeQueue") private var swipeQueue = false
    @AppStorage("appearance.showLiked") private var liked = true
    @AppStorage("appearance.showDownloaded") private var downloaded = true
    @AppStorage("appearance.showTop") private var top = true

    var body: some View {
        Form {
            Picker("Default tab", selection: $tab) {
                Text("Home").tag(0); Text("Stats").tag(1); Text("History").tag(2); Text("Library").tag(3)
            }
            Picker("Default library view", selection: $library) {
                ForEach(["Playlists", "Songs", "Albums", "Artists"], id: \.self) { Text($0) }
            }
            Toggle("Show Home category chips", isOn: $chips)
            Toggle("Slim bottom navigation", isOn: $slim)
            Toggle("Swipe songs to queue them", isOn: $swipeQueue)
            Section("Automatic playlists") {
                Toggle("Show Liked", isOn: $liked)
                Toggle("Show Downloaded", isOn: $downloaded)
                Toggle("Show Top", isOn: $top)
            }
        }.navigationTitle("Navigation and library").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerAppearanceSettingsView: View {
    @AppStorage("appearance.playerBackground") private var background = "Gradient"
    @AppStorage("appearance.hideArtwork") private var hideArtwork = false
    @AppStorage("appearance.cropArtwork") private var crop = true
    @AppStorage("appearance.artworkSwipe") private var swipe = false
    @AppStorage("appearance.swipeDistance") private var swipeDistance = 52.0
    @AppStorage("appearance.compactMini") private var compactMini = false
    @AppStorage("appearance.accentButtons") private var accentButtons = false
    @AppStorage("appearance.playerCompact") private var compactPlayer = false

    var body: some View {
        Form {
            Picker("Player background", selection: $background) {
                ForEach(["Gradient", "Solid", "Blurred artwork"], id: \.self) { Text($0) }
            }
            Toggle("Hide player thumbnail", isOn: $hideArtwork)
            Toggle("Crop player artwork to square", isOn: $crop)
            Toggle("Swipe artwork to change song", isOn: $swipe)
            if swipe { Slider(value: $swipeDistance, in: 28...100) { Text("Swipe distance") } }
            Toggle("Compact mini player", isOn: $compactMini)
            Toggle("Compact player controls", isOn: $compactPlayer)
            Toggle("Use accent color for play button", isOn: $accentButtons)
        }.navigationTitle("Player appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct LyricsSettingsView: View {
    @AppStorage("lyrics.style") private var style = "Apple Music"
    @AppStorage("lyrics.position") private var position = "Center"
    @AppStorage("lyrics.follow") private var follow = true
    @AppStorage("lyrics.click") private var click = true
    @AppStorage("lyrics.size") private var size = 28.0
    @AppStorage("lyrics.spacing") private var spacing = 22.0
    var body: some View {
        Form {
            Picker("Animation style", selection: $style) {
                ForEach(["Apple Music", "Fade", "Glow", "Slide", "Karaoke", "None"], id: \.self) { Text($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("lyrics.animation")
            Picker("Text position", selection: $position) {
                ForEach(["Left", "Center", "Right"], id: \.self) { Text($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("lyrics.position")
            Toggle("Automatic scrolling", isOn: $follow)
            Toggle("Tap lyrics to seek", isOn: $click)
            VStack(alignment: .leading) { Text("Text size: \(Int(size))"); Slider(value: $size, in: 18...42, step: 1) }
            VStack(alignment: .leading) { Text("Line spacing: \(Int(spacing))"); Slider(value: $spacing, in: 8...42, step: 1) }
            Text("Following requires timed lyrics. Drag to browse; following resumes after three seconds.").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject private var player: PlaybackController
    @AppStorage("player.quality") private var quality = "Automatic"
    @AppStorage("player.metered") private var metered = false
    @AppStorage("player.persistentQueue") private var persistentQueue = false
    @AppStorage("player.keepShuffle") private var keepShuffle = false
    @AppStorage("player.savedShuffle") private var savedShuffle = false
    @AppStorage("player.downloadLikes") private var downloadLikes = false
    @AppStorage("player.skipErrors") private var skipErrors = false
    @AppStorage("player.pauseAtZero") private var pauseAtZero = false
    @AppStorage("player.bluetoothStart") private var bluetoothStart = false
    @AppStorage("player.progressiveSeek") private var progressiveSeek = false
    @AppStorage("player.historyMinimum") private var historyMinimum = 30.0
    var body: some View {
        Form {
            Section("Music haptics") {
                NavigationLink("Music haptics") { HapticsSettingsView() }
            }
            Section("Playback") {
                Toggle("Shuffle", isOn: Binding(get: { player.shuffleEnabled }, set: player.setShuffle))
                Picker("Repeat", selection: Binding(get: { player.repeatMode.rawValue }, set: { player.setRepeat(PlayRepeatMode(rawValue: $0) ?? .off) })) {
                    Text("Off").tag(0); Text("One song").tag(1); Text("All songs").tag(2)
                }
                NavigationLink("Sleep timer") { SleepTimerView() }
                Picker("Audio quality", selection: $quality) {
                    ForEach(["Automatic", "High", "Low"], id: \.self) { Text($0) }
                }
                Toggle("Treat network as metered", isOn: $metered)
                Toggle("Pause at zero device volume", isOn: $pauseAtZero)
                Toggle("Resume on Bluetooth connect", isOn: $bluetoothStart)
                Toggle("Progressive skip intervals", isOn: $progressiveSeek)
                VStack(alignment: .leading) {
                    Text("Minimum listening time for history: \(Int(historyMinimum)) sec")
                    Slider(value: $historyMinimum, in: 0...120, step: 5)
                }
            }
            Section("Queue") {
                Toggle("Restore queue and position", isOn: $persistentQueue)
                    .onChange(of: persistentQueue) { _ in player.persistQueue() }
                Toggle("Remember shuffle mode", isOn: $keepShuffle)
                    .onChange(of: keepShuffle) { if $0 { savedShuffle = player.shuffleEnabled } }
                Toggle("Skip songs that fail to play", isOn: $skipErrors)
                Toggle("Download songs when liked", isOn: $downloadLikes)
            }
        }.navigationTitle("Player and audio").navigationBarTitleDisplayMode(.inline)
    }
}

struct SleepTimerView: View {
    @EnvironmentObject private var player: PlaybackController
    var body: some View {
        Form {
            if let deadline = player.sleepDeadline { HStack { Text("Stops at"); Spacer(); Text(deadline, style: .time) } }
            if player.stopAtTrackEnd { Text("Stops after the current song") }
            ForEach([5, 10, 15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Button("\(minutes) minutes") { player.setSleepTimer(minutes: Double(minutes)) }
            }
            Button("After current song") { player.sleepAfterCurrentSong() }
            Button("Turn off timer") { player.setSleepTimer(minutes: nil) }
        }.navigationTitle("Sleep timer").navigationBarTitleDisplayMode(.inline)
    }
}

struct QueueView: View {
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var together: TogetherSession
    var body: some View {
        List {
            ForEach(player.queue) { song in SongRow(song: song, queue: player.queue) }
                .onMove(perform: player.moveQueue)
                .onDelete(perform: player.removeQueue)
        }.listStyle(.plain).navigationTitle("Queue").navigationBarTitleDisplayMode(.inline)
            .toolbar { if !together.connected || together.isHost { EditButton() } }
    }
}

struct ContentSettingsView: View {
    @AppStorage("content.language") private var language = "en"
    @AppStorage("content.region") private var region = "US"
    @AppStorage("content.hideExplicit") private var hideExplicit = false
    @AppStorage("content.hideVideos") private var hideVideos = false
    @AppStorage("content.topCount") private var topCount = 50
    @AppStorage("lyrics.preferredSource") private var preferred = LyricSource.lrcLib.rawValue
    @AppStorage("lyrics.preload") private var preload = false
    @AppStorage("lyrics.preloadCount") private var preloadCount = 3
    private let languages = [("en", "English"), ("hi", "Hindi"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("ja", "Japanese"), ("ko", "Korean"), ("pt", "Portuguese"), ("ar", "Arabic")]
    var body: some View {
        Form {
            Picker("Content language", selection: $language) { ForEach(languages, id: \.0) { Text($0.1).tag($0.0) } }
            Picker("Content region", selection: $region) {
                ForEach(Locale.isoRegionCodes.sorted(), id: \.self) { Text(Locale.current.localizedString(forRegionCode: $0) ?? $0).tag($0) }
            }
            Text("These preferences affect music-service results. They do not translate lyrics.").font(.caption).foregroundColor(.secondary)
            Toggle("Hide explicit songs", isOn: $hideExplicit)
            Toggle("Hide music videos", isOn: $hideVideos)
            Picker("Top playlist length", selection: $topCount) {
                ForEach([10, 25, 50, 100, 200], id: \.self) { Text("\($0) songs").tag($0) }
            }
            Section("Lyrics providers") {
                ForEach(LyricSource.allCases) { source in LyricsProviderToggle(source: source) }
                Picker("Preferred provider", selection: $preferred) {
                    ForEach(LyricSource.allCases) { source in Text(source.rawValue).tag(source.rawValue) }
                }
                Toggle("Preload queue lyrics", isOn: $preload)
                if preload { Stepper("Songs to preload: \(preloadCount)", value: $preloadCount, in: 1...10) }
            }
        }.navigationTitle("Content").navigationBarTitleDisplayMode(.inline)
    }
}

private struct LyricsProviderToggle: View {
    let source: LyricSource
    @AppStorage private var enabled: Bool

    init(source: LyricSource) {
        self.source = source
        _enabled = AppStorage(wrappedValue: true, source.setting)
    }

    var body: some View { Toggle(source.rawValue, isOn: $enabled) }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var collections: UserCollections
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("privacy.pauseHistory") private var paused = false
    @AppStorage("privacy.pauseSearch") private var searchPaused = false
    @State private var clearing = false
    @State private var clearingSearch = false
    var body: some View {
        Form {
            Toggle("Pause listening history", isOn: Binding(get: { paused }, set: {
                collections.flush(); paused = $0
                if !$0, library.player.isPlaying, let song = library.player.current { collections.started(song) }
            }))
            Button("Clear listening history", role: .destructive) { clearing = true }
            Section("Search history") {
                Toggle("Pause search history", isOn: $searchPaused)
                Button("Clear search history", role: .destructive) { clearingSearch = true }
            }
            Text("Play stores your listening history on this device. Music and lyrics services receive the requests needed to play songs and load lyrics.").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
            .alert("Clear listening history and stats?", isPresented: $clearing) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { collections.clearHistory() }
            }
            .alert("Clear search history?", isPresented: $clearingSearch) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { library.clearSearchHistory() }
            }
    }
}

struct StorageSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var cacheCleared = false
    @State private var clearingDownloads = false
    @State private var pickingFolder = false
    @State private var copying = false
    @State private var folderStatus: String?
    @AppStorage(DownloadFolder.nameKey) private var folder = ""
    var body: some View {
        Form {
            Section("Downloaded songs") {
                NavigationLink("Downloaded songs (\(library.songs.filter { $0.localFile != nil }.count))") {
                    AutoCollectionView(kind: "Downloaded")
                }
                Text("Files → On My iPhone → Play → Downloads").font(.caption).foregroundColor(.secondary)
                Text("Use a song’s menu to remove it and its saved audio.").font(.caption).foregroundColor(.secondary)
                Button("Clear all downloads", role: .destructive) { clearingDownloads = true }
            }
            Section("Download location") {
                Button(folder.isEmpty ? "Choose a Files folder" : "Change folder: \(folder)") { pickingFolder = true }
                if !folder.isEmpty {
                    Button(copying ? "Copying…" : "Copy existing downloads to folder") {
                        copying = true
                        Task {
                            defer { copying = false }
                            do { try await library.copyDownloadsToFiles(); folderStatus = "Downloads copied." }
                            catch { folderStatus = error.localizedDescription }
                        }
                    }.disabled(copying)
                    Button("Save in Play only") {
                        UserDefaults.standard.removeObject(forKey: DownloadFolder.bookmarkKey)
                        folder = ""
                        folderStatus = nil
                    }.disabled(copying)
                    Text("New downloads are also copied to this folder. Play keeps an offline copy on this device.")
                        .font(.caption).foregroundColor(.secondary)
                }
                if let status = folderStatus { Text(status).font(.caption).foregroundColor(.secondary) }
            }
            Section("Cache") {
                Button(cacheCleared ? "Artwork cache cleared" : "Clear artwork cache") { URLCache.shared.removeAllCachedResponses(); cacheCleared = true }
            }
        }.navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                do {
                    let url = try result.get()
                    let bookmark = try DownloadFolder.bookmark(for: url)
                    UserDefaults.standard.set(bookmark, forKey: DownloadFolder.bookmarkKey)
                    folder = url.lastPathComponent
                    folderStatus = nil
                } catch { folderStatus = error.localizedDescription }
            }
            .alert("Clear all downloads?", isPresented: $clearingDownloads) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { library.clearDownloads() }
            } message: {
                Text("Songs stay in your library. Imported audio files are kept.")
            }
    }
}

struct PlayBackup: Codable {
    var formatVersion = 1
    var songs: [Song]
    var collections: CollectionSnapshot
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let backup: PlayBackup
    init(backup: PlayBackup) { self.backup = backup }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 16 * 1024 * 1024 else { throw PlayError.message("Backup is missing or too large.") }
        backup = try JSONDecoder().decode(PlayBackup.self, from: data)
        guard backup.formatVersion == 1 else { throw PlayError.message("Unsupported backup version.") }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: try JSONEncoder().encode(backup)) }
}
struct BackupSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    @State private var exporting = false
    @State private var importing = false
    @State private var status: String?
    var body: some View {
        Form {
            Button("Create backup") { collections.flush(); exporting = true }
            Button("Restore backup") { importing = true }
            Text("Backs up your library, playlists, favorites, history and stats. Audio files stay on this device. Restoring merges with existing data.").font(.caption).foregroundColor(.secondary)
            if let status = status { Text(status).font(.caption) }
        }.navigationTitle("Backup and restore").navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: BackupDocument(backup: PlayBackup(songs: library.songs, collections: collections.state)), contentType: .json, defaultFilename: "Play-backup") { result in
                if case .failure(let error) = result { status = error.localizedDescription }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): Task { await restore(url) }
                case .failure(let error): status = error.localizedDescription
                }
            }
    }
    private func restore(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try await Task.detached(priority: .utility) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 16 * 1024 * 1024 else { throw PlayError.message("Backup is too large.") }
                let decoded = try JSONDecoder().decode(PlayBackup.self, from: Data(contentsOf: url))
                guard decoded.formatVersion == 1 else { throw PlayError.message("Unsupported backup version.") }
                return decoded
            }.value
            library.merge(backup.songs); collections.restore(backup.collections)
            status = library.error ?? collections.error ?? "Backup restored"
        } catch { status = error.localizedDescription }
    }
}

struct AboutSettingsView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    var body: some View {
        Form {
            HStack(spacing: 16) {
                Image("PlayLogo").resizable().scaledToFit().frame(width: 70, height: 70)
                VStack(alignment: .leading) {
                    Text("Play").font(PlayTheme.font(26, weight: .bold))
                    Text("iOS \(version)").foregroundColor(.secondary)
                }
            }
            Link("Source code", destination: URL(string: "https://github.com/highrise14752-a11y/play")!)
            Text("Play is an independent music client based on Play / Velune. GPL-3.0 source; YouTubeKit is MIT licensed. Poppins is distributed under the SIL Open Font License.").font(.caption)
            Link("GPL-3.0 license", destination: URL(string: "https://github.com/highrise14752-a11y/play/blob/main/LICENSE")!)
        }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
