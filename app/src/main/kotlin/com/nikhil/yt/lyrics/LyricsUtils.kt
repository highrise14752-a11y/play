/*
 * Velune - by Nikhil
 * Nikhil
 * Licensed Under GPL-3.0
 */


package com.nikhil.yt.lyrics

import android.text.format.DateUtils
import com.nikhil.yt.betterlyrics.TTMLParser

@Suppress("RegExpRedundantEscape")
object LyricsUtils {
    val LINE_REGEX = "((\\[\\d\\d:\\d\\d\\.\\d{2,3}\\] ?)+)(.+)".toRegex()
    val TIME_REGEX = "\\[(\\d\\d):(\\d\\d)\\.(\\d{2,3})\\]".toRegex()

    fun isTtml(lyrics: String): Boolean {
        val trimmed = lyrics.trim()
        if (!trimmed.startsWith("<")) return false

        return trimmed.contains("<tt", ignoreCase = true) ||
                trimmed.contains("http://www.w3.org/ns/ttml", ignoreCase = true)
    }

    fun parseTtml(lyrics: String, durationSeconds: Int? = null): List<LyricsEntry> {
        val parsedLines = TTMLParser.parseTTML(lyrics)
        if (parsedLines.isEmpty()) return emptyList()
        val scale = 1.0

        return parsedLines.map { line ->
            val words =
                line.words
                    .filter { it.text.isNotEmpty() }
                    .map { word ->
                        WordTimestamp(
                            text = word.text,
                            startTime = word.startTime * scale,
                            endTime = word.endTime * scale,
                            isBackground = word.isBackground,
                        )
                    }.takeIf { it.isNotEmpty() }

            LyricsEntry(
                time = (line.startTime * scale * 1000.0).toLong(),
                text = line.text,
                words = words,
                agent = line.agent,
            )
        }.sorted()
    }

    fun parseLyrics(lyrics: String): List<LyricsEntry> {
        val lines = lyrics.lines()
        val result = mutableListOf<LyricsEntry>()

        for (line in lines) {
            val entries = parseLine(line)
            if (entries != null) {
                result.addAll(entries)
            }
        }
        return result.sorted()
    }

    private fun parseLine(line: String): List<LyricsEntry>? {
        if (line.isEmpty()) {
            return null
        }
        val matchResult = LINE_REGEX.matchEntire(line.trim()) ?: return null
        val times = matchResult.groupValues[1]
        val text = matchResult.groupValues[3]
        val timeMatchResults = TIME_REGEX.findAll(times)

        return timeMatchResults
            .map { timeMatchResult ->
                val min = timeMatchResult.groupValues[1].toLong()
                val sec = timeMatchResult.groupValues[2].toLong()
                val milString = timeMatchResult.groupValues[3]
                var mil = milString.toLong()
                if (milString.length == 2) {
                    mil *= 10
                }
                val time = min * DateUtils.MINUTE_IN_MILLIS + sec * DateUtils.SECOND_IN_MILLIS + mil
                LyricsEntry(time, text)
            }.toList()
    }

    fun findCurrentLineIndex(
        lines: List<LyricsEntry>,
        position: Long,
        leadMs: Long = 300L,
    ): Int {
        if (lines.isEmpty()) return -1

        val target = position + leadMs
        var low = 0
        var high = lines.lastIndex

        while (low <= high) {
            val mid = (low + high).ushr(1)
            val midTime = lines[mid].time

            if (midTime < target) {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        return high.coerceIn(0, lines.lastIndex)
    }

    /**
     * Checks if the given text contains any Japanese characters (Hiragana, Katakana, or common Kanji).
     * This function is generally efficient due to '.any' and early exit.
     * No major performance bottlenecks expected here for typical inputs.
     */
    fun isJapanese(text: String): Boolean {
        return text.any { char ->
            (char in '\u3040'..'\u309F') || // Hiragana
            (char in '\u30A0'..'\u30FF') || // Katakana
            // CJK Unified Ideographs (covers most common Kanji)
            // Note: This range also includes many Chinese Hanzi.
            // Differentiating Japanese Kanji from Chinese Hanzi solely based on Unicode
            // ranges is challenging as they share many characters.
            // For more accurate Japanese detection, one might need to analyze
            // the presence of Hiragana/Katakana alongside Kanji.
            (char in '\u4E00'..'\u9FFF')
        }
    }

    /**
     * Checks if the given text contains any Korean characters (Hangul Syllables, Jamo, etc.).
     */
    fun isKorean(text: String): Boolean {
        return text.any { char ->
            (char in '\uAC00'..'\uD7A3') // Hangul Syllables
        }
    }

    /**
     * Checks if the given text contains any Chinese characters (common Hanzi).
     * This function is generally efficient due to '.any' and early exit.
     * To improve accuracy in distinguishing between Chinese and Japanese (which shares Kanji),
     * this function now checks if the text *predominantly* consists of CJK Unified Ideographs
     * and *lacks* significant amounts of Hiragana or Katakana.
     *
     * A simple threshold is used here. More sophisticated methods (e.g., frequency analysis,
     * dictionaries, or machine learning models) would be needed for higher accuracy.
     */
    fun isChinese(text: String): Boolean {
        if (text.isEmpty()) return false

        val cjkCharCount = text.count { char -> char in '\u4E00'..'\u9FFF' }
        val hiraganaKatakanaCount = text.count { char -> (char in '\u3040'..'\u309F') || (char in '\u30A0'..'\u30FF') }

        // Heuristic: If CJK characters are present and there are very few or no Hiragana/Katakana,
        // it's more likely to be Chinese.
        // The threshold (e.g., 0.1) can be adjusted based on desired sensitivity.
        return cjkCharCount > 0 && (hiraganaKatakanaCount.toDouble() / text.length.toDouble()) < 0.1
    }
}
