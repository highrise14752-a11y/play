package com.nikhil.yt.lyrics

import org.junit.Assert.assertEquals
import org.junit.Test

class LyricsPreservationTest {
    @Test fun originalJapaneseAndKoreanLyricsRemainTimedAndUnchanged() {
        val lines = LyricsUtils.parseLyrics("[00:01.00]ありがとう\n[00:02.50]안녕하세요")
        assertEquals(listOf("ありがとう", "안녕하세요"), lines.map { it.text })
        assertEquals(listOf(1000L, 2500L), lines.map { it.time })
    }
}
