package com.nikhil.yt.playback.haptics

import androidx.media3.common.Format
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer

/** Reads PCM without changing samples, timing or backpressure. */
class HapticsAudioSink(delegate: AudioSink, private val analyzer: MusicHapticsAnalyzer) : ForwardingAudioSink(delegate) {
    private var format: Format? = null
    private var analyzedBuffer: ByteBuffer? = null

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
        format = inputFormat
        analyzedBuffer = null
        analyzer.reset()
    }

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (analyzer.isAnalysisActive && analyzedBuffer !== buffer) {
            analyzedBuffer = buffer
            // Partial writes retry the same buffer; detect each beat only once.
            runCatching {
                analyzer.analyze(buffer, format, presentationTimeUs,
                    positionUs = { getCurrentPositionUs(false) },
                    playbackSpeed = { playbackParameters.speed })
            }
        }
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount).also {
            if (it) analyzedBuffer = null
        }
    }

    override fun handleDiscontinuity() {
        analyzer.flush()
        analyzedBuffer = null
        super.handleDiscontinuity()
    }

    override fun flush() {
        analyzer.flush()
        analyzedBuffer = null
        super.flush()
    }

    override fun reset() {
        analyzer.reset()
        analyzedBuffer = null
        format = null
        super.reset()
    }
}
