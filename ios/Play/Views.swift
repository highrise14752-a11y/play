// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var together: TogetherSession
    @EnvironmentObject private var haptics: MusicHaptics
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingPlayer = false

    var body: some View {
        TabView {
            NavigationView { SearchView() }.navigationViewStyle(.stack)
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            NavigationView { LibraryView() }.navigationViewStyle(.stack)
                .tabItem { Label("Library", systemImage: "music.note.list") }
            NavigationView { SettingsView() }.navigationViewStyle(.stack)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let song = player.current {
                HStack {
                    Button { showingPlayer = true } label: {
                        HStack {
                            Artwork(url: song.artwork).frame(width: 44, height: 44).cornerRadius(8)
                            VStack(alignment: .leading) {
                                Text(song.title).font(.subheadline.bold()).lineLimit(1)
                                Text(song.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                    if player.loading { ProgressView() }
                    Button(action: player.toggle) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button(action: player.next) { Image(systemName: "forward.end.fill").frame(width: 40, height: 44) }
                        .accessibilityLabel("Next song")
                }
                .padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showingPlayer) {
            NavigationView { PlayerView() }.navigationViewStyle(.stack)
        }
        .onChange(of: scenePhase) { haptics.setVisible($0 == .active) }
        .onOpenURL { together.join(link: $0.absoluteString, name: "Listener") }
        .alert("Play", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("OK") { library.error = nil }
        } message: { Text(library.error ?? "") }
    }
}

struct Artwork: View {
    let url: URL?
    var body: some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            ZStack { Color.white.opacity(0.07); Image("PlayLogo").resizable().scaledToFit() }
        }.clipped().accessibilityHidden(true)
    }
}

struct SongRow: View {
    let song: Song
    let queue: [Song]
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        HStack(spacing: 12) {
            Button { library.play(song, in: queue) } label: {
                HStack(spacing: 12) {
                    Artwork(url: song.artwork).frame(width: 54, height: 54).cornerRadius(9)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(.body.weight(.medium)).foregroundColor(.primary).lineLimit(2)
                        Text(song.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if library.saved(song).localFile != nil { Image(systemName: "arrow.down.circle.fill").foregroundColor(.cyan) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if library.downloading.contains(song.id) { ProgressView() }
            Menu {
                Button { library.play(song, in: queue) } label: { Label("Play now", systemImage: "play") }
                Button { library.save(song) } label: { Label("Save to library", systemImage: "plus") }
                if !song.isLocal && library.saved(song).localFile == nil {
                    Button { Task { await library.download(song) } } label: { Label("Download", systemImage: "arrow.down") }
                }
                if library.contains(song) {
                    Button(role: .destructive) { library.remove(song) } label: { Label("Remove from library", systemImage: "trash") }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 44) }
            .accessibilityLabel("Song options")
        }.padding(.vertical, 4)
    }
}

struct SearchView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var loading = false
    @State private var error: String?
    @State private var submitted = ""
    @State private var request: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image("PlayLogo").resizable().scaledToFit().frame(width: 54, height: 54)
                    VStack(alignment: .leading) {
                        Text("Your music, your way.").font(.headline)
                        Text("Search for a song or artist to start listening.").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if loading { HStack { Spacer(); ProgressView("Searching…"); Spacer() } }
            if let error = error { Text(error).foregroundColor(.orange) }
            if !submitted.isEmpty && results.isEmpty && !loading && error == nil {
                Text("No songs found. Try another title or artist.").foregroundColor(.secondary)
            }
            ForEach(results) { song in SongRow(song: song, queue: results) }
        }
        .navigationTitle("Play")
        .searchable(text: $query, prompt: "Songs and artists")
        .onSubmit(of: .search) { search() }
        .onDisappear { request?.cancel(); loading = false }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        request?.cancel()
        submitted = text; error = nil; loading = true
        request = Task {
            do {
                let songs = try await library.api.search(text)
                guard !Task.isCancelled else { return }
                results = songs
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var importing = false
    @State private var onlyDownloads = false
    private var displayed: [Song] { library.songs.filter { !onlyDownloads || $0.localFile != nil } }

    var body: some View {
        List {
            Toggle("Downloaded songs only", isOn: $onlyDownloads)
            if displayed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your library starts here").font(.headline)
                    Text("Save songs from search, download them, or import audio from Files.").foregroundColor(.secondary)
                    Button("Import audio") { importing = true }
                }.padding(.vertical)
            }
            ForEach(displayed) { song in SongRow(song: song, queue: displayed) }
        }
        .navigationTitle("Library")
        .toolbar { Button { importing = true } label: { Label("Import audio", systemImage: "plus") } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 16) {
            if let song = player.current {
                if showLyrics {
                    LyricsView().id(song.id).frame(maxHeight: .infinity)
                } else {
                    Artwork(url: song.artwork).aspectRatio(1, contentMode: .fit).cornerRadius(20)
                        .padding(.horizontal, 20).frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(song.title).font(.title2.bold()).lineLimit(2)
                    HStack {
                        Text(song.artist).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button { library.save(song) } label: {
                            Image(systemName: library.contains(song) ? "checkmark.circle.fill" : "plus.circle")
                        }.accessibilityLabel("Save to library")
                    }
                    if let error = player.error { Text(error).font(.caption).foregroundColor(.orange) }
                    Slider(value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }), in: 0...max(1, player.duration)) { editing in
                        if !editing, let value = scrub { player.seek(value); scrub = nil }
                    }
                    .disabled(player.duration <= 0)
                    HStack { Text(clock(scrub ?? player.position)); Spacer(); Text(clock(player.duration)) }
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }.padding(.horizontal, 24)
                HStack(spacing: 48) {
                    Button(action: player.previous) { Image(systemName: "backward.end.fill").font(.title) }.accessibilityLabel("Previous song")
                    Button(action: player.toggle) {
                        if player.loading { ProgressView().frame(width: 50, height: 50) }
                        else { Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64)) }
                    }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button(action: player.next) { Image(systemName: "forward.end.fill").font(.title) }.accessibilityLabel("Next song")
                }
                HStack(spacing: 36) {
                    Button { showLyrics.toggle() } label: { Label("Lyrics", systemImage: "text.quote").foregroundColor(showLyrics ? .cyan : .secondary) }
                    Menu {
                        ForEach(player.queue) { queued in Button(queued.title) { library.play(queued, in: player.queue) } }
                    } label: { Label("Queue", systemImage: "list.bullet") }
                    if !song.isLocal && library.saved(song).localFile == nil {
                        Button { Task { await library.download(song) } } label: { Image(systemName: "arrow.down.circle") }
                            .disabled(library.downloading.contains(song.id)).accessibilityLabel("Download song")
                    }
                }.font(.subheadline).padding(.bottom, 16)
            }
        }
        .navigationTitle("Now playing").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } } }
        .onChange(of: player.current?.id) { _ in scrub = nil }
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var together: TogetherSession
    @AppStorage("lyrics.style") private var style = "Apple Music"
    @AppStorage("lyrics.position") private var position = "Center"
    @AppStorage("lyrics.follow") private var follow = true
    var body: some View {
        Form {
            Section("Playback") {
                NavigationLink { HapticsSettingsView() } label: { Label("Music haptics", systemImage: "waveform") }
                NavigationLink { TogetherView() } label: { Label("Music Together", systemImage: "person.2.wave.2") }
            }
            Section("Lyrics") {
                Picker("Animation style", selection: $style) {
                    ForEach(["Apple Music", "Fade", "None"], id: \.self) { Text($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("lyrics.animation")
                Picker("Text position", selection: $position) {
                    ForEach(["Left", "Center", "Right"], id: \.self) { Text($0) }
                }.pickerStyle(.menu).accessibilityIdentifier("lyrics.position")
                Toggle("Automatic scrolling", isOn: $follow)
                Text("Following requires timed lyrics. Drag to browse; following resumes after three seconds.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Storage") {
                Text("Downloads and imported audio are saved in Play’s Downloads folder. Find them in Files → On My iPhone → Play.")
                Text("Remove saved audio using the song’s options in Library.").font(.caption).foregroundColor(.secondary)
            }
            Section("About") {
                HStack { Image("PlayLogo").resizable().scaledToFit().frame(width: 64, height: 64); Text("Play").font(.title.bold()) }
                Text("iOS 1.0 • An independent music client")
                Link("Source code and GPL-3.0 license", destination: URL(string: "https://github.com/highrise14752-a11y/play")!)
                Text("Based on Play / Velune. Audio extraction uses YouTubeKit (MIT); lyrics are supplied by LRCLIB. Service availability varies by song and region.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.navigationTitle("Settings")
    }
}

struct HapticsSettingsView: View {
    @EnvironmentObject private var haptics: MusicHaptics
    var body: some View {
        Form {
            Toggle("Music haptics", isOn: $haptics.enabled).disabled(!haptics.supported)
            Text(haptics.supported ? haptics.status : "This device does not support Core Haptics.")
                .font(.caption).foregroundColor(.secondary)
            if haptics.supported {
                Picker("Audio focus", selection: $haptics.mode) {
                    ForEach(HapticMode.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                }
                Slider(value: $haptics.intensity, in: 0...1) { Text("Intensity") }
                Text("Intensity: \(Int(haptics.intensity * 100))%")
                Text("Vibrations follow decoded audio, while Play is onscreen. Vocals emphasis is a frequency filter, not vocal isolation. Streaming formats that don’t expose decoded PCM cannot drive haptics.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.navigationTitle("Music haptics")
    }
}

struct TogetherView: View {
    @EnvironmentObject private var together: TogetherSession
    @AppStorage("together.name") private var name = "Listener"
    @State private var link = ""
    @State private var copied = false
    var body: some View {
        Form {
            Section("Music Together") {
                Text(together.status)
                if let error = together.error { Text(error).foregroundColor(.orange) }
                TextField("Your name", text: $name)
                Text("Use the same Wi-Fi network. Each device streams the same song independently; local audio files are not transferred.")
                    .font(.caption).foregroundColor(.secondary)
            }
            if !together.connected {
                Section("Host a session") {
                    Button("Start Music Together") { together.host(name: name) }
                }
                Section("Join a session") {
                    TextField("Paste invitation link", text: $link).textInputAutocapitalization(.never).disableAutocorrection(true)
                    Button("Join session") { together.join(link: link, name: name) }.disabled(link.isEmpty)
                }
            } else {
                if together.isHost {
                    Section("Invite friends") {
                        if let invite = together.invite {
                            Button(copied ? "Invitation copied" : "Copy invitation") { UIPasteboard.general.string = invite; copied = true }
                            Text("Share this invitation privately. It grants access to your room.").font(.caption).foregroundColor(.secondary)
                        }
                        Toggle("Guests can control playback", isOn: $together.allowGuestControls)
                    }
                }
                Section("Participants") {
                    ForEach(together.participants) { person in
                        HStack { Text(person.name); Spacer(); if person.isHost { Text("Host").foregroundColor(.secondary) } }
                    }
                }
                Button("Leave session", role: .destructive) { together.leave(); copied = false }
            }
        }.navigationTitle("Music Together")
    }
}
