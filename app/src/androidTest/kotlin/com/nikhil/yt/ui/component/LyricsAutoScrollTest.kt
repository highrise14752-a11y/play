package com.nikhil.yt.ui.component

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nikhil.yt.constants.LyricsAnimationStyle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

/** Uses a real measured list, including the half-viewport padding in the lyrics UI. */
class LyricsAutoScrollTest {
    @get:Rule val compose = createComposeRule()
    private val line = mutableIntStateOf(5)
    private val following = mutableStateOf(true)
    private val suspended = mutableStateOf(false)
    private val song = mutableStateOf("song-a")
    private val style = mutableStateOf(LyricsAnimationStyle.APPLE)
    private lateinit var list: LazyListState
    private lateinit var scope: CoroutineScope

    private fun showLyrics(anchor: Float = 0.5f) {
        compose.setContent {
            list = rememberLazyListState()
            scope = rememberCoroutineScope()
            LyricsAutoScrollEffect(list, line.intValue, 60, following.value,
                suspended.value, song.value, anchor, style.value)
            LazyColumn(
                state = list,
                modifier = Modifier.width(320.dp).height(300.dp),
                contentPadding = PaddingValues(vertical = 150.dp),
            ) {
                items((0 until 60).toList()) { index ->
                    Box(Modifier.height(if (index == 17) 128.dp else 64.dp)) {
                        Text("Lyric line $index")
                    }
                }
            }
        }
        compose.waitForIdle()
    }

    private fun assertFollowing(anchor: Float = 0.5f) {
        compose.waitForIdle()
        compose.runOnIdle {
            val info = list.layoutInfo
            val row = info.visibleItemsInfo.firstOrNull { it.index == line.intValue }
            assertNotNull("The active lyric must be visible", row)
            val expected = info.viewportStartOffset +
                (info.viewportEndOffset - info.viewportStartOffset) * anchor
            assertTrue("Active lyric must follow its measured center",
                abs(row!!.offset + row.size / 2f - expected) <= 2f)
        }
    }

    @Test fun followsPlaybackAndCentersWrappedLines() {
        showLyrics()
        assertFollowing()
        compose.runOnIdle { line.intValue = 17 }
        assertFollowing()
        compose.runOnIdle { line.intValue = 42 }
        assertFollowing()
    }

    @Test fun manualScrollingPausesAndResumesOnTheSameLyric() {
        showLyrics()
        compose.runOnIdle {
            suspended.value = true
            scope.launch { list.scrollToItem(1) }
        }
        compose.waitForIdle()
        compose.runOnIdle { line.intValue = 30 }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(1, list.firstVisibleItemIndex) }
        compose.runOnIdle { suspended.value = false }
        assertFollowing()
    }

    @Test fun enablingFollowRecentersWithoutWaitingForAnotherTimestamp() {
        following.value = false
        showLyrics()
        compose.runOnIdle { line.intValue = 26 }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(0, list.firstVisibleItemIndex) }
        compose.runOnIdle { following.value = true }
        assertFollowing()
    }

    @Test fun aNewSongRecentersAnUnchangedLineIndex() {
        showLyrics(anchor = 0.35f)
        assertFollowing(0.35f)
        compose.runOnIdle { scope.launch { list.scrollToItem(0) } }
        compose.waitForIdle()
        compose.runOnIdle { song.value = "song-b" }
        assertFollowing(0.35f)
    }

    @Test fun appleMotionGlidesInsteadOfJumping() {
        showLyrics()
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { line.intValue = 7 }
        compose.mainClock.advanceTimeBy(100)
        compose.runOnIdle {
            val info = list.layoutInfo
            val row = info.visibleItemsInfo.first { it.index == 7 }
            val anchor = info.viewportStartOffset + (info.viewportEndOffset - info.viewportStartOffset) / 2f
            assertTrue("Apple scrolling should still be moving at 100 ms", row.offset + row.size / 2f - anchor > 2f)
        }
        compose.mainClock.advanceTimeBy(1000)
        assertFollowing()
    }

    @Test fun noAnimationFollowsWithoutGliding() {
        style.value = LyricsAnimationStyle.NONE
        showLyrics()
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { line.intValue = 7 }
        compose.mainClock.advanceTimeBy(64)
        assertFollowing()
    }
}
