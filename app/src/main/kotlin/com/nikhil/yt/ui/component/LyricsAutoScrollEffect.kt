package com.nikhil.yt.ui.component

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.flow.first
import com.nikhil.yt.constants.LyricsAnimationStyle
import kotlin.math.abs
import kotlin.math.roundToInt

internal val AppleLyricsEasing = CubicBezierEasing(0.25f, 0.1f, 0.25f, 1f)

/** Following is state-driven so resuming does not need another lyric timestamp. */
@Composable
internal fun LyricsAutoScrollEffect(
    listState: LazyListState,
    activeLineIndex: Int,
    lineCount: Int,
    enabled: Boolean,
    suspended: Boolean,
    contentKey: Any?,
    anchorFraction: Float = 0.5f,
    animationStyle: LyricsAnimationStyle = LyricsAnimationStyle.APPLE,
) {
    val viewportSize by remember(listState) { derivedStateOf { listState.layoutInfo.viewportSize } }
    LaunchedEffect(listState, activeLineIndex, lineCount, enabled, suspended, contentKey, viewportSize, anchorFraction, animationStyle) {
        if (!enabled || suspended || activeLineIndex !in 0 until lineCount) return@LaunchedEffect
        val layout = snapshotFlow { listState.layoutInfo }.first {
            it.totalItemsCount > activeLineIndex && it.viewportSize.height > 0
        }
        val anchor = layout.viewportStartOffset +
            (layout.viewportEndOffset - layout.viewportStartOffset) * anchorFraction
        if (layout.visibleItemsInfo.none { it.index == activeLineIndex }) {
            if (animationStyle == LyricsAnimationStyle.NONE) {
                listState.scrollToItem(activeLineIndex, -anchor.roundToInt())
            } else {
                listState.animateScrollToItem(activeLineIndex, -anchor.roundToInt())
            }
        }
        val measured = snapshotFlow { listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == activeLineIndex } }
            .first { it != null } ?: return@LaunchedEffect
        val delta = measured.offset + measured.size / 2f - anchor
        if (abs(delta) > 1f) {
            val motion = when (animationStyle) {
                LyricsAnimationStyle.APPLE -> tween<Float>(550, easing = AppleLyricsEasing)
                LyricsAnimationStyle.NONE -> snap<Float>()
                else -> spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessLow)
            }
            listState.animateScrollBy(delta, motion)
        }
    }
}
