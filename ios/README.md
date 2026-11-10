# Play for iOS

Native SwiftUI / AVPlayer application, alongside the existing Android app. Requires iOS 15 or newer; an IPA cannot support every historical iOS release.

## Included

- YouTube Music song search, audio extraction through pinned YouTubeKit, playback queue, seeking, background playback and lock-screen controls.
- Saved library, on-device audio downloads, and importing audio through Files. Files are copied into Play's Documents/Downloads folder; the library stores relative paths so sandbox changes do not break downloads.
- LRCLIB timed/plain lyrics. Apple-style following, Fade/None, Left/Center/Right alignment, tap-to-seek, and automatic resume after manual browsing. A track change clears old lyrics and cancels stale work.
- Play's supplied logo and native iPhone/iPad layouts.
- Music Together local Wi-Fi hosting/joining using Android Play's version-1 WebSocket protocol, invitations, queue requests, playback synchronization, participants, and host-controlled guest permissions.
- Audio-driven Core Haptics with intensity and Whole song / Bass & beats / Vocals emphasis controls. PCM audio is observed without modifying playback samples; output is capped at 10 pulses per second and stops while paused or backgrounded. Requires supported hardware and a source exposing compatible PCM to AVPlayer's audio tap; vocals emphasis does not isolate stems.

This is a first native iOS implementation, not full Android feature parity. Music Together currently supports local Wi-Fi invitations, not the upstream online room-code server. iOS haptics use an audio-frequency analyzer and Core Haptics rather than Android's vibrator APIs. Advanced audio effects, accounts, and lyric translation have not been ported. Lyrics retain the provider's language; English translation is not promised. Plain lyrics have no automatic timing. YouTube may change extraction behavior or restrict songs by region; playback errors are shown rather than an empty success state. Downloads initiated in the app need it to remain active until completion. Keep Play active or playing audio for local sessions; iOS may suspend inactive apps.

## Build on a Mac

Install Xcode and XcodeGen, then run from the repository root:

```sh
xcodegen generate --spec ios/project.yml --project ios
open ios/Play.xcodeproj
```

Select the shared **Play** scheme. The deployment target is 15.0. The project is generated from `project.yml`; do not edit generated project files. The workflow runs native unit tests on an iPhone simulator before archiving an unsigned device build.

## GitHub Actions / AltStore

Push changes under `ios/`, or choose **Actions → Build iOS → Run workflow**. Download the `Play-iOS-unsigned-…` artifact and extract `Play-unsigned.ipa`. This is an unsigned ARM64 device app; AltStore/AltServer must sign it with your Apple account before installation. No signing certificate, account password, or Apple key belongs in this repository. Signing/refresh restrictions belong to your installation method. Simulator results do not establish physical-device streaming or audio quality.

Android builds remain available through Gradle and **Build Android** in Actions.

## License

Play's source remains GPL-3.0-only; see the repository LICENSE and original upstream credits. YouTubeKit is MIT licensed; its license is included in `Play/ThirdPartyNotices.txt`. Lyrics requests identify Play to LRCLIB. No remote extraction server is enabled.
