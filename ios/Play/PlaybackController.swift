// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import MediaPlayer
import Foundation

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var current: Song?
    @Published private(set) var queue: [Song] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var loading = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var lyrics: [LyricLine] = []
    @Published private(set) var lyricsLoading = false
    @Published var error: String?
    let haptics = MusicHaptics()
    var interceptControl: ((String, Double?) -> Bool)?
    var interceptSong: ((Song) -> Bool)?
    var sharedSessionActive = false
    private let api: MusicAPI
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var loadTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var requestID = UUID()
    private var resumeAfterInterruption = false
    private var resolving = false
    private var pendingPosition = 0.0
    private var pendingAutoplay = true

    init(api: MusicAPI) {
        self.api = api
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let seconds = time.seconds
                if seconds.isFinite && self.position != max(0, seconds) { self.position = max(0, seconds) }
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && self.duration != max(0, length) { self.duration = max(0, length) }
            }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.haptics.setPlayback(playing: player.timeControlStatus == .playing)
                self?.loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self?.updateNowPlaying()
            }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                if self.interceptControl?("ended", nil) == true { return }
                self.next()
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in
                guard let self = self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.resumeAfterInterruption = self.isPlaying
                    self.player.pause()
                } else if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.resume()
                }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.pause() }
            }
        })
        configureRemoteCommands()
    }

    deinit {
        loadTask?.cancel()
        lyricsTask?.cancel()
        if let token = timeObserver { player.removeTimeObserver(token) }
        notifications.forEach(NotificationCenter.default.removeObserver)
        for (command, token) in remoteTargets { command.removeTarget(token) }
    }

    func play(_ song: Song, queue: [Song], startAt: Double = 0, autoplay: Bool = true) {
        if interceptSong?(song) == true { return }
        loadTask?.cancel()
        lyricsTask?.cancel()
        requestID = UUID()
        let request = requestID
        let allowed = sharedSessionActive ? queue.filter { !$0.isLocal } : queue
        self.queue = allowed.contains(where: { $0.id == song.id }) ? allowed : [song]
        current = song
        lyrics = []
        position = 0
        duration = song.duration ?? 0
        error = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        haptics.attach(to: nil)
        resolving = true; pendingPosition = max(0, startAt); pendingAutoplay = autoplay
        loading = true
        lyricsLoading = true
        updateNowPlaying()
        lyricsTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let lines = try await self.api.lyrics(for: song)
                guard !Task.isCancelled, self.requestID == request else { return }
                self.lyrics = lines
            } catch { /* Lyrics absence never prevents playback. */ }
            if self.requestID == request { self.lyricsLoading = false }
        }
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let url: URL
                if let file = song.localFile {
                    let local = LibraryStore.downloads.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: local.path) else {
                        throw PlayError.message("The downloaded file is missing. Import or download the song again.")
                    }
                    url = local
                } else { url = try await self.api.stream(for: song) }
                guard !Task.isCancelled, self.requestID == request else { return }
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, mode: .default)
                try audio.setActive(true)
                let item = AVPlayerItem(url: url)
                self.itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self = self, self.requestID == request else { return }
                        if item.status == .failed {
                            self.error = item.error?.localizedDescription ?? "Could not play this audio."
                            self.loading = false
                        }
                    }
                }
                self.player.replaceCurrentItem(with: item)
                self.haptics.attach(to: item)
                self.player.seek(to: CMTime(seconds: self.pendingPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self, self.requestID == request else { return }
                        self.resolving = false; self.loading = false
                        if self.pendingAutoplay { self.player.play() } else { self.player.pause() }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.requestID == request else { return }
                self.error = error.localizedDescription
                self.loading = false
                self.resolving = false
            }
        }
    }

    func toggle() { isPlaying ? pause() : resume() }
    func pause() {
        if interceptControl?("pause", nil) == true { return }
        pendingAutoplay = false; player.pause()
    }
    func resume() {
        if interceptControl?("play", nil) == true { return }
        pendingAutoplay = true
        do { try AVAudioSession.sharedInstance().setActive(true); player.play() }
        catch { self.error = error.localizedDescription }
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if interceptControl?("seek_to", seconds) == true { return }
        position = max(0, min(seconds, duration > 0 ? duration : seconds))
        pendingPosition = position
        if resolving { return }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }
    func next() {
        if interceptControl?("skip_next", nil) == true { return }
        guard let id = current?.id, let index = queue.firstIndex(where: { $0.id == id }), queue.indices.contains(index + 1) else { pause(); return }
        play(queue[index + 1], queue: queue)
    }
    func previous() {
        if interceptControl?("skip_previous", nil) == true { return }
        if position > 3 { seek(0); return }
        guard let id = current?.id, let index = queue.firstIndex(where: { $0.id == id }), index > 0 else { seek(0); return }
        play(queue[index - 1], queue: queue)
    }

    func enqueue(_ song: Song, next: Bool) {
        guard !queue.contains(where: { $0.id == song.id }) else { return }
        if current == nil { play(song, queue: [song]); return }
        if next, let index = queue.firstIndex(where: { $0.id == current?.id }) { queue.insert(song, at: index + 1) }
        else { queue.append(song) }
    }

    // Apply an authoritative room update without sending it back as a guest control.
    func synchronize(queue: [Song], position: Double, playing: Bool) {
        self.queue = queue
        pendingPosition = max(0, position); pendingAutoplay = playing
        guard !resolving else { return }
        if abs(self.position - position) > 0.8 {
            player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if playing { player.play() } else { player.pause() }
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ action: @escaping (PlaybackController, MPRemoteCommandEvent) -> Void) {
            let token = command.addTarget { [weak self] event in
                Task { @MainActor in if let self = self { action(self, event) } }
                return .success
            }
            remoteTargets.append((command, token))
        }
        add(commands.playCommand) { player, _ in player.resume() }
        add(commands.pauseCommand) { player, _ in player.pause() }
        add(commands.togglePlayPauseCommand) { player, _ in player.toggle() }
        add(commands.nextTrackCommand) { player, _ in player.next() }
        add(commands.previousTrackCommand) { player, _ in player.previous() }
        add(commands.changePlaybackPositionCommand) { player, event in
            if let change = event as? MPChangePlaybackPositionCommandEvent { player.seek(change.positionTime) }
        }
    }

    private func updateNowPlaying() {
        guard let song = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.title, MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
