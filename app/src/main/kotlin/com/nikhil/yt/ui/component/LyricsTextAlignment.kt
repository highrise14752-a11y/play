package com.nikhil.yt.ui.component

import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextAlign
import com.nikhil.yt.ui.screens.settings.LyricsPosition

internal val LyricsPosition.textAlignment: TextAlign
    get() = when (this) {
        LyricsPosition.LEFT -> TextAlign.Start
        LyricsPosition.CENTER -> TextAlign.Center
        LyricsPosition.RIGHT -> TextAlign.End
    }

internal val LyricsPosition.lineAlignment: Alignment.Horizontal
    get() = when (this) {
        LyricsPosition.LEFT -> Alignment.Start
        LyricsPosition.CENTER -> Alignment.CenterHorizontally
        LyricsPosition.RIGHT -> Alignment.End
    }
