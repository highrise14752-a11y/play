package com.nikhil.yt.ui.component

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToString
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.test.platform.app.InstrumentationRegistry
import com.nikhil.yt.LocalPlayerConnection
import com.nikhil.yt.constants.LyricsAnimationStyle
import com.nikhil.yt.constants.LyricsAnimationStyleKey
import com.nikhil.yt.constants.LyricsScrollKey
import com.nikhil.yt.constants.LyricsTextPositionKey
import com.nikhil.yt.db.entities.LyricsEntity
import com.nikhil.yt.models.MediaMetadata
import com.nikhil.yt.playback.MusicService
import com.nikhil.yt.playback.PlayerConnection
import com.nikhil.yt.ui.screens.settings.LyricsPosition
import com.nikhil.yt.utils.dataStore
import com.nikhil.yt.utils.rememberEnumPreference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Exercises the real lyric renderers and persisted settings, without a music-service request. */
class LyricsPresentationTest {
    @get:Rule val compose = createComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val useV2 = mutableStateOf(false)
    private val showRenderer = mutableStateOf(true)
    @Volatile private var observedStyle: LyricsAnimationStyle? = null
    @Volatile private var observedPosition: LyricsPosition? = null
    private lateinit var connection: PlayerConnection
    private lateinit var originalPreferences: Preferences
    private lateinit var binder: MusicService.MusicBinder
    private val ready = CountDownLatch(1)
    private var bound = false
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            binder = service as MusicService.MusicBinder
            ready.countDown()
        }
        override fun onServiceDisconnected(name: ComponentName?) = Unit
    }

    @Before fun setup() {
        originalPreferences = runBlocking { context.dataStore.data.first() }
        bound = context.bindService(Intent(context, MusicService::class.java), serviceConnection, Context.BIND_AUTO_CREATE)
        assertTrue(bound)
        assertTrue("Playback service must be ready", ready.await(30, TimeUnit.SECONDS))
        runBlocking { withTimeout(30000) { binder.service.queueRestoreCompleted.first { it } } }
        binder.service.database.upsert(LyricsEntity(TEST_ID, LRC))
        instrumentation.runOnMainSync {
            binder.service.player.pause()
            binder.service.player.clearMediaItems()
            connection = PlayerConnection(context, binder, binder.service.database, scope)
            connection.mediaMetadata.value = MediaMetadata(TEST_ID, "Lyrics UI test", emptyList(), 30)
        }
        compose.mainClock.autoAdvance = false
        compose.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalPlayerConnection provides connection) {
                    val selectedStyle = rememberEnumPreference(LyricsAnimationStyleKey, LyricsAnimationStyle.APPLE).value
                    val selectedPosition = rememberEnumPreference(LyricsTextPositionKey, LyricsPosition.LEFT).value
                    SideEffect {
                        if (observedStyle != selectedStyle || observedPosition != selectedPosition)
                            android.util.Log.i("LyricsSettingsTest", "Rendered preference $selectedStyle/$selectedPosition")
                        observedStyle = selectedStyle; observedPosition = selectedPosition
                    }
                    Box(Modifier.fillMaxSize()) {
                        if (showRenderer.value) {
                            if (useV2.value) LyricsV2({ 10200L }) else Lyrics({ 10200L })
                        }
                    }
                }
            }
        }
    }

    private fun select(style: LyricsAnimationStyle, position: LyricsPosition) {
        runBlocking {
            context.dataStore.edit {
                it[LyricsAnimationStyleKey] = style.name
                it[LyricsTextPositionKey] = position.name
                it[LyricsScrollKey] = true
            }
        }
        try {
            compose.waitUntil(15000) {
                compose.mainClock.advanceTimeBy(32)
                observedStyle == style && observedPosition == position
            }
        } catch (failure: Throwable) {
            val actual = runBlocking { context.dataStore.data.first() }
            val tree = runCatching { compose.onRoot().printToString() }.getOrElse { it.toString() }
            android.util.Log.e("LyricsSettingsTest", "Requested $style/$position; observed $observedStyle/$observedPosition; stored ${actual[LyricsAnimationStyleKey]}/${actual[LyricsTextPositionKey]}; tree=$tree")
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                val file = java.io.File(context.getExternalFilesDir(null), "lyrics-test-failure.png")
                file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                bitmap.recycle()
            }
            throw AssertionError("Requested $style/$position; observed $observedStyle/$observedPosition; " +
                "stored ${actual[LyricsAnimationStyleKey]}/${actual[LyricsTextPositionKey]}; tree=$tree", failure)
        }
        compose.mainClock.advanceTimeBy(1200)
        compose.waitUntil(15000) {
            compose.mainClock.advanceTimeBy(32)
            compose.onAllNodesWithText("Anchor", useUnmergedTree = true).fetchSemanticsNodes().any {
                it.boundsInRoot.width > 0 && it.boundsInRoot.height > 0
            }
        }
    }

    @Test fun everyStyleRendersWithBothLyricEngines() {
        for (v2 in listOf(false, true)) {
            compose.runOnUiThread { useV2.value = v2 }
            for (style in LyricsAnimationStyle.entries) {
                select(style, LyricsPosition.CENTER)
                val nodes = compose.onAllNodesWithText("Anchor", useUnmergedTree = true).fetchSemanticsNodes()
                assertTrue("$style must render with V2=$v2", nodes.any { it.boundsInRoot.width > 0 })
            }
        }
    }

    @Test fun leftCenterAndRightMoveTheRealLyricsInBothEngines() {
        for (v2 in listOf(false, true)) {
            compose.runOnUiThread { useV2.value = v2 }
            val positions = LyricsPosition.entries.map { position ->
                select(LyricsAnimationStyle.APPLE, position)
                compose.onAllNodesWithText("Anchor", useUnmergedTree = true).fetchSemanticsNodes()
                    .first { it.boundsInRoot.width > 0 }.boundsInRoot.center.x
            }
            assertTrue("Left must precede Center with V2=$v2", positions[0] + 20 < positions[1])
            assertTrue("Center must precede Right with V2=$v2", positions[1] + 20 < positions[2])
        }
    }

    @After fun cleanup() {
        compose.runOnUiThread { showRenderer.value = false }
        compose.mainClock.advanceTimeBy(64)
        compose.waitForIdle()
        if (::connection.isInitialized) instrumentation.runOnMainSync { connection.dispose() }
        scope.cancel()
        if (::originalPreferences.isInitialized) runBlocking {
            context.dataStore.edit { prefs ->
                for (key in listOf(LyricsAnimationStyleKey, LyricsTextPositionKey)) {
                    val previous = originalPreferences[key]
                    if (previous == null) prefs.remove(key) else prefs[key] = previous
                }
                val previous = originalPreferences[LyricsScrollKey]
                if (previous == null) prefs.remove(LyricsScrollKey) else prefs[LyricsScrollKey] = previous
            }
        }
        if (::binder.isInitialized) binder.service.database.openHelper.writableDatabase.execSQL(
            "DELETE FROM lyrics WHERE id = ?", arrayOf(TEST_ID))
        if (bound) context.unbindService(serviceConnection)
    }

    private companion object {
        const val TEST_ID = "__play_lyrics_presentation_test__"
        const val LRC = "[00:00.00]Opening\n[00:10.00]Anchor\n[00:20.00]Closing"
    }
}
