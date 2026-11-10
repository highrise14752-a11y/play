// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import CoreHaptics
import MediaToolbox
import UIKit

enum HapticMode: String, CaseIterable { case whole = "Whole song", bass = "Bass & beats", vocals = "Vocals emphasis" }

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
    let queue = DispatchQueue(label: "Play.haptics", qos: .userInteractive)
    private var engine: CHHapticEngine?
    private var running = false
    private var enabled = false
    private var generation = UUID()
    private var intensity = 0.5

    func configure(enabled: Bool, intensity: Double, generation: UUID) {
        queue.async { [self] in
            self.enabled = enabled
            self.intensity = min(1, max(0, intensity))
            self.generation = generation
            if !enabled { engine?.stop(completionHandler: nil); running = false }
        }
    }

    func emit(_ energy: Double, generation: UUID) {
        queue.async { [self] in
            guard enabled, self.generation == generation, energy.isFinite, energy > 0.008 else { return }
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
                let strength = Float(min(1, sqrt(energy) * 2.5) * intensity)
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

private final class AudioTapContext {
    let output: HapticOutput
    let generation: UUID
    var format = AudioStreamBasicDescription()
    var analyzer: HapticEnergy
    private var lastEmission = 0.0
    init(output: HapticOutput, generation: UUID, mode: HapticMode) {
        self.output = output; self.generation = generation; analyzer = HapticEnergy(mode: mode)
    }
    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0, format.mFormatID == kAudioFormatLinearPCM else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let first = buffers.first, let data = first.mData else { return }
        let stride = max(1, Int(first.mNumberChannels))
        analyzer.sampleRate = format.mSampleRate
        var energy = 0.0
        if format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32 {
            let count = min(frames, Int(first.mDataByteSize) / (MemoryLayout<Float>.size * stride))
            guard count > 0 else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            for i in 0..<count { energy += analyzer.sample(samples[i * stride]) }
            energy = sqrt(energy / Double(count))
        } else if format.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0 && format.mBitsPerChannel == 16 {
            let count = min(frames, Int(first.mDataByteSize) / (MemoryLayout<Int16>.size * stride))
            guard count > 0 else { return }
            let samples = data.assumingMemoryBound(to: Int16.self)
            for i in 0..<count { energy += analyzer.sample(Float(samples[i * stride]) / 32768) }
            energy = sqrt(energy / Double(count))
        } else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastEmission >= 0.1 {
            lastEmission = now
            output.emit(energy, generation: generation)
        }
    }
}

@MainActor
final class MusicHaptics: ObservableObject {
    let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "haptics.enabled"); refresh() } }
    @Published var intensity: Double { didSet { UserDefaults.standard.set(intensity, forKey: "haptics.intensity"); updateOutput() } }
    @Published var mode: String { didSet { UserDefaults.standard.set(mode, forKey: "haptics.mode"); refresh() } }
    @Published private(set) var status = "Off"
    private let output = HapticOutput()
    private weak var item: AVPlayerItem?
    private var generation = UUID()
    private var attachTask: Task<Void, Never>?
    private var playing = false
    private var visible = true

    init() {
        enabled = UserDefaults.standard.bool(forKey: "haptics.enabled")
        intensity = UserDefaults.standard.object(forKey: "haptics.intensity") as? Double ?? 0.5
        mode = UserDefaults.standard.string(forKey: "haptics.mode") ?? HapticMode.whole.rawValue
    }

    func attach(to item: AVPlayerItem?) { self.item = item; refresh() }
    func setPlayback(playing: Bool) { self.playing = playing; updateOutput() }
    func setVisible(_ visible: Bool) { self.visible = visible; updateOutput() }
    private func updateOutput() { output.configure(enabled: supported && enabled && playing && visible, intensity: intensity, generation: generation) }
    private func refresh() {
        attachTask?.cancel()
        generation = UUID()
        updateOutput()
        guard supported else { status = "Music haptics aren’t supported on this device."; return }
        guard enabled else { item?.audioMix = nil; status = "Off"; return }
        guard let item = item else { status = "Ready — play a song"; return }
        let currentGeneration = generation
        status = "Preparing audio analysis…"
        attachTask = Task { [weak self, weak item] in
            guard let self = self, let item = item else { return }
            do {
                let tracks = try await item.asset.loadTracks(withMediaType: .audio)
                guard !Task.isCancelled, generation == currentGeneration, let track = tracks.first else { return }
                let context = AudioTapContext(output: output, generation: currentGeneration, mode: HapticMode(rawValue: mode) ?? .whole)
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
                var unmanaged: Unmanaged<MTAudioProcessingTap>?
                let result = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &unmanaged)
                guard result == noErr, let tap = unmanaged?.takeRetainedValue() else {
                    reference.release(); status = "Audio analysis is unavailable for this track."; return
                }
                let parameters = AVMutableAudioMixInputParameters(track: track)
                parameters.audioTapProcessor = tap
                let mix = AVMutableAudioMix()
                mix.inputParameters = [parameters]
                item.audioMix = mix
                status = "Audio-driven haptics • active while Play is onscreen"
            } catch { if !Task.isCancelled { status = "Audio analysis unavailable: \(error.localizedDescription)" } }
        }
    }
}
