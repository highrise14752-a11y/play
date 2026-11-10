# Android → iOS feature checklist

This is a migration checklist, not a claim of full parity. Source labels are inventoried from each Android Settings page. “Pending” controls must not be added as nonfunctional switches. iPhone 7 feedback uses UIKit compatibility impacts; actual vibration still requires that device.

## Main screens

| Screen | iOS state | Validation |
|---|---|---|
| Home | Suggestions, category chips, quick picks, keep listening, search/settings entry points | Cloud UI and parser checks pending for 1.1 |
| Stats | Listening time, play counts, top songs; 7/30 days/all time | Collection persistence checks pending |
| History | Timestamped listening records, playback, remove entries | UI and collection checks pending |
| Library | Playlists, songs, albums, artists, favorites/downloaded/top lists, sorting/import | UI and collection checks pending |

## Settings source inventory

### AboutScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AboutScreen.kt`

- About (`about`): Pending / compare iOS-specific behavior

### AccountSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AccountSettings.kt`

- Account (`account`): Pending / compare iOS-specific behavior
- More content (`more_content`): Pending / compare iOS-specific behavior
- This can influence what content you see and for example shows premium-only albums if you are logged in with a Premium account (`use_login_for_browse_desc`): Pending / compare iOS-specific behavior
- Auto sync with account (`yt_sync`): Pending / compare iOS-specific behavior
- General (`general`): Pending / compare iOS-specific behavior
- Select Playlist To Sync (`select_playlist_to_sync`): Pending / compare iOS-specific behavior
- Play Music Together (`music_together`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- Settings (`settings`): Pending / compare iOS-specific behavior

### AppearanceSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AppearanceSettings.kt`

- Theme (`theme`): Pending / compare iOS-specific behavior
- Enable dynamic theme (`enable_dynamic_theme`): Pending / compare iOS-specific behavior
- Random theme on startup (`random_theme_on_startup`): Pending / compare iOS-specific behavior
- Color Palette (`color_palette`): Pending / compare iOS-specific behavior
- Dark theme (`dark_theme`): Pending / compare iOS-specific behavior
- Pure black (`pure_black`): Implemented; verification pending
- Disable blur effects (`disable_blur`): Pending / compare iOS-specific behavior
- Use system font (`use_system_font`): Pending / compare iOS-specific behavior
- Player (`player`): Pending / compare iOS-specific behavior
- Player design style (`player_design_style`): Pending / compare iOS-specific behavior
- New mini player design (`new_mini_player_design`): Pending / compare iOS-specific behavior
- New library design (`new_library_design`): Pending / compare iOS-specific behavior
- Player background style (`player_background_style`): Pending / compare iOS-specific behavior
- Customized background (`customized_background`): Pending / compare iOS-specific behavior
- Hide Player Thumbnail (`hide_player_thumbnail`): Pending / compare iOS-specific behavior
- Play Canvas (`velune_canvas`): Pending / compare iOS-specific behavior
- Crop thumbnails to 1:1 (`crop_thumbnail_to_square`): Pending / compare iOS-specific behavior
- Player button colors (`player_buttons_style`): Pending / compare iOS-specific behavior
- Player slider style (`player_slider_style`): Pending / compare iOS-specific behavior
- Enable swipe to change song (`enable_swipe_thumbnail`): Pending / compare iOS-specific behavior
- Mini player swipe sensitivity (`swipe_sensitivity`): Pending / compare iOS-specific behavior
- Lyrics (`lyrics`): Pending / compare iOS-specific behavior
- Lyrics text position (`lyrics_text_position`): Implemented; verification pending
- Lyrics animation style (`lyrics_animation_style`): Implemented; verification pending
- Change lyrics on click (`lyrics_click_change`): Pending / compare iOS-specific behavior
- Auto scroll lyrics (`lyrics_auto_scroll`): Implemented; verification pending
- Lyrics text size (`lyrics_text_size`): Implemented; verification pending
- Lyrics line spacing (`lyrics_line_spacing`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- Default open tab (`default_open_tab`): Pending / compare iOS-specific behavior
- Change default library chip (`default_lib_chips`): Pending / compare iOS-specific behavior
- Show home category chips (`show_home_category_chips`): Pending / compare iOS-specific behavior
- Show tags in library (`show_tags_in_library`): Pending / compare iOS-specific behavior
- Swipe song to the left to add it to the queue or to the right to play it next (`swipe_song_to_add`): Pending / compare iOS-specific behavior
- Slim bottom navigation bar (`slim_navbar`): Pending / compare iOS-specific behavior
- Grid cell size (`grid_cell_size`): Pending / compare iOS-specific behavior
- Auto playlists (`auto_playlists`): Pending / compare iOS-specific behavior
- Show \"Liked\" playlist (`show_liked_playlist`): Pending / compare iOS-specific behavior
- Show \"Downloaded\" playlist (`show_downloaded_playlist`): Pending / compare iOS-specific behavior
- Show \"Top\" playlist (`show_top_playlist`): Pending / compare iOS-specific behavior
- Show \"Cached\" playlist (`show_cached_playlist`): Pending / compare iOS-specific behavior
- Appearance (`appearance`): Pending / compare iOS-specific behavior

### BackupAndRestore

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/BackupAndRestore.kt`

- Backup and restore (`backup_restore`): Pending / compare iOS-specific behavior

### ChangelogScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/ChangelogScreen.kt`

- Changelog (`changelog`): Pending / compare iOS-specific behavior

### ContentSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/ContentSettings.kt`

- General (`general`): Pending / compare iOS-specific behavior
- Default content language (`content_language`): Implemented; verification pending
- Default content country (`content_country`): Implemented; verification pending
- Hide explicit content (`hide_explicit`): Pending / compare iOS-specific behavior
- Hide music videos (`hide_video`): Pending / compare iOS-specific behavior
- App language (`app_language`): Pending / compare iOS-specific behavior
- Proxy (`proxy`): Pending / compare iOS-specific behavior
- Enable proxy (`enable_proxy`): Pending / compare iOS-specific behavior
- Proxy type (`proxy_type`): Pending / compare iOS-specific behavior
- Proxy URL (`proxy_url`): Pending / compare iOS-specific behavior
- Bypass proxy for streams (`stream_bypass_proxy`): Pending / compare iOS-specific behavior
- Lyrics (`lyrics`): Pending / compare iOS-specific behavior
- Enable LrcLib lyrics provider (`enable_lrclib`): Pending / compare iOS-specific behavior
- Enable KuGou lyrics provider (`enable_kugou`): Pending / compare iOS-specific behavior
- Enable BetterLyrics (`enable_betterlyrics`): Pending / compare iOS-specific behavior
- Enable SimpMusic lyrics (`enable_simpmusic_lyrics`): Pending / compare iOS-specific behavior
- Preferred lyrics provider (`set_first_lyrics_provider`): Pending / compare iOS-specific behavior
- Preload queue lyrics (`preload_queue_lyrics`): Pending / compare iOS-specific behavior
- Number of songs to preload (`queue_lyrics_preload_count`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- My Top list length (`top_length`): Pending / compare iOS-specific behavior
- Set quick picks (`set_quick_picks`): Pending / compare iOS-specific behavior
- Content (`content`): Pending / compare iOS-specific behavior

### CustomizeBackground

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/CustomizeBackground.kt`

- Customize background (`customize_background_title`): Pending / compare iOS-specific behavior

### DebugSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/DebugSettings.kt`

- Experimental Features (`experimental_features`): Pending / compare iOS-specific behavior
- Show nerd stats (`show_nerd_stats`): Pending / compare iOS-specific behavior
- Display Codec on Player (`display_codec_on_player`): Pending / compare iOS-specific behavior

### DownloadLocationSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/DownloadLocationSettings.kt`

- Download location (`download_location`): Pending / compare iOS-specific behavior
- Move existing downloads (`download_move_existing`): Pending / compare iOS-specific behavior

### MusicHapticsSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/MusicHapticsSettings.kt`

- Music haptics (`music_haptics`): Implemented; verification pending
- Haptic mode (`music_haptics_mode`): Pending / compare iOS-specific behavior
- Intensity (`music_haptics_intensity`): Implemented; verification pending
- Haptic engine (`music_haptics_engine`): Pending / compare iOS-specific behavior
- Pause haptics in battery saver (`music_haptics_battery_saver`): Pending / compare iOS-specific behavior

### MusicTogetherScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/MusicTogetherScreen.kt`

- Play Music Together (`music_together`): Pending / compare iOS-specific behavior
- Host a session (`together_welcome_host_title`): Pending / compare iOS-specific behavior
- Join from another device (`together_welcome_join_title`): Pending / compare iOS-specific behavior
- Permissions and safety (`together_welcome_permissions_title`): Pending / compare iOS-specific behavior
- Display name (`together_display_name`): Pending / compare iOS-specific behavior
- Session port (`together_port`): Pending / compare iOS-specific behavior
- Guests can add songs (`together_allow_guests_add`): Pending / compare iOS-specific behavior
- Guests can control playback (`together_allow_guests_control`): Pending / compare iOS-specific behavior
- Require approval (`together_require_approval`): Pending / compare iOS-specific behavior
- Join session (`join_session`): Pending / compare iOS-specific behavior

### PalettePickerScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PalettePickerScreen.kt`

- Color Palette (`color_palette`): Pending / compare iOS-specific behavior

### PlayerSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PlayerSettings.kt`

- Player (`player`): Pending / compare iOS-specific behavior
- Audio quality (`audio_quality`): Pending / compare iOS-specific behavior
- Playback client (`player_stream_client`): Pending / compare iOS-specific behavior
- Treat network as metered (`network_metered_title`): Pending / compare iOS-specific behavior
- History duration (`history_duration`): Pending / compare iOS-specific behavior
- Skip silence (`skip_silence`): Pending / compare iOS-specific behavior
- Audio normalization (`audio_normalization`): Pending / compare iOS-specific behavior
- Audio offload (`audio_offload`): Pending / compare iOS-specific behavior
- Progressive seek (`seek_seconds_addup`): Pending / compare iOS-specific behavior
- Pause when device volume is 0 (`pause_on_device_mute`): Pending / compare iOS-specific behavior
- Auto-start on Bluetooth connect (`auto_start_on_bluetooth`): Pending / compare iOS-specific behavior
- Queue (`queue`): Pending / compare iOS-specific behavior
- Persistent queue (`persistent_queue`): Pending / compare iOS-specific behavior
- Permanent shuffle mode (`permanent_shuffle`): Pending / compare iOS-specific behavior
- Auto download on like (`auto_download_on_like`): Pending / compare iOS-specific behavior
- Auto skip to next song when error occurs (`auto_skip_next_on_error`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- Stop music on task clear (`stop_music_on_task_clear`): Pending / compare iOS-specific behavior
- Symbols to split artists (`artist_separators`): Pending / compare iOS-specific behavior
- Playlist Tags (`manage_playlist_tags`): Pending / compare iOS-specific behavior
- Player and audio (`player_and_audio`): Pending / compare iOS-specific behavior

### PoTokenExtractionActivity

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PoTokenExtractionActivity.kt`

- Extracting tokens from URL… (`extracting_from_url`): Pending / compare iOS-specific behavior

### PoTokenScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PoTokenScreen.kt`

- Web Client PO Token (`web_client_po_token`): Pending / compare iOS-specific behavior
- Generated Tokens (`generated_tokens`): Pending / compare iOS-specific behavior
- Supported Clients (`supported_clients`): Pending / compare iOS-specific behavior
- Token Settings (`token_settings`): Pending / compare iOS-specific behavior
- Use Visitor Data (`use_visitor_data`): Pending / compare iOS-specific behavior
- PO Token Generation (`po_token_generation`): Pending / compare iOS-specific behavior

### PrivacySettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PrivacySettings.kt`

- Listen history (`listen_history`): Pending / compare iOS-specific behavior
- Pause listen history (`pause_listen_history`): Implemented; verification pending
- Clear listen history (`clear_listen_history`): Implemented; verification pending
- Search history (`search_history`): Pending / compare iOS-specific behavior
- Pause search history (`pause_search_history`): Pending / compare iOS-specific behavior
- Clear search history (`clear_search_history`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- Disable screenshot (`disable_screenshot`): Pending / compare iOS-specific behavior
- Privacy (`privacy`): Pending / compare iOS-specific behavior

### SettingsScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/SettingsScreen.kt`

- User Interface (`settings_section_ui`): Pending / compare iOS-specific behavior
- Appearance (`appearance`): Pending / compare iOS-specific behavior
- Dark theme (`dark_theme`): Pending / compare iOS-specific behavior
- Player & Content (`settings_section_player_content`): Pending / compare iOS-specific behavior
- Player and audio (`player_and_audio`): Pending / compare iOS-specific behavior
- Audio quality (`audio_quality`): Pending / compare iOS-specific behavior
- Content (`content`): Pending / compare iOS-specific behavior
- Default content language (`content_language`): Implemented; verification pending
- PO Token Generation (`po_token_generation`): Pending / compare iOS-specific behavior
- Generate and manage web client PO tokens (`po_token_generation_subtitle`): Pending / compare iOS-specific behavior
- Privacy & Security (`settings_section_privacy`): Pending / compare iOS-specific behavior
- Privacy (`privacy`): Pending / compare iOS-specific behavior
- Pause listen history (`pause_listen_history`): Implemented; verification pending
- Storage & Data (`settings_section_storage`): Pending / compare iOS-specific behavior
- Storage (`storage`): Pending / compare iOS-specific behavior
- Cache (`cache`): Pending / compare iOS-specific behavior
- Backup and restore (`backup_restore`): Pending / compare iOS-specific behavior
- Backup (`action_backup`): Pending / compare iOS-specific behavior
- System & About (`settings_section_system`): Pending / compare iOS-specific behavior
- Open supported links (`default_links`): Pending / compare iOS-specific behavior
- Open supported link by default (`open_supported_links`): Pending / compare iOS-specific behavior
- Experimental Settings (`experiment_settings`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- About (`about`): Pending / compare iOS-specific behavior
- Theme Creator (`theme_creator_title`): Pending / compare iOS-specific behavior
- Tune colors, preview the result, then export or import. (`theme_creator_subtitle`): Pending / compare iOS-specific behavior
- Customize colors (`customize_colors`): Pending / compare iOS-specific behavior
- Customize background (`customize_background_title`): Pending / compare iOS-specific behavior
- Play Music Together (`music_together`): Pending / compare iOS-specific behavior
- Internal & subcategory settings (`internal_subcategory_settings`): Pending / compare iOS-specific behavior
- No results found (`no_results_found`): Pending / compare iOS-specific behavior

### StorageSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/StorageSettings.kt`

- Storage (`storage`): Pending / compare iOS-specific behavior
- Downloaded songs (`downloaded_songs`): Implemented; verification pending
- Song Cache (`song_cache`): Pending / compare iOS-specific behavior
- Image Cache (`image_cache`): Pending / compare iOS-specific behavior
- Canvas Cache (`canvas_cache`): Pending / compare iOS-specific behavior
- Clear all downloads (`clear_all_downloads`): Pending / compare iOS-specific behavior
- Clear song cache (`clear_song_cache`): Pending / compare iOS-specific behavior
- Clear image cache (`clear_image_cache`): Implemented; verification pending
- Clear canvas cache (`clear_canvas_cache`): Pending / compare iOS-specific behavior
- Max cache size (`max_cache_size`): Pending / compare iOS-specific behavior

### UpdateScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/UpdateScreen.kt`

- Enable Update Notification (`enable_update_notification`): Pending / compare iOS-specific behavior
- Nightly (`channel_nightly`): Pending / compare iOS-specific behavior
- Updates (`updates`): Pending / compare iOS-specific behavior
- Notification (`notification_settings`): Pending / compare iOS-specific behavior
- Update Channel (`update_channel`): Pending / compare iOS-specific behavior
- Development (`commit_history`): Pending / compare iOS-specific behavior

## Known remaining gaps

- YouTube account/saved-playlist synchronization and upstream Play-account services.
- Online Together codes, approval/moderation, and server configuration; local Wi-Fi sessions are implemented.
- Full Android appearance variants, custom palettes/background/Canvas, and detailed layout switches.
- Additional lyrics providers, translation/romanization decisions, and word-timed formats.
- Advanced audio effects, normalization, silence skipping and quality/network-client controls.
- Android offload, USB audio, notification/default-link behavior and Android Auto need platform-specific iOS treatment; some require Apple entitlements.
- Android backup database files are not interchangeable with the native iOS JSON backup.

Previously removed Discord/integrations/donation/developer/inspiration sections are intentionally not restored.
