package com.nikhil.yt.ui.screens.settings

import android.content.Context
import android.media.audiofx.HapticGenerator
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.nikhil.yt.R
import com.nikhil.yt.playback.haptics.*
import com.nikhil.yt.ui.component.EnumListPreference
import com.nikhil.yt.ui.component.PreferenceGroupTitle
import com.nikhil.yt.ui.component.SwitchPreference
import com.nikhil.yt.utils.rememberEnumPreference
import com.nikhil.yt.utils.rememberPreference

@Composable
fun MusicHapticsSettings() {
    val context = LocalContext.current
    val vibrator = remember(context) {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }
    val supported = remember(vibrator) { vibrator?.hasVibrator() == true }
    val nativeSupported = remember {
        Build.VERSION.SDK_INT >= 31 && runCatching { HapticGenerator.isAvailable() }.getOrDefault(false)
    }
    val (enabled, setEnabled) = rememberPreference(MusicHapticsEnabledKey, false)
    val (mode, setMode) = rememberEnumPreference(MusicHapticsModeKey, MusicHapticsMode.WHOLE_SONG)
    val (intensity, setIntensity) = rememberEnumPreference(MusicHapticsIntensityKey, MusicHapticsIntensity.MEDIUM)
    val (engine, setEngine) = rememberEnumPreference(MusicHapticsEngineKey, MusicHapticsEngineMode.AUTO)
    val (batterySaver, setBatterySaver) = rememberPreference(MusicHapticsBatterySaverKey, true)
    PreferenceGroupTitle(title = stringResource(R.string.music_haptics))
    SwitchPreference(
        title = { Text(stringResource(R.string.music_haptics)) },
        description = stringResource(if (supported) R.string.music_haptics_description else R.string.music_haptics_unavailable),
        checked = enabled, onCheckedChange = setEnabled, isEnabled = supported,
    )
    if (enabled && supported) {
        EnumListPreference(
            title = { Text(stringResource(R.string.music_haptics_mode)) }, icon = null,
            selectedValue = mode, valueText = { it.label }, onValueSelected = setMode,
        )
        EnumListPreference(
            title = { Text(stringResource(R.string.music_haptics_intensity)) }, icon = null,
            selectedValue = intensity, valueText = { it.label }, onValueSelected = setIntensity,
        )
        if (nativeSupported) {
            EnumListPreference(
                title = { Text(stringResource(R.string.music_haptics_engine)) }, icon = null,
                selectedValue = engine, valueText = { it.label }, onValueSelected = setEngine,
            )
            Text(stringResource(R.string.music_haptics_native_note))
        }
        SwitchPreference(
            title = { Text(stringResource(R.string.music_haptics_battery_saver)) },
            checked = batterySaver, onCheckedChange = setBatterySaver,
        )
        TextButton(onClick = {
            runCatching {
                val amplitude = (255 * intensity.amplitudeScale).toInt().coerceIn(1, 255)
                vibrator?.vibrate(VibrationEffect.createOneShot(45L,
                    if (vibrator.hasAmplitudeControl()) amplitude else VibrationEffect.DEFAULT_AMPLITUDE))
            }
        }) { Text(stringResource(R.string.music_haptics_test)) }
    }
}
