package com.nikhil.yt.playback.haptics

import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey

val MusicHapticsEnabledKey = booleanPreferencesKey("musicHapticsEnabled")
val MusicHapticsModeKey = stringPreferencesKey("musicHapticsMode")
val MusicHapticsIntensityKey = stringPreferencesKey("musicHapticsIntensity")
val MusicHapticsEngineKey = stringPreferencesKey("musicHapticsEngine")
val MusicHapticsBatterySaverKey = booleanPreferencesKey("musicHapticsBatterySaver")

fun Preferences.musicHapticsConfig() = MusicHapticsConfig(
    enabled = this[MusicHapticsEnabledKey] ?: false,
    mode = MusicHapticsMode.fromName(this[MusicHapticsModeKey]),
    intensity = MusicHapticsIntensity.fromName(this[MusicHapticsIntensityKey]),
    engineMode = MusicHapticsEngineMode.fromName(this[MusicHapticsEngineKey]),
    pauseOnBatterySaver = this[MusicHapticsBatterySaverKey] ?: true,
)
