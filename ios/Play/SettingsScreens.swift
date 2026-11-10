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
    var body: some View {
        Form {
            Section("Theme") {
                Toggle("Pure black background", isOn: $pureBlack)
                HStack {
                    Text("Accent color")
                    Spacer()
                    ForEach([0xFFB3BB, 0xCFB9FF, 0xA1D6B2, 0xE5D88A, 0xA2CBFA], id: \.self) { value in
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
        }.navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct LyricsSettingsView: View {
    @AppStorage("lyrics.style") private var style = "Apple Music"
    @AppStorage("lyrics.position") private var position = "Center"
    @AppStorage("lyrics.follow") private var follow = true
    @AppStorage("lyrics.click") private var click = true
    @AppStorage("lyrics.size") private var size = 28.0
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
            Text("Following requires timed lyrics. Drag to browse; following resumes after three seconds.").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("Lyrics").navigationBarTitleDisplayMode(.inline)
    }
}

struct PlayerSettingsView: View {
    @EnvironmentObject private var player: PlaybackController
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
    private let languages = [("en", "English"), ("hi", "Hindi"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("ja", "Japanese"), ("ko", "Korean"), ("pt", "Portuguese"), ("ar", "Arabic")]
    var body: some View {
        Form {
            Picker("Content language", selection: $language) { ForEach(languages, id: \.0) { Text($0.1).tag($0.0) } }
            Picker("Content region", selection: $region) {
                ForEach(Locale.isoRegionCodes.sorted(), id: \.self) { Text(Locale.current.localizedString(forRegionCode: $0) ?? $0).tag($0) }
            }
            Text("These preferences affect music-service results. They do not translate lyrics.").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("Content").navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var collections: UserCollections
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("privacy.pauseHistory") private var paused = false
    @State private var clearing = false
    var body: some View {
        Form {
            Toggle("Pause listening history", isOn: Binding(get: { paused }, set: {
                collections.flush(); paused = $0
                if !$0, library.player.isPlaying, let song = library.player.current { collections.started(song) }
            }))
            Button("Clear listening history", role: .destructive) { clearing = true }
            Text("Play stores your listening history on this device. Music and lyrics services receive the requests needed to play songs and load lyrics.").font(.caption).foregroundColor(.secondary)
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
            .alert("Clear listening history and stats?", isPresented: $clearing) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) { collections.clearHistory() }
            }
    }
}

struct StorageSettingsView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var cacheCleared = false
    var body: some View {
        Form {
            Section("Downloaded songs") {
                NavigationLink("Downloaded songs (\(library.songs.filter { $0.localFile != nil }.count))") {
                    AutoCollectionView(kind: "Downloaded")
                }
                Text("Files → On My iPhone → Play → Downloads").font(.caption).foregroundColor(.secondary)
                Text("Use a song’s menu to remove it and its saved audio.").font(.caption).foregroundColor(.secondary)
            }
            Section("Cache") {
                Button(cacheCleared ? "Artwork cache cleared" : "Clear artwork cache") { URLCache.shared.removeAllCachedResponses(); cacheCleared = true }
            }
        }.navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
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
    var body: some View {
        Form {
            HStack(spacing: 16) {
                Image("PlayLogo").resizable().scaledToFit().frame(width: 70, height: 70)
                VStack(alignment: .leading) { Text("Play").font(PlayTheme.font(26, weight: .bold)); Text("iOS 1.1").foregroundColor(.secondary) }
            }
            Link("Source code", destination: URL(string: "https://github.com/highrise14752-a11y/play")!)
            Text("Play is an independent music client based on Play / Velune. GPL-3.0 source; YouTubeKit is MIT licensed. Poppins is distributed under the SIL Open Font License.").font(.caption)
            Link("GPL-3.0 license", destination: URL(string: "https://github.com/highrise14752-a11y/play/blob/main/LICENSE")!)
        }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
