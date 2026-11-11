// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import MediaPlayer
import Foundation

enum PlayRepeatMode: Int, CaseIterable { case off = 0, one = 1, all = 2 }

struct SavedQueue: Codable {
    let current: Song
    let songs: [Song]
    let position: Double
    let shuffle: Bool
    let repeatMode: Int
}

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
    @Published private(set) var repeatMode = PlayRepeatMode.off
    @Published private(set) var shuffleEnabled = false
    @Published private(set) var sleepDeadline: Date?
    @Published private(set) var stopAtTrackEnd = false
    var onTrackStarted: ((Song) -> Void)?
    var onListeningTime: ((Double) -> Void)?
    var onPaused: (() -> Void)?
    var onDurationKnown: ((Song) -> Void)?
    let haptics = MusicHaptics()
    var interceptControl: ((String, Double?) -> Bool)?
    var interceptSong: ((Song) -> Bool)?
    var interceptEnqueue: ((Song, Bool) -> Bool)?
    var sharedSessionActive = false
    private let api: MusicAPI
    private let downloadDirectory: URL
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemObserver: NSKeyValueObservation?
    private var volumeObserver: NSKeyValueObservation?
    private var mutedPause = false
    private var notifications: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var loadTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var requestID = UUID()
    private var resumeAfterInterruption = false
    private var resolving = false
    private var pendingPosition = 0.0
    private var pendingAutoplay = true
    private(set) var isLocallySuspended = false
    private var loggedRequest: UUID?
    private var lastPosition = 0.0
    private var sleepTask: Task<Void, Never>?
    private var playedHistory: [Song] = []
    private let queueFile: URL?
    private var deferredItem = false
    private var lastQueueSave = Date.distantPast
    private var failedTracks = Set<String>()
    private var lastSkip = Date.distantPast
    private var skipDirection = 0
    private var skipCount = 0

    init(api: MusicAPI, downloadDirectory: URL? = nil, queueFile: URL? = nil) {
        self.api = api
        self.downloadDirectory = downloadDirectory ?? LibraryStore.downloads
        self.queueFile = queueFile
        if UserDefaults.standard.bool(forKey: "player.keepShuffle") {
            shuffleEnabled = UserDefaults.standard.bool(forKey: "player.savedShuffle")
        }
        if UserDefaults.standard.bool(forKey: "player.persistentQueue"),
           let queueFile = queueFile, let data = try? Data(contentsOf: queueFile),
           let saved = try? JSONDecoder().decode(SavedQueue.self, from: data),
           saved.position.isFinite, saved.position >= 0, saved.songs.contains(where: { $0.id == saved.current.id }) {
            current = saved.current
            queue = saved.songs
            duration = saved.current.duration ?? 0
            position = saved.position
            pendingPosition = position
            shuffleEnabled = saved.shuffle
            repeatMode = PlayRepeatMode(rawValue: saved.repeatMode) ?? .off
            deferredItem = true
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self, !self.deferredItem, !self.resolving else { return }
                let seconds = time.seconds
                let delta = seconds - self.lastPosition
                if self.isPlaying && delta > 0 && delta < 2 { self.onListeningTime?(delta) }
                self.lastPosition = seconds.isFinite ? seconds : 0
                if seconds.isFinite && self.position != max(0, seconds) { self.position = max(0, seconds) }
                let length = self.player.currentItem?.duration.seconds ?? 0
                if length.isFinite && length > 0 && abs(self.duration - length) > 0.01 { self.updateDuration(length) }
                if self.isPlaying && Date().timeIntervalSince(self.lastQueueSave) >= 15 { self.persistQueue() }
            }
        }
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.haptics.setPlayback(playing: player.timeControlStatus == .playing)
                self?.loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self?.updateNowPlaying()
                if let self = self {
                    if self.isPlaying, self.loggedRequest != self.requestID, let song = self.current {
                        self.failedTracks.removeAll()
                        self.loggedRequest = self.requestID; self.onTrackStarted?(song)
                    } else if player.timeControlStatus == .paused {
                        self.onPaused?()
                        if !self.resolving { self.persistQueue() }
                    }
                }
            }
        }
        notifications.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self = self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
                if self.interceptControl?("ended", nil) == true { return }
                if self.stopAtTrackEnd { self.stopAtTrackEnd = false; self.suspendForSystemEvent(); return }
                if self.repeatMode == .one {
                    self.seek(0); if let song = self.current { self.onTrackStarted?(song) }; self.resume(); return
                }
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
                    self.suspendForSystemEvent()
                } else if self.resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self.resumeAfterInterruption = false
                    self.resume()
                }
            }
        })
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                Task { @MainActor in self?.suspendForSystemEvent() }
            } else if reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue {
                Task { @MainActor in
                    guard let self = self, self.current != nil, !self.sharedSessionActive,
                          UserDefaults.standard.bool(forKey: "player.bluetoothStart") else { return }
                    let output = AVAudioSession.sharedInstance().currentRoute.outputs
                    if output.contains(where: { [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0.portType) }) { self.resume() }
                }
            }
        })
        volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let volume = session.outputVolume
            Task { @MainActor in
                guard let self = self, !self.sharedSessionActive,
                      UserDefaults.standard.bool(forKey: "player.pauseAtZero") else { return }
                if volume == 0 && self.isPlaying {
                    self.mutedPause = true
                    self.player.pause()
                } else if volume > 0 && self.mutedPause {
                    self.mutedPause = false
                    self.resume()
                }
            }
        }
        configureRemoteCommands()
    }

    deinit {
        loadTask?.cancel()
        lyricsTask?.cancel()
        sleepTask?.cancel()
        if let token = timeObserver { player.removeTimeObserver(token) }
        notifications.forEach(NotificationCenter.default.removeObserver)
        for (command, token) in remoteTargets { command.removeTarget(token) }
    }

    func play(_ song: Song, queue: [Song], startAt: Double = 0, autoplay: Bool = true, preserveLocalSuspension: Bool = false, rememberPrevious: Bool = true, retrying: Bool = false) {
        if interceptSong?(song) == true { return }
        if rememberPrevious, let old = current, old.id != song.id {
            playedHistory.append(old)
            if playedHistory.count > 100 { playedHistory.removeFirst() }
        }
        if !preserveLocalSuspension { isLocallySuspended = false }
        if !retrying { failedTracks.removeAll() }
        deferredItem = false
        mutedPause = false
        lastSkip = .distantPast
        loadTask?.cancel()
        lyricsTask?.cancel()
        requestID = UUID()
        let request = requestID
        var seen = Set<String>()
        let allowed = queue.filter { (!sharedSessionActive || !$0.isLocal) && seen.insert($0.id).inserted }
        self.queue = allowed.contains(where: { $0.id == song.id }) ? allowed : [song]
        current = song
        lyrics = []
        position = max(0, startAt)
        lastPosition = position
        duration = song.duration ?? 0
        error = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        haptics.attach(to: nil)
        resolving = true; pendingPosition = max(0, startAt); pendingAutoplay = autoplay && !isLocallySuspended
        loading = true
        persistQueue()
        lyricsLoading = true
        updateNowPlaying()
        lyricsTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let lines = try await self.api.lyrics(for: song)
                guard !Task.isCancelled, self.requestID == request else { return }
                self.lyrics = lines
            } catch { /* Lyrics absence never prevents playback. */ }
            guard self.requestID == request, !Task.isCancelled else { return }
            self.lyricsLoading = false
            let defaults = UserDefaults.standard
            guard defaults.bool(forKey: "lyrics.preload"),
                  let index = self.queue.firstIndex(where: { $0.id == song.id }) else { return }
            let count = min(10, max(1, defaults.integer(forKey: "lyrics.preloadCount")))
            let upcoming = Array(self.queue.dropFirst(index + 1).prefix(count))
            for next in upcoming {
                guard !Task.isCancelled else { break }
                _ = try? await self.api.lyrics(for: next)
            }
        }
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let url: URL
                if let file = song.localFile {
                    let local = try DownloadFile.url(filename: file, directory: self.downloadDirectory)
                    if FileManager.default.fileExists(atPath: local.path) { url = local }
                    else if !song.isLocal { url = try await self.api.stream(for: song) }
                    else {
                        throw PlayError.message("The imported file is missing. Import the song again.")
                    }
                } else {
                    guard !song.isLocal else { throw PlayError.message("Import this local audio file again before playing it.") }
                    url = try await self.api.stream(for: song)
                }
                guard !Task.isCancelled, self.requestID == request else { return }
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, mode: .default)
                try audio.setActive(true)
                let asset = AVURLAsset(url: url)
                let measured = try? await asset.load(.duration).seconds
                guard !Task.isCancelled, self.requestID == request else { return }
                if let measured = measured, measured.isFinite, measured > 0 { self.updateDuration(measured) }
                let item = AVPlayerItem(asset: asset)
                self.itemObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                    Task { @MainActor in
                        guard let self = self, self.requestID == request else { return }
                        if item.status == .failed {
                            self.handleFailure(item.error?.localizedDescription ?? "Could not play this audio.")
                        }
                    }
                }
                self.player.replaceCurrentItem(with: item)
                self.haptics.attach(to: item)
                self.player.seek(to: CMTime(seconds: self.pendingPosition, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                    Task { @MainActor in
                        guard let self = self, self.requestID == request, self.resolving else { return }
                        self.resolving = false; self.loading = false
                        if self.pendingAutoplay { self.player.play() } else { self.player.pause() }
                    }
                }
            } catch {
                guard !Task.isCancelled, self.requestID == request else { return }
                self.handleFailure(error.localizedDescription)
            }
        }
    }

    private func handleFailure(_ message: String) {
        loading = false
        resolving = false
        guard let current = current else { error = message; return }
        failedTracks.insert(current.id)
        if pendingAutoplay, !sharedSessionActive, UserDefaults.standard.bool(forKey: "player.skipErrors"),
           let index = queue.firstIndex(where: { $0.id == current.id }),
           let next = queue.dropFirst(index + 1).first(where: { !failedTracks.contains($0.id) }) {
            play(next, queue: queue, retrying: true)
        } else { error = message }
    }

    func persistQueue() {
        lastQueueSave = Date()
        guard let queueFile = queueFile else { return }
        guard UserDefaults.standard.bool(forKey: "player.persistentQueue") else {
            if FileManager.default.fileExists(atPath: queueFile.path) { try? FileManager.default.removeItem(at: queueFile) }
            return
        }
        guard !sharedSessionActive, let current = current else { return }
        let index = queue.firstIndex(where: { $0.id == current.id }) ?? 0
        let start = max(0, index - 500)
        let tracks = Array(queue.dropFirst(start).prefix(2000))
        let saved = SavedQueue(current: current, songs: tracks, position: position, shuffle: shuffleEnabled, repeatMode: repeatMode.rawValue)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: queueFile, options: .atomic) }
    }

    func toggle() { isPlaying ? pause() : resume() }
    private func updateDuration(_ value: Double) {
        guard value.isFinite && value > 0 else { return }
        duration = value
        if var song = current {
            song.duration = value; current = song
            if let index = queue.firstIndex(where: { $0.id == song.id }) { queue[index].duration = value }
            onDurationKnown?(song)
        }
        updateNowPlaying()
    }
    func pause() {
        if interceptControl?("pause", nil) == true { return }
        mutedPause = false; pendingAutoplay = false; player.pause()
    }
    func resume() {
        isLocallySuspended = false
        if interceptControl?("play", nil) == true { return }
        if deferredItem, let song = current { play(song, queue: queue, startAt: position); return }
        pendingAutoplay = true
        do { try AVAudioSession.sharedInstance().setActive(true); player.play() }
        catch { self.error = error.localizedDescription }
    }
    // Device events must always pause this device, even when the host owns controls.
    func suspendForSystemEvent() {
        isLocallySuspended = true
        pendingAutoplay = false
        mutedPause = false
        player.pause()
        haptics.setPlayback(playing: false)
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        if interceptControl?("seek_to", seconds) == true { return }
        position = max(0, min(seconds, duration > 0 ? duration : seconds))
        pendingPosition = position
        if resolving || deferredItem { return }
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }
    func skipTime(_ direction: Int) {
        guard current != nil else { return }
        let now = Date()
        if UserDefaults.standard.bool(forKey: "player.progressiveSeek"),
           direction == skipDirection, now.timeIntervalSince(lastSkip) < 0.8 {
            skipCount = min(skipCount + 1, 6)
        } else { skipCount = 1 }
        lastSkip = now
        skipDirection = direction
        seek(position + Double(direction * skipCount * 10))
    }
    func next() {
        if interceptControl?("skip_next", nil) == true { return }
        if shuffleEnabled, let random = queue.filter({ $0.id != current?.id }).randomElement() { play(random, queue: queue); return }
        if let id = current?.id, queue.last?.id == id, repeatMode == .all, let first = queue.first { play(first, queue: queue); return }
        guard let id = current?.id, let index = queue.firstIndex(where: { $0.id == id }), queue.indices.contains(index + 1) else { pause(); return }
        play(queue[index + 1], queue: queue)
    }
    func previous() {
        if interceptControl?("skip_previous", nil) == true { return }
        if position > 3 { seek(0); return }
        if let previous = playedHistory.popLast() { play(previous, queue: queue, rememberPrevious: false); return }
        guard let id = current?.id, let index = queue.firstIndex(where: { $0.id == id }), index > 0 else { seek(0); return }
        play(queue[index - 1], queue: queue)
    }

    func enqueue(_ song: Song, next: Bool) {
        if interceptEnqueue?(song, next) == true { return }
        guard !queue.contains(where: { $0.id == song.id }) else { return }
        if current == nil { play(song, queue: [song]); return }
        if next, let index = queue.firstIndex(where: { $0.id == current?.id }) { queue.insert(song, at: index + 1) }
        else { queue.append(song) }
        persistQueue()
    }

    func setRepeat(_ mode: PlayRepeatMode) {
        if interceptControl?("set_repeat_mode", Double(mode.rawValue)) == true { return }
        repeatMode = mode
        persistQueue()
    }
    func setShuffle(_ enabled: Bool) {
        if interceptControl?("set_shuffle_enabled", enabled ? 1 : 0) == true { return }
        shuffleEnabled = enabled
        if UserDefaults.standard.bool(forKey: "player.keepShuffle") { UserDefaults.standard.set(enabled, forKey: "player.savedShuffle") }
        persistQueue()
    }
    func applyRoomModes(repeatMode: Int, shuffle: Bool) {
        self.repeatMode = PlayRepeatMode(rawValue: repeatMode) ?? .off; self.shuffleEnabled = shuffle
    }
    func removeQueue(at offsets: IndexSet) {
        guard interceptControl?("edit_queue", nil) != true else { return }
        let active = current?.id
        queue = queue.enumerated().filter { !offsets.contains($0.offset) || $0.element.id == active }.map(\.element)
        persistQueue()
    }
    func moveQueue(from: IndexSet, to: Int) {
        guard interceptControl?("edit_queue", nil) != true else { return }
        var updated = queue
        let valid = from.filter { updated.indices.contains($0) }
        let selected = valid.sorted().map { updated[$0] }
        let insertion = to - valid.filter { $0 < to }.count
        updated = updated.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        updated.insert(contentsOf: selected, at: max(0, min(updated.count, insertion)))
        queue = updated
        persistQueue()
    }
    func setSleepTimer(minutes: Double?) {
        sleepTask?.cancel(); sleepDeadline = nil; stopAtTrackEnd = false
        guard let minutes = minutes, minutes.isFinite, minutes > 0 else { return }
        let seconds = min(minutes, 1440) * 60
        sleepDeadline = Date().addingTimeInterval(seconds)
        sleepTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
            self?.sleepDeadline = nil; self?.suspendForSystemEvent()
        }
    }
    func sleepAfterCurrentSong() { setSleepTimer(minutes: nil); stopAtTrackEnd = true }

    // Apply an authoritative room update without sending it back as a guest control.
    func synchronize(queue: [Song], position: Double, playing: Bool) {
        if deferredItem, let song = current {
            play(song, queue: queue, startAt: position, autoplay: playing, preserveLocalSuspension: true)
            return
        }
        self.queue = queue
        pendingPosition = max(0, position); pendingAutoplay = playing && !isLocallySuspended
        guard !resolving else { return }
        if abs(self.position - position) > 0.8 {
            player.seek(to: CMTime(seconds: max(0, position), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if pendingAutoplay { player.play() } else { player.pause() }
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
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.preferredIntervals = [10]
        add(commands.skipForwardCommand) { player, _ in player.skipTime(1) }
        add(commands.skipBackwardCommand) { player, _ in player.skipTime(-1) }
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
