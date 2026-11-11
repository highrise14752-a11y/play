// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// Playback ticks update this bar, rather than rebuilding the tab/list container.
struct MiniPlayerView: View {
    @EnvironmentObject private var player: PlaybackController
    @Binding var showingPlayer: Bool
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    var body: some View {
        if let song = player.current {
            HStack {
                Button { showingPlayer = true } label: {
                    HStack {
                        Artwork(url: song.artwork).frame(width: 43, height: 43).clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text(song.title).font(PlayTheme.font(13, weight: .medium)).lineLimit(1)
                            Text(song.artist).font(PlayTheme.font(10)).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                }.buttonStyle(.plain)
                if player.loading { ProgressView() }
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { library.save(song); collections.toggleLike(song) } label: {
                    Image(systemName: collections.liked(song) ? "heart.fill" : "heart").frame(width: 38, height: 44)
                }.accessibilityLabel("Like song")
            }
            .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(PlayTheme.surface))
        }
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
    @EnvironmentObject private var collections: UserCollections
    var body: some View {
        HStack(spacing: 12) {
            Button { library.play(song, in: queue) } label: {
                HStack(spacing: 12) {
                    Artwork(url: song.artwork).frame(width: 54, height: 54).cornerRadius(9)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title).font(PlayTheme.font(13, weight: .medium)).foregroundColor(.primary).lineLimit(2)
                        Text(song.artist).font(PlayTheme.font(11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if library.saved(song).localFile != nil { Image(systemName: "arrow.down.circle.fill").foregroundColor(PlayTheme.accent) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if library.downloading.contains(song.id) { ProgressView() }
            if let duration = library.saved(song).duration { Text(TrackTime.text(duration)).font(PlayTheme.font(10)).foregroundColor(.secondary) }
            Menu {
                Button { library.play(song, in: queue) } label: { Label("Play now", systemImage: "play") }
                Button { library.player.enqueue(library.saved(song), next: true) } label: { Label("Play next", systemImage: "text.insert") }
                Button { library.player.enqueue(library.saved(song), next: false) } label: { Label("Add to queue", systemImage: "text.append") }
                Button { library.save(song); collections.toggleLike(song) } label: { Label(collections.liked(song) ? "Unlike" : "Like", systemImage: "heart") }
                Button { library.save(song) } label: { Label("Save to library", systemImage: "plus") }
                if !collections.state.playlists.isEmpty {
                    Menu("Add to playlist") {
                        ForEach(collections.state.playlists) { playlist in
                            Button(playlist.name) { library.save(song); collections.add(song, to: playlist.id) }
                        }
                    }
                }
                if !song.isLocal && library.saved(song).localFile == nil {
                    Button { Task { await library.download(song) } } label: { Label("Download", systemImage: "arrow.down") }
                }
                if !song.isLocal {
                    Button("Start radio") {
                        Task {
                            do {
                                let suggestions = try await library.api.related(to: song)
                                library.play(song, in: [song] + suggestions)
                            } catch { library.error = error.localizedDescription }
                        }
                    }
                }
                if library.contains(song) {
                    Button(role: .destructive) { library.remove(song) } label: { Label("Remove from library", systemImage: "trash") }
                }
            } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 25, height: 44) }
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
    @EnvironmentObject private var collections: UserCollections
    @State private var importing = false
    @State private var section = "Playlists"
    @State private var query = ""
    @State private var sort = "Date added"
    @State private var descending = false
    @State private var creating = false
    @State private var renaming: LocalPlaylist?
    private var displayed: [Song] {
        let songs = library.songs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query) || ($0.album?.localizedCaseInsensitiveContains(query) == true) }
        let ordered: [Song]
        switch sort {
        case "Title": ordered = songs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case "Artist": ordered = songs.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case "Duration": ordered = songs.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        default: ordered = Array(songs.reversed())
        }
        return descending ? Array(ordered.reversed()) : ordered
    }

    var body: some View {
        let visibleSongs = displayed
        VStack(spacing: 12) {
            CategoryChips(choices: ["Playlists", "Songs", "Albums", "Artists"], selection: $section)
            HStack {
                Menu {
                    ForEach(["Date added", "Title", "Artist", "Duration"], id: \.self) { value in Button(value) { sort = value } }
                } label: { Text(sort).font(PlayTheme.font(12)) }
                Button { descending.toggle() } label: { Image(systemName: descending ? "arrow.up" : "arrow.down") }
                Spacer()
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down").frame(width: 32, height: 35) }.accessibilityLabel("Import audio")
                Button { creating = true } label: { Image(systemName: "plus").frame(width: 32, height: 35) }.accessibilityLabel("New playlist")
            }.foregroundColor(PlayTheme.accent).padding(.horizontal, 20)
            if section == "Songs" {
                TextField("Search your library", text: $query).padding(12).background(RoundedRectangle(cornerRadius: 18).fill(PlayTheme.surface)).padding(.horizontal, 16)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if section == "Playlists" {
                        NavigationLink { AutoCollectionView(kind: "Liked") } label: { collectionRow("Liked", icon: "heart") }
                        NavigationLink { AutoCollectionView(kind: "Downloaded") } label: { collectionRow("Downloaded", icon: "arrow.down.circle") }
                        NavigationLink { AutoCollectionView(kind: "My top 50") } label: { collectionRow("My top 50", icon: "chart.line.uptrend.xyaxis") }
                        ForEach(collections.state.playlists) { playlist in
                            NavigationLink { PlaylistDetailView(id: playlist.id) } label: { collectionRow(playlist.name, icon: "music.note.list", subtitle: "\(playlist.songIDs.count) songs") }
                                .contextMenu {
                                    Button("Rename") { renaming = playlist }
                                    Button("Delete playlist", role: .destructive) { collections.deletePlaylist(playlist.id) }
                                }
                        }
                    } else if section == "Albums" || section == "Artists" {
                        let groups = Dictionary(grouping: visibleSongs) { section == "Albums" ? ($0.album ?? "Unknown album") : $0.artist }
                        ForEach(groups.keys.sorted(), id: \.self) { title in
                            NavigationLink { GroupedCollectionView(title: title, isAlbum: section == "Albums") } label: {
                                collectionRow(title, icon: section == "Albums" ? "square.stack" : "person.crop.circle", subtitle: "\(groups[title]?.count ?? 0) songs")
                            }
                        }
                    } else {
                        ForEach(visibleSongs) { song in SongRow(song: song, queue: visibleSongs) }
                    }
                    if library.songs.isEmpty && section != "Playlists" {
                        EmptyMusicState(title: "Your library starts here", message: "Save a song, or import audio from Files.", icon: "music.note")
                        Button("Import audio") { importing = true }.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $creating) { NameEntryView(title: "New playlist", submit: collections.createPlaylist) }
        .sheet(item: $renaming) { playlist in NameEntryView(title: "Rename playlist", submit: { collections.renamePlaylist(playlist.id, name: $0) }, name: playlist.name) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await library.importFiles(urls) }
            case .failure(let error): library.error = error.localizedDescription
            }
        }
    }
    private func collectionRow(_ title: String, icon: String, subtitle: String? = nil) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.system(size: 23)).foregroundColor(PlayTheme.accent).frame(width: 48, height: 48).background(RoundedRectangle(cornerRadius: 7).fill(PlayTheme.surface))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PlayTheme.font(14, weight: .medium)).foregroundColor(.white)
                if let subtitle = subtitle { Text(subtitle).font(PlayTheme.font(11)).foregroundColor(.secondary) }
            }
            Spacer()
        }.padding(.vertical, 4)
    }
}

struct PlaylistDetailView: View {
    let id: String
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var collections: UserCollections
    private var playlist: LocalPlaylist? { collections.state.playlists.first { $0.id == id } }
    var body: some View {
        SongCollectionView(title: playlist?.name ?? "Playlist", songs: (playlist?.songIDs ?? []).compactMap { id in library.songs.first { $0.id == id } }, playlistID: id)
            .toolbar { EditButton() }
    }
}

struct PlayerView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: PlaybackController
    @EnvironmentObject private var collections: UserCollections
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var scrub: Double?
    @State private var queueVisible = false
    @State private var timerVisible = false
    @State private var shareVisible = false

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
                    Text(song.title).font(PlayTheme.font(24, weight: .bold)).lineLimit(2)
                    HStack {
                        Text(song.artist).font(PlayTheme.font(13)).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button { shareVisible = true } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share song")
                        Button { library.save(song); collections.toggleLike(song) } label: {
                            Image(systemName: collections.liked(song) ? "heart.fill" : "heart")
                        }.accessibilityLabel("Like song")
                    }
                    if let error = player.error { Text(error).font(.caption).foregroundColor(.orange) }
                    Slider(value: Binding(get: { scrub ?? player.position }, set: { scrub = $0 }), in: 0...max(1, player.duration)) { editing in
                        if !editing, let value = scrub { player.seek(value); scrub = nil }
                    }
                    .disabled(player.duration <= 0)
                    HStack { Text(TrackTime.text(scrub ?? player.position, elapsed: true)); Spacer(); Text(TrackTime.text(player.duration > 0 ? player.duration : nil)) }
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }.padding(.horizontal, 24)
                HStack(spacing: 22) {
                    Button { player.setShuffle(!player.shuffleEnabled) } label: { Image(systemName: "shuffle").foregroundColor(player.shuffleEnabled ? PlayTheme.accent : .gray) }.accessibilityLabel("Shuffle")
                    Button(action: player.previous) { Image(systemName: "backward.end.fill").font(.title2).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08))) }.accessibilityLabel("Previous song")
                    Button(action: player.toggle) {
                        if player.loading { ProgressView().frame(width: 50, height: 50) }
                        else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 27)).foregroundColor(.black).frame(width: 67, height: 67).background(Circle().fill(.white)) }
                    }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    Button(action: player.next) { Image(systemName: "forward.end.fill").font(.title2).frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08))) }.accessibilityLabel("Next song")
                    Button { player.setRepeat(PlayRepeatMode(rawValue: (player.repeatMode.rawValue + 1) % 3) ?? .off) } label: {
                        Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").foregroundColor(player.repeatMode == .off ? .gray : PlayTheme.accent)
                    }.accessibilityLabel("Repeat")
                }
                HStack(spacing: 28) {
                    Button { queueVisible = true } label: { Label("Queue", systemImage: "list.bullet") }
                    Button { timerVisible = true } label: { Image(systemName: player.sleepDeadline == nil && !player.stopAtTrackEnd ? "moon" : "moon.fill") }.accessibilityLabel("Sleep timer")
                    Button { showLyrics.toggle() } label: { Label("Lyrics", systemImage: "text.quote").foregroundColor(showLyrics ? PlayTheme.accent : .secondary) }
                    if !song.isLocal && library.saved(song).localFile == nil {
                        Button { Task { await library.download(song) } } label: { Image(systemName: "arrow.down.circle") }
                            .disabled(library.downloading.contains(song.id)).accessibilityLabel("Download song")
                    }
                }.font(PlayTheme.font(11)).padding(.bottom, 16)
            }
        }
        .background(LinearGradient(colors: [PlayTheme.accent.opacity(0.17), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationTitle("Now Playing").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("Close player") } }
        .sheet(isPresented: $queueVisible) { NavigationView { QueueView().toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { queueVisible = false } } } }.navigationViewStyle(.stack) }
        .sheet(isPresented: $timerVisible) { NavigationView { SleepTimerView().toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { timerVisible = false } } } }.navigationViewStyle(.stack) }
        .sheet(isPresented: $shareVisible) { ShareView(items: shareItems) }
        .onChange(of: player.current?.id) { _ in scrub = nil }
    }

    private var shareItems: [Any] {
        guard let song = player.current else { return [] }
        if song.isLocal, let filename = song.localFile, let file = try? DownloadFile.url(filename: filename, directory: LibraryStore.downloads) { return [file] }
        var url = URLComponents(string: "https://music.youtube.com/watch")!
        url.queryItems = [URLQueryItem(name: "v", value: song.id)]
        return url.url.map { [$0] } ?? []
    }
}

struct ShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = controller.view
        controller.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        controller.popoverPresentationController?.permittedArrowDirections = []
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct HapticsSettingsView: View {
    @EnvironmentObject private var haptics: MusicHaptics
    var body: some View {
        Form {
            Toggle("Music haptics", isOn: $haptics.enabled).disabled(!haptics.supported)
            Text(haptics.supported ? haptics.status : "Haptic feedback isn’t supported on this device.")
                .font(.caption).foregroundColor(.secondary)
            if haptics.supported {
                Button("Test vibration") { haptics.testFeedback() }
                Text(haptics.backendName).font(.caption).foregroundColor(.secondary)
                if haptics.backend == .legacyImpact {
                    Text("iPhone 7 compatibility mode uses standard Taptic Engine impacts. Feedback is less detailed than on newer iPhones.")
                        .font(.caption).foregroundColor(.secondary)
                }
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
