package com.nikhil.yt.playback

import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/** A complete, byte-for-byte copy is required before replacing a download's location. */
internal fun copyDownloadedAudio(input: InputStream, output: OutputStream, expectedBytes: Long) {
    require(expectedBytes > 0) { "Unknown download length" }
    val copied = input.copyTo(output)
    output.flush()
    if (copied != expectedBytes) throw IOException("Incomplete audio file: $copied of $expectedBytes bytes")
}

internal fun downloadedAudioName(title: String, id: String, mimeType: String): String {
    fun clean(value: String) = value.replace(Regex("[\\\\/:*?\"<>|\\p{Cntrl}]"), "_").trim().trim('.')
    val extension = when (mimeType.substringBefore(';').trim()) {
        "audio/mp4" -> "m4a"
        "audio/mpeg" -> "mp3"
        "audio/ogg" -> "ogg"
        "audio/opus" -> "opus"
        "audio/webm", "video/webm" -> "webm"
        "audio/flac" -> "flac"
        else -> "audio"
    }
    return "${clean(title).take(100).ifBlank { "Song" }} [${clean(id).take(64)}].$extension"
}

/** Detect the saved container rather than trusting playback metadata for a different stream. */
internal fun downloadedAudioMime(header: ByteArray): String {
    fun startsWith(vararg bytes: Int) = header.size >= bytes.size &&
        bytes.indices.all { (header[it].toInt() and 255) == bytes[it] }
    return when {
        startsWith(0x1A, 0x45, 0xDF, 0xA3) -> "audio/webm"
        header.size >= 8 && String(header, 4, 4, Charsets.US_ASCII) == "ftyp" -> "audio/mp4"
        startsWith(0x4F, 0x67, 0x67, 0x53) -> "audio/ogg"
        startsWith(0x66, 0x4C, 0x61, 0x43) -> "audio/flac"
        startsWith(0x49, 0x44, 0x33) || (header.size >= 2 &&
            (header[0].toInt() and 255) == 0xFF && (header[1].toInt() and 0xE0) == 0xE0) -> "audio/mpeg"
        else -> "application/octet-stream"
    }
}
