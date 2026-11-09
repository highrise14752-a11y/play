package com.nikhil.yt.playback

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class DownloadFileCopyTest {
    @Test fun copiesAudioWithoutChangingItsBytes() {
        val audio = ByteArray(200_000) { (it % 251).toByte() }
        val output = ByteArrayOutputStream()
        copyDownloadedAudio(ByteArrayInputStream(audio), output, audio.size.toLong())
        assertArrayEquals(audio, output.toByteArray())
    }

    @Test(expected = IOException::class) fun rejectsTruncatedSource() {
        copyDownloadedAudio(ByteArrayInputStream(byteArrayOf(1, 2)), ByteArrayOutputStream(), 3)
    }

    @Test(expected = IOException::class) fun rejectsIncorrectLength() {
        copyDownloadedAudio(ByteArrayInputStream(byteArrayOf(1, 2, 3)), ByteArrayOutputStream(), 2)
    }

    @Test(expected = IOException::class) fun propagatesFullStorageError() {
        val output = object : java.io.OutputStream() {
            override fun write(value: Int) { throw IOException("No space left") }
        }
        copyDownloadedAudio(ByteArrayInputStream(byteArrayOf(1, 2)), output, 2)
    }

    @Test fun usesActualContainerInsteadOfRenamingEverythingToMp3() {
        assertEquals("Title [abc].m4a", downloadedAudioName("Title", "abc", "audio/mp4"))
        assertEquals("Title [abc].webm", downloadedAudioName("Title", "abc", "audio/webm; codecs=opus"))
    }

    @Test fun sanitizesFileNamesAndLimitsLength() {
        val name = downloadedAudioName("../Bad/Name:*?", "a/b", "audio/ogg")
        assertFalse(name.contains('/'))
        assertFalse(name.contains(':'))
        assertTrue(name.endsWith("[a_b].ogg"))
        assertTrue(downloadedAudioName("A".repeat(1000), "id", "audio/mpeg").length < 180)
    }

    @Test fun detectsTheActualSavedContainer() {
        assertEquals("audio/webm", downloadedAudioMime(byteArrayOf(0x1A, 0x45, 0xDF.toByte(), 0xA3.toByte())))
        assertEquals("audio/mp4", downloadedAudioMime(byteArrayOf(0, 0, 0, 20, 102, 116, 121, 112)))
        assertEquals("audio/ogg", downloadedAudioMime("OggS".toByteArray()))
        assertEquals("audio/flac", downloadedAudioMime("fLaC".toByteArray()))
        assertEquals("audio/mpeg", downloadedAudioMime("ID3".toByteArray()))
        assertEquals("application/octet-stream", downloadedAudioMime(byteArrayOf(1, 2)))
    }
}
