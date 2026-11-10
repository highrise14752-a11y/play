// SPDX-License-Identifier: GPL-3.0-only
// Wire protocol adapted from Play/Velune's GPL-3.0 TogetherMessages and TogetherModels.
import Foundation
import Network
import CryptoKit
import Darwin

struct TogetherTrack: Codable {
    var id: String
    var title: String
    var artists: [String]
    var durationSec: Int
    var thumbnailUrl: String?
    init(_ song: Song) {
        id = song.id; title = song.title; artists = [song.artist]
        durationSec = Int(song.duration ?? -1); thumbnailUrl = song.artwork?.absoluteString
    }
    var song: Song { Song(id: id, title: title, artist: artists.joined(separator: ", "), artwork: thumbnailUrl.flatMap(URL.init(string:)), duration: durationSec > 0 ? Double(durationSec) : nil) }
}
struct TogetherParticipant: Codable, Identifiable {
    var id: String
    var name: String
    var isHost = false
    var isPending = false
    var isConnected = true
}
struct TogetherSettings: Codable {
    var allowGuestsToAddTracks = true
    var allowGuestsToControlPlayback = false
    var requireHostApprovalToJoin = false
}
struct TogetherRoom: Codable {
    var sessionId: String
    var hostId: String
    var participants: [TogetherParticipant]
    var settings: TogetherSettings
    var queue: [TogetherTrack]
    var queueHash: String
    var currentIndex: Int
    var isPlaying: Bool
    var positionMs: Int
    var repeatMode = 0
    var shuffleEnabled = false
    var sentAtElapsedRealtimeMs: Int
}
struct TogetherInvite: Equatable {
    var host: String
    var port: UInt16
    var sessionID: String
    var key: String
    var link: String {
        var url = URLComponents()
        url.scheme = "play"; url.host = "together"
        url.queryItems = [URLQueryItem(name: "host", value: host), URLQueryItem(name: "port", value: String(port)), URLQueryItem(name: "sid", value: sessionID), URLQueryItem(name: "key", value: key)]
        return url.string ?? ""
    }
    static func parse(_ raw: String) -> TogetherInvite? {
        guard let url = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["play", "velune", "ws", "wss"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let items = url.queryItems ?? []
        func item(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let deep = url.scheme == "play" || url.scheme == "velune"
        guard !deep || url.host == "together", let host = deep ? item("host") : url.host,
              !host.isEmpty, !host.contains("/"), let port = UInt16(deep ? item("port") ?? "" : String(url.port ?? 80)), port > 0,
              let session = item("sid"), !session.isEmpty, let key = item("key"), !key.isEmpty else { return nil }
        // TLS invitations must not silently downgrade to a plaintext connection.
        guard url.scheme != "wss" else { return nil }
        return TogetherInvite(host: host, port: port, sessionID: session, key: key)
    }
}

@MainActor
final class TogetherSession: ObservableObject {
    @Published private(set) var status = "Not connected"
    @Published private(set) var isHost = false
    @Published private(set) var connected = false
    @Published private(set) var invite: String?
    @Published private(set) var participants: [TogetherParticipant] = []
    @Published var allowGuestControls = false
    @Published var error: String?
    private let player: PlaybackController
    private var listener: NWListener?
    private var peers: [UUID: NWConnection] = [:]
    private var identities: [UUID: TogetherParticipant] = [:]
    private var timer: Timer?
    private var sessionID = ""
    private var key = ""
    private var participantID = UUID().uuidString
    private var displayName = "Listener"
    private var pendingPing: Int?
    private var clockOffset: Double?
    private var applying = false
    private var guestControlsAllowed = false
    private var guestAddsAllowed = true

    init(player: PlaybackController) {
        self.player = player
        player.interceptControl = { [weak self] action, value in self?.requestControl(action, value: value) ?? false }
        player.interceptSong = { [weak self] song in self?.requestSong(song) ?? false }
    }

    func host(name: String, addressOverride: String? = nil) {
        leave()
        guard player.current?.isLocal != true else { error = "Choose an online song before hosting. Local files are not transferred."; return }
        guard let address = addressOverride ?? Self.wifiAddress() else { error = "Connect to Wi-Fi before hosting a session."; return }
        isHost = true; displayName = String(name.prefix(64)); error = nil
        sessionID = UUID().uuidString; key = UUID().uuidString + UUID().uuidString
        participantID = UUID().uuidString
        participants = [TogetherParticipant(id: participantID, name: displayName, isHost: true)]
        do {
            let listener = try NWListener(using: Self.parameters(), on: .any)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                Task { @MainActor in
                    guard let self = self else { return }
                    switch state {
                    case .ready:
                        guard let port = listener?.port?.rawValue else { return }
                        self.invite = TogetherInvite(host: address, port: port, sessionID: self.sessionID, key: self.key).link
                        self.connected = true; self.player.sharedSessionActive = true; self.status = "Hosting on Wi-Fi"
                        self.startTimer()
                    case .failed(let failure): self.error = failure.localizedDescription; self.leave()
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
            listener.start(queue: .main)
            status = "Starting session…"
        } catch { self.error = error.localizedDescription; leave() }
    }

    func join(link: String, name: String) {
        guard let invitation = TogetherInvite.parse(link) else { error = "Paste a valid Play local-session invitation. Online room codes are not supported yet."; return }
        leave()
        displayName = String(name.prefix(64)); sessionID = invitation.sessionID; key = invitation.key
        error = nil; status = "Connecting…"
        var endpoint = URLComponents()
        endpoint.scheme = "ws"; endpoint.host = invitation.host; endpoint.port = Int(invitation.port); endpoint.path = "/together"
        guard let url = endpoint.url else { error = "Invalid invitation address."; return }
        let connection = NWConnection(to: .url(url), using: Self.parameters())
        let id = UUID(); peers[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self = self, let connection = connection, self.peers[id] != nil else { return }
                switch state {
                case .ready:
                    self.send(["type": "client_hello", "protocolVersion": 1, "sessionId": self.sessionID, "sessionKey": self.key,
                               "clientId": self.participantID, "displayName": self.displayName], to: connection)
                    self.receive(connection, id: id)
                case .failed(let failure): self.error = failure.localizedDescription; self.leave()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.peers[id] != nil, !self.connected else { return }
            self.error = "The host did not respond. Check Wi-Fi and the invitation."; self.leave()
        }
    }

    func leave() {
        timer?.invalidate(); timer = nil
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        let active = peers.values
        peers = [:]; identities = [:]
        for connection in active { connection.stateUpdateHandler = nil; connection.cancel() }
        let wasGuest = connected && !isHost
        connected = false; isHost = false; invite = nil; participants = []; clockOffset = nil
        guestControlsAllowed = false; guestAddsAllowed = true
        player.sharedSessionActive = false
        if wasGuest { applying = true; player.pause(); applying = false }
        status = "Not connected"
    }

    private static func parameters() -> NWParameters {
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        parameters.includePeerToPeer = true
        return parameters
    }
    private func accept(_ connection: NWConnection) {
        guard peers.count < 12 else { connection.cancel(); return }
        let id = UUID(); peers[id] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            Task { @MainActor in
                guard let self = self, let connection = connection else { return }
                switch state {
                case .ready: self.receive(connection, id: id)
                case .failed, .cancelled: self.peers[id] = nil; self.identities[id] = nil; self.rebuildParticipants()
                default: break
                }
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak connection] in
            guard let self = self, self.peers[id] != nil, self.identities[id] == nil else { return }
            connection?.cancel()
        }
    }
    private func receive(_ connection: NWConnection, id: UUID) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, failure in
            Task { @MainActor in
                guard let self = self, let connection = connection, self.peers[id] != nil else { return }
                if failure != nil { if !self.isHost { self.error = "Session disconnected"; self.leave() }; connection.cancel(); return }
                if let data = data, data.count <= 262144,
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.handle(object, data: data, connection: connection, id: id)
                }
                if self.peers[id] != nil { self.receive(connection, id: id) }
            }
        }
    }
    private func send(_ object: [String: Any], to connection: NWConnection) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        send(data, to: connection)
    }
    private func send(_ data: Data, to connection: NWConnection) {
        let context = NWConnection.ContentContext(identifier: "Play.Together", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
    }
    private func handle(_ message: [String: Any], data: Data, connection: NWConnection, id: UUID) {
        let type = message["type"] as? String ?? ""
        if isHost && type == "client_hello" {
            guard message["sessionId"] as? String == sessionID, message["sessionKey"] as? String == key,
                  message["protocolVersion"] as? Int == 1, let client = message["clientId"] as? String, !client.isEmpty else { connection.cancel(); return }
            let guest = TogetherParticipant(id: client, name: String((message["displayName"] as? String ?? "Listener").prefix(64)))
            identities[id] = guest
            send(["type": "server_welcome", "protocolVersion": 1, "sessionId": sessionID, "participantId": client, "role": "GUEST", "isPending": false,
                  "settings": ["allowGuestsToAddTracks": true, "allowGuestsToControlPlayback": allowGuestControls, "requireHostApprovalToJoin": false]], to: connection)
            rebuildParticipants(); broadcast(); return
        }
        if isHost && identities[id] == nil { connection.cancel(); return }
        if type == "room_state", !isHost {
            guard let state = message["state"], let bytes = try? JSONSerialization.data(withJSONObject: state),
                  let room = try? JSONDecoder().decode(TogetherRoom.self, from: bytes), room.sessionId == sessionID else { return }
            participants = room.participants
            guestControlsAllowed = room.settings.allowGuestsToControlPlayback
            guestAddsAllowed = room.settings.allowGuestsToAddTracks
            apply(room); return
        }
        guard message["sessionId"] as? String == sessionID else { return }
        if type == "server_welcome" && !isHost {
            participantID = message["participantId"] as? String ?? participantID
            connected = true; player.sharedSessionActive = true
            status = (message["isPending"] as? Bool == true) ? "Waiting for host approval" : "Listening together"
            startTimer()
        } else if type == "heartbeat_ping" && isHost {
            send(["type": "heartbeat_pong", "sessionId": sessionID, "pingId": message["pingId"] ?? 0,
                  "clientElapsedRealtimeMs": message["clientElapsedRealtimeMs"] ?? 0, "serverElapsedRealtimeMs": Self.now()], to: connection)
        } else if type == "heartbeat_pong" && !isHost,
                  let ping = message["pingId"] as? Int, ping == pendingPing,
                  let server = message["serverElapsedRealtimeMs"] as? Int {
            clockOffset = Double(server) - Double(ping + Self.now()) / 2
        } else if type == "control_request" && isHost && allowGuestControls,
                  let action = message["action"] as? [String: Any] {
            control(action); broadcast()
        } else if type == "add_track_request" && isHost,
                  let track = message["track"], let bytes = try? JSONSerialization.data(withJSONObject: track),
                  let song = try? JSONDecoder().decode(TogetherTrack.self, from: bytes), !song.song.isLocal {
            player.enqueue(song.song, next: message["mode"] as? String == "PLAY_NEXT"); broadcast()
        } else if type == "server_error" {
            error = message["message"] as? String ?? "The host rejected that request."
        } else if type == "kick" || type == "ban" {
            error = message["reason"] as? String ?? "The host ended your session."; leave()
        } else if type == "client_leave" && isHost { connection.cancel() }
    }
    private func rebuildParticipants() {
        guard isHost else { return }
        participants = [TogetherParticipant(id: participantID, name: displayName, isHost: true)] + identities.values.sorted { $0.name < $1.name }
    }
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.isHost { self.broadcast() }
                else if let connection = self.peers.values.first {
                    let now = Self.now(); self.pendingPing = now
                    self.send(["type": "heartbeat_ping", "sessionId": self.sessionID, "pingId": now, "clientElapsedRealtimeMs": now], to: connection)
                }
            }
        }
    }
    private func broadcast() {
        let songs = player.queue.filter { !$0.isLocal }
        let hash = SHA256.hash(data: Data(songs.map(\.id).joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
        let room = TogetherRoom(sessionId: sessionID, hostId: participantID, participants: participants,
                                settings: TogetherSettings(allowGuestsToControlPlayback: allowGuestControls), queue: songs.map(TogetherTrack.init), queueHash: hash,
                                currentIndex: songs.firstIndex { $0.id == player.current?.id } ?? 0,
                                isPlaying: player.isPlaying, positionMs: Int(player.position * 1000), sentAtElapsedRealtimeMs: Self.now())
        struct Envelope: Encodable { let type = "room_state"; let state: TogetherRoom }
        guard let data = try? JSONEncoder().encode(Envelope(state: room)) else { return }
        for (id, connection) in peers where identities[id] != nil { send(data, to: connection) }
    }
    private func apply(_ room: TogetherRoom) {
        guard room.queue.indices.contains(room.currentIndex) else {
            applying = true; player.pause(); applying = false; return
        }
        let songs = room.queue.map(\.song)
        let song = songs[room.currentIndex]
        guard !song.isLocal else { return }
        let elapsed = room.isPlaying && clockOffset != nil ? min(2500, max(0, Double(Self.now()) + (clockOffset ?? 0) - Double(room.sentAtElapsedRealtimeMs))) : 0
        let target = Double(room.positionMs) / 1000 + elapsed / 1000
        applying = true
        defer { applying = false }
        status = "Listening together"
        if player.current?.id != song.id {
            player.play(song, queue: songs, startAt: target, autoplay: room.isPlaying)
        } else {
            player.synchronize(queue: songs, position: target, playing: room.isPlaying)
        }
    }
    private func requestControl(_ action: String, value: Double?) -> Bool {
        guard connected && !isHost && !applying else { return false }
        if action == "ended" { return true }
        guard guestControlsAllowed else { player.error = "The host controls playback in this session."; return true }
        guard let connection = peers.values.first else { return true }
        var control: [String: Any] = ["type": action]
        if let value = value { control["positionMs"] = Int(value * 1000) }
        send(["type": "control_request", "sessionId": sessionID, "participantId": participantID, "action": control], to: connection)
        return true
    }
    private func requestSong(_ song: Song) -> Bool {
        guard connected && !applying else { return false }
        if song.isLocal { player.error = "Local files cannot be shared in Music Together."; return true }
        guard !isHost, let connection = peers.values.first else { return false }
        guard guestAddsAllowed else { player.error = "The host has disabled guest queue requests."; return true }
        guard let data = try? JSONEncoder().encode(TogetherTrack(song)), let track = try? JSONSerialization.jsonObject(with: data) else { return true }
        send(["type": "add_track_request", "sessionId": sessionID, "participantId": participantID, "track": track, "mode": "ADD_TO_QUEUE"], to: connection)
        status = "Track requested from host"
        return true
    }
    private func control(_ action: [String: Any]) {
        switch action["type"] as? String {
        case "play": player.resume()
        case "pause": player.pause()
        case "seek_to": player.seek(Double(action["positionMs"] as? Int ?? 0) / 1000)
        case "skip_next": player.next()
        case "skip_previous": player.previous()
        default: break
        }
    }
    // Peer clock offsets map this timestamp to Android's elapsed-time clock.
    // Do not transmit device boot time to other participants.
    private static func now() -> Int { Int(Date().timeIntervalSince1970 * 1000) }
    private static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var current = list
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == "en0", let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
        }
        return nil
    }
}
