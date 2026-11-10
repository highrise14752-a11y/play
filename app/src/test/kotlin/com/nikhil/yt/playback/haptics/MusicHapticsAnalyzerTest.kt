package com.nikhil.yt.playback.haptics

import androidx.media3.common.C
import androidx.media3.common.Format
import org.junit.Assert.*
import org.junit.Test
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.sin

class MusicHapticsAnalyzerTest {
    private class Listener : HapticPulseListener {
        val leads = mutableListOf<Long>()
        var flushes = 0
        override fun onHapticPulse(bassEnergy: Float, vocalEnergy: Float, isKick: Boolean,
            isSharpTransient: Boolean, leadTimeMs: Long) { leads += leadTimeMs }
        override fun onAnalysisFlushed() { flushes++ }
    }

    private fun format(encoding: Int = C.ENCODING_PCM_16BIT) = Format.Builder()
        .setSampleRate(48000).setChannelCount(1).setPcmEncoding(encoding).build()

    private fun bass(): ByteBuffer = ByteBuffer.allocateDirect(48000 / 2).order(ByteOrder.LITTLE_ENDIAN).apply {
        repeat(capacity() / 2) { index ->
            putShort((sin(2 * PI * 80 * index / 48000) * 26000).toInt().toShort())
        }
        flip()
    }

    @Test fun disabledAnalyzerDoesNotReadOrEmit() {
        val listener = Listener()
        val analyzer = MusicHapticsAnalyzer(listener)
        val buffer = bass()
        analyzer.analyze(buffer, format(), 200000, { error("Disabled analysis must not read the clock") }, { 1f })
        assertTrue(listener.leads.isEmpty())
        assertEquals(0, buffer.position())
    }

    @Test fun detectsBassWithoutChangingPcmOrBufferPosition() {
        val listener = Listener()
        val analyzer = MusicHapticsAnalyzer(listener).apply { isAnalysisActive = true }
        val buffer = bass()
        val before = ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
        analyzer.analyze(buffer, format(), 200000, { 0L }, { 1f })
        val after = ByteArray(buffer.remaining()).also { buffer.duplicate().get(it) }
        assertArrayEquals(before, after)
        assertEquals(0, buffer.position())
        assertTrue("Bass should produce timed pulses", listener.leads.isNotEmpty())
        assertTrue(listener.leads.all { it in 0..1500 })
    }

    @Test fun unknownAudioClockDropsPulses() {
        val listener = Listener()
        val analyzer = MusicHapticsAnalyzer(listener).apply { isAnalysisActive = true }
        analyzer.analyze(bass(), format(), 200000, { Long.MIN_VALUE }, { 1f })
        assertTrue(listener.leads.isEmpty())
    }

    @Test fun silenceDoesNotProducePulses() {
        val listener = Listener()
        val analyzer = MusicHapticsAnalyzer(listener).apply { isAnalysisActive = true }
        analyzer.analyze(ByteBuffer.allocateDirect(48000), format(), 200000, { 0L }, { 1f })
        assertTrue(listener.leads.isEmpty())
    }

    @Test fun flushCancelsOnlyActiveAnalyzersPulses() {
        val listener = Listener()
        val analyzer = MusicHapticsAnalyzer(listener)
        analyzer.flush()
        assertEquals(0, listener.flushes)
        analyzer.isAnalysisActive = true
        analyzer.flush()
        assertEquals(1, listener.flushes)
    }

    @Test fun invalidSavedOptionsUseSafeDefaults() {
        assertEquals(MusicHapticsMode.WHOLE_SONG, MusicHapticsMode.fromName("invalid"))
        assertEquals(MusicHapticsIntensity.MEDIUM, MusicHapticsIntensity.fromName(null))
        assertEquals(MusicHapticsEngineMode.AUTO, MusicHapticsEngineMode.fromName("invalid"))
        assertFalse(MusicHapticsConfig().enabled)
        assertTrue(MusicHapticsConfig().pauseOnBatterySaver)
    }
}
