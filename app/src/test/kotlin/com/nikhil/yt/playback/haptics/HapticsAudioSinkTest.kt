package com.nikhil.yt.playback.haptics

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackParameters
import androidx.media3.exoplayer.audio.AudioSink
import org.junit.Assert.*
import org.junit.Test
import java.lang.reflect.Proxy
import java.nio.ByteBuffer

class HapticsAudioSinkTest {
    @Test fun preservesPartialWritesAndAudioBytes() {
        val original = byteArrayOf(10, 20, 30, 40)
        val buffer = ByteBuffer.wrap(original.copyOf())
        var writes = 0
        val delegate = Proxy.newProxyInstance(AudioSink::class.java.classLoader, arrayOf(AudioSink::class.java)) { _, method, args ->
            when (method.name) {
                "handleBuffer" -> {
                    assertSame(buffer, args!![0])
                    assertEquals(123456L, args[1])
                    writes++
                    if (writes == 1) { buffer.position(2); false }
                    else { buffer.position(4); true }
                }
                "getCurrentPositionUs" -> 0L
                "getPlaybackParameters" -> PlaybackParameters.DEFAULT
                else -> null
            }
        } as AudioSink
        val analyzer = MusicHapticsAnalyzer(object : HapticPulseListener {
            override fun onHapticPulse(bassEnergy: Float, vocalEnergy: Float, isKick: Boolean,
                isSharpTransient: Boolean, leadTimeMs: Long) = Unit
        }).apply { isAnalysisActive = true }
        val sink = HapticsAudioSink(delegate, analyzer)
        sink.configure(Format.Builder().setPcmEncoding(C.ENCODING_PCM_16BIT)
            .setChannelCount(1).setSampleRate(48000).build(), 0, null)
        assertFalse(sink.handleBuffer(buffer, 123456, 1))
        assertEquals(2, buffer.position())
        assertTrue(sink.handleBuffer(buffer, 123456, 1))
        assertEquals(2, writes)
        assertArrayEquals(original, buffer.array())
    }
}
