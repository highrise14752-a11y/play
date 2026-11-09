<div align="center">
  <img src="assets/play-logo.png" alt="Play logo" width="180" />

# Play

An ad-free Android music client built with Kotlin and Jetpack Compose.
</div>

Play is a rebranded fork of [Velune](https://github.com/nikhilvishwakarma00/Velune), originally developed by Nikhil Vishwakarma. The original Git history, copyright notices, and GPL-3.0 license are preserved.

## Features

- Background playback, offline caching, and library management
- Synced lyrics, translation, and animated artwork
- Material You themes and audio controls
- Discord Rich Presence and listening statistics

## Build

Requires JDK 21, Android SDK 36, and Android Studio.

```sh
git clone https://github.com/highrise14752-a11y/play.git
cd play
./gradlew :app:assembleUniversalDebug
```

On Windows, use `gradlew.bat :app:assembleUniversalDebug`. Configure the Android SDK in your local `local.properties` file or through `ANDROID_HOME`. Optional integration keys are read from local properties or environment variables; see `app/build.gradle.kts`.

For daily use, build `./gradlew :app:assembleUniversalOptimized` (all CPU architectures) or `./gradlew :app:assembleArm64Optimized` (ARM64 phones). These enable the release optimizer and resource shrinking, disable debugging, and use the local debug signing key so they can update the earlier debug APK. Keep this key stable for future updates. Debug builds include development tooling and are unsuitable for comparing release size or performance.

Run `./gradlew :app:exportPlayApk` to write the installable file as `app/build/outputs/play/Play.apk`. In-app labels, including debug builds, use **Play**. New listening-session links use `play://`; older invitation links remain supported.

The Android application ID is `com.highrise14752.play`. No Play APK has been released yet. Updates will use [this repository's releases](https://github.com/highrise14752-a11y/play/releases). Some inherited online integrations still depend on upstream services and their configuration.

## Branding

The supplied Play artwork is stored in `assets/play-logo.png` and used for Android launcher icons, in-app branding, and store metadata. Historical screenshots may still show the upstream interface.

## Credits and license

Based on Velune and its upstream projects, including ArchiveTune, Metrolist, InnerTune, Kizzy, SimpMusic, and BetterLyrics. See the source headers and [GPL-3.0 license](LICENSE). Play is an independent client and is not affiliated with YouTube or Google.
