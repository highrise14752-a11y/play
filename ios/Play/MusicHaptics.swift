// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import CoreHaptics
import MediaToolbox
import UIKit
import Darwin

enum HapticMode: String, CaseIterable { case whole = "Whole song", bass = "Bass & beats", vocals = "Vocals emphasis" }

enum HapticBackend: Equatable {
    case coreHaptics, legacyImpact, unavailable
    static func select(coreSupported: Bool, model: String) -> HapticBackend {
        if coreSupported { return .coreHaptics }
        // iPhone 7 / 7 Plus have UIKit feedback, but no Core Haptics support.
        if ["iPhone9,1", "iPhone9,2", "iPhone9,3", "iPhone9,4"].contains(model) { return .legacyImpact }
        return .unavailable
    }
}

@MainActor
private final class LegacyImpactOutput {
    private var generator: UIImpactFeedbackGenerator?
    private var enabled = false
    private var generation = UUID()
    func configure(enabled: Bool, generation: UUID) {
        self.enabled = enabled; self.generation = generation
        if enabled {
            if generator == nil { generator = UIImpactFeedbackGenerator(style: .medium) }
            generator?.prepare()
        } else { generator = nil }
    }
    func emit(strength: Float, generation: UUID, emittedAt: Double) {
        guard enabled, self.generation == generation,
              ProcessInfo.processInfo.systemUptime - emittedAt < 0.2 else { return }
        generator?.impactOccurred(intensity: CGFloat(strength))
        generator?.prepare()
    }
}

// All filter state belongs to one audio tap; analysis never changes the audio samples.
struct HapticEnergy {
    var sampleRate = 44100.0
    var mode = HapticMode.whole
    private var low = 0.0
    private var mid = 0.0
    init(mode: HapticMode = .whole, sampleRate: Double = 44100) { self.mode = mode; self.sampleRate = sampleRate }
    mutating func sample(_ value: Float) -> Double {
        let input = value.isFinite ? Double(value) : 0
        low += min(1, 2 * .pi * 180 / max(1, sampleRate)) * (input - low)
        mid += min(1, 2 * .pi * 3000 / max(1, sampleRate)) * (input - mid)
        let filtered: Double
        switch mode { case .whole: filtered = input; case .bass: filtered = low; case .vocals: filtered = mid - low }
        return filtered * filtered
    }
}

// Core Haptics operations run on this serial queue, never on the audio render thread.
private final class HapticOutput {
    private let backend: HapticBackend
    private let legacy: LegacyImpactOutput?
    let queue = DispatchQueue(label: "Play.haptics", qos: .userInteractive)
    private var engine: CHHapticEngine?
    private var running = false
    private var enabled = false
    private var generation = UUID()
    private var intensity = 0.5

    @MainActor init(backend: HapticBackend) {
        self.backend = backend
        legacy = backend == .legacyImpact ? LegacyImpactOutput() : nil
    }

    @MainActor
    func configure(enabled: Bool, intensity: Double, generation: UUID) {
        legacy?.configure(enabled: enabled, generation: generation)
        queue.async { [self] in
            self.enabled = enabled
            self.intensity = min(1, max(0, intensity))
            self.generation = generation
            if !enabled { engine?.stop(completionHandler: nil); running = false }
        }
    }

    func emit(_ energy: Double, generation: UUID) {
        let emittedAt = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard enabled, self.generation == generation, energy.isFinite, energy > 0.008 else { return }
            let strength = Float(min(1, sqrt(energy) * 2.5) * intensity)
            if backend == .legacyImpact {
                Task { @MainActor [weak legacy] in legacy?.emit(strength: strength, generation: generation, emittedAt: emittedAt) }
                return
            }
            guard backend == .coreHaptics else { return }
            do {
                if engine == nil {
                    let created = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
                    created.playsHapticsOnly = true
                    created.isAutoShutdownEnabled = true
                    created.stoppedHandler = { [weak self] _ in self?.queue.async { self?.running = false } }
                    created.resetHandler = { [weak self] in self?.queue.async { self?.running = false; self?.engine = nil } }
                    engine = created
                }
                guard let engine = engine else { return }
                if !running { try engine.start(); running = true }
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35)
                ], relativeTime: 0)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            } catch { running = false }
        }
    }
}

struct AdaptiveGain {
    private(set) var gain = 1.0

    mutating func update(rms: Double, frames: Int, sampleRate: Double) -> Float {
        guard rms.isFinite, rms > 0.008, sampleRate > 0, frames > 0 else { return Float(gain) }
        let target = min(1.6, max(0.3, 0.14 / rms))
        let seconds = Double(frames) / sampleRate
        let timeConstant = target < gain ? 0.25 : 2.0
        gain += (target - gain) * (1 - exp(-seconds / timeConstant))
        return Float(gain)
    }

    static func limited(_ sample: Float, gain: Float) -> Float {
        guard sample.isFinite else { return 0 }
        return min(0.98, max(-0.98, sample * gain))
    }
}

private final class AudioTapContext {
    let output: HapticOutput
    let generation: UUID
    var format = AudioStreamBasicDescription()
    var analyzer: HapticEnergy
    let haptics: Bool
    let normalization: Bool
    private var gain = AdaptiveGain()
    private var lastEmission = 0.0
    init(output: HapticOutput, generation: UUID, mode: HapticMode, haptics: Bool, normalization: Bool) {
        self.output = output; self.generation = generation; analyzer = HapticEnergy(mode: mode)
        self.haptics = haptics
        self.normalization = normalization
    }
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0, format.mFormatID == kAudioFormatLinearPCM else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let first = buffers.first, let data = first.mData else { return }
        let stride = max(1, Int(first.mNumberChannels))
        analyzer.sampleRate = format.mSampleRate
        var energy = 0.0
        var square = 0.0
        var frameCount: Int
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 {
            let count = min(frames, Int(first.mDataByteSize) / (MemoryLayout<Float>.size * stride))
            guard count > 0 else { return }
            frameCount = count
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count {
                let sample = samples[i * stride]
                if haptics { energy += analyzer.sample(sample) }
                if normalization { square += Double(sample) * Double(sample) }
            }
            if normalization {
                let multiplier = gain.update(rms: sqrt(square / Double(count)), frames: count, sampleRate: format.mSampleRate)
                for buffer in buffers {
                    guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let length = min(frames * max(1, Int(buffer.mNumberChannels)), Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                    for i in 0..<length { samples[i] = AdaptiveGain.limited(samples[i], gain: multiplier) }
                }
            }
        } else if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && format.mBitsPerChannel == 16 {
            let count = min(frames, Int(first.mDataByteSize) / (MemoryLayout<Int16>.size * stride))
            guard count > 0 else { return }
            frameCount = count
            let samples = data.assumingMemoryBound(to: Int16.self)
            for i in 0..<count {
                let sample = Float(samples[i * stride]) / 32768
                if haptics { energy += analyzer.sample(sample) }
                if normalization { square += Double(sample) * Double(sample) }
            }
            if normalization {
                let multiplier = gain.update(rms: sqrt(square / Double(count)), frames: count, sampleRate: format.mSampleRate)
                for buffer in buffers {
                    guard let samples = buffer.mData?.assumingMemoryBound(to: Int16.self) else { continue }
                    let length = min(frames * max(1, Int(buffer.mNumberChannels)), Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size)
                    for i in 0..<length {
                        samples[i] = Int16(AdaptiveGain.limited(Float(samples[i]) / 32768, gain: multiplier) * 32768)
                    }
                }
            }
        } else { return }
        guard haptics else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastEmission >= 0.1 {
            lastEmission = now
            output.emit(sqrt(energy / Double(frameCount)), generation: generation)
        }
    }
}

@MainActor
final class MusicHaptics: ObservableObject {
    let backend: HapticBackend
    var supported: Bool { backend != .unavailable }
    var backendName: String { backend == .legacyImpact ? "Taptic Engine compatibility mode" : "Core Haptics" }
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "haptics.enabled"); refresh() } }
    @Published var intensity: Double { didSet { UserDefaults.standard.set(intensity, forKey: "haptics.intensity"); updateOutput() } }
    @Published var mode: String { didSet { UserDefaults.standard.set(mode, forKey: "haptics.mode"); refresh() } }
    @Published var pauseInLowPower: Bool {
        didSet { UserDefaults.standard.set(pauseInLowPower, forKey: "haptics.pauseInLowPower"); updateOutput() }
    }
    @Published var normalizeAudio: Bool {
        didSet { UserDefaults.standard.set(normalizeAudio, forKey: "player.normalize"); refresh() }
    }
    @Published private(set) var status = "Off"
    private let output: HapticOutput
    private weak var item: AVPlayerItem?
    private var generation = UUID()
    private var attachTask: Task<Void, Never>?
    private var playing = false
    private var visible = true
    private var powerObserver: NSObjectProtocol?

    init() {
        var info = utsname()
        uname(&info)
        let model = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        backend = HapticBackend.select(coreSupported: CHHapticEngine.capabilitiesForHardware().supportsHaptics, model: model)
        output = HapticOutput(backend: backend)
        enabled = UserDefaults.standard.bool(forKey: "haptics.enabled")
        intensity = UserDefaults.standard.object(forKey: "haptics.intensity") as? Double ?? 0.5
        mode = UserDefaults.standard.string(forKey: "haptics.mode") ?? HapticMode.whole.rawValue
        pauseInLowPower = UserDefaults.standard.object(forKey: "haptics.pauseInLowPower") as? Bool ?? true
        normalizeAudio = UserDefaults.standard.bool(forKey: "player.normalize")
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateOutput() }
        }
    }

    deinit { if let observer = powerObserver { NotificationCenter.default.removeObserver(observer) } }

    func attach(to item: AVPlayerItem?) { self.item = item; refresh() }
    func setPlayback(playing: Bool) { self.playing = playing; updateOutput() }
    func setVisible(_ visible: Bool) { self.visible = visible; updateOutput() }
    func testFeedback() {
        guard supported && visible else { return }
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.visible else { return }
            feedback.impactOccurred(intensity: CGFloat(self.intensity))
        }
    }
    private func updateOutput() {
        let lowPower = pauseInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled
        output.configure(enabled: supported && enabled && playing && visible && !lowPower, intensity: intensity, generation: generation)
    }
    private func refresh() {
        attachTask?.cancel()
        generation = UUID()
        updateOutput()
        let hapticsActive = supported && enabled
        let normalize = normalizeAudio
        guard hapticsActive || normalize else { item?.audioMix = nil; status = "Off"; return }
        guard let item = item else { status = "Ready — play a song"; return }
        let currentGeneration = generation
        status = "Preparing audio analysis…"
        attachTask = Task { [weak self, weak item] in
            guard let self = self, let item = item else { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard !Task.isCancelled, generation == currentGeneration, let track = tracks.first else { return }
                let context = AudioTapContext(output: output, generation: currentGeneration, mode: HapticMode(rawValue: mode) ?? .whole,
                                              haptics: hapticsActive, normalization: normalize)
                let reference = Unmanaged.passRetained(context)
                var callbacks = MTAudioProcessingTapCallbacks(version: kMTAudioProcessingTapCallbacksVersion_0,
                    clientInfo: reference.toOpaque(),
                    init: { _, info, storage in storage.pointee = info },
                    finalize: { tap in Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release() },
                    prepare: { tap, _, format in
                        Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().format = format.pointee
                    }, unprepare: { _ in },
                    process: { tap, frames, _, list, framesOut, flagsOut in
                        let result = MTAudioProcessingTapGetSourceAudio(tap, frames, list, flagsOut, nil, framesOut)
                        guard result == noErr else { framesOut.pointee = 0; return }
                        Unmanaged<AudioTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().process(list, frames: framesOut.pointee)
                    })
                var createdTap: MTAudioProcessingTap?
                let result = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &createdTap)
                guard result == noErr, let tap = createdTap else {
                    reference.release(); status = "Audio analysis is unavailable for this track."; return
                }
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.audioTapProcessor = tap
                let mix = AVMutableAudioMix()
                mix.inputParameters = [parameters]
                item.audioMix = mix
                status = hapticsActive ? "\(backendName) • active while Play is onscreen" : "Off"
            } catch { if !Task.isCancelled { status = "Audio analysis unavailable: \(error.localizedDescription)" } }
        }
    }
}
