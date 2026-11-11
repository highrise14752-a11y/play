// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import AudioToolbox
import Foundation

enum CrossfadeCurve {
    static func gains(progress: Double) -> (outgoing: Float, incoming: Float) {
        let angle = min(1, max(0, progress)) * .pi / 2
        return (Float(cos(angle)), Float(sin(angle)))
    }
}

struct SilentSpan: Equatable {
    let start: Double
    let end: Double
}

private struct SilenceDetector {
    private var start: Double?
    private var end = 0.0
    private(set) var spans: [SilentSpan] = []

    mutating func consume(start: Double, end: Double, peak: Float) {
        guard start.isFinite, end.isFinite, end > start, peak.isFinite else { return }
        if peak > 0.003 {
            finish()
            return
        }
        if self.start != nil, start - self.end > 0.05 { finish() }
        if self.start == nil { self.start = start }
        self.end = end
    }

    mutating func finish() {
        if let start = start, end - start >= 0.85, spans.count < 2000 {
            spans.append(SilentSpan(start: start + 0.12, end: end - 0.16))
        }
        start = nil
    }
}

enum OfflineSilence {
    static func scan(url: URL) async -> [SilentSpan] {
        guard url.isFileURL else { return [] }
        let scan = Task.detached(priority: .utility) { await read(url) }
        return await withTaskCancellationHandler(operation: { await scan.value }, onCancel: { scan.cancel() })
    }

    private static func read(_ url: URL) async -> [SilentSpan] {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .audio), let track = tracks.first,
              !Task.isCancelled, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { return [] }
        var detector = SilenceDetector()
        while !Task.isCancelled, let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer),
                  let format = CMSampleBufferGetFormatDescription(buffer),
                  let audio = CMAudioFormatDescriptionGetStreamBasicDescription(format),
                  audio.pointee.mSampleRate > 0 else { continue }
            var pointer: UnsafeMutablePointer<Int8>?
            var count = 0
            var contiguous = 0
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: &contiguous,
                                              totalLengthOut: &count, dataPointerOut: &pointer) == noErr,
                  let bytes = pointer, count == contiguous, count >= MemoryLayout<Float>.size else {
                detector.finish()
                continue
            }
            let samples = UnsafeRawPointer(bytes).assumingMemoryBound(to: Float.self)
            let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let frames = CMSampleBufferGetNumSamples(buffer)
            let duration = Double(frames) / audio.pointee.mSampleRate
            var peak: Float = 0
            for index in 0..<(count / MemoryLayout<Float>.size) {
                let sample = samples[index]
                if !sample.isFinite || abs(sample) > 0.003 { peak = 1; break }
            }
            detector.consume(start: start, end: start + duration, peak: peak)
        }
        guard !Task.isCancelled, reader.status == .completed else { reader.cancelReading(); return [] }
        detector.finish()
        return detector.spans
    }
}
