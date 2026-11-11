# Android → iOS feature checklist

This is a migration checklist, not a claim of full parity. Source labels are inventoried from each Android Settings page. “Pending” controls must not be added as nonfunctional switches. iPhone 7 feedback uses UIKit compatibility impacts; actual vibration still requires that device.

## Main screens

| Screen | iOS state | Validation |
|---|---|---|
| Home | Suggestions, category chips, quick picks, keep listening, search/settings entry points | Passed tab navigation, Home preview, and catalog parser checks in 1.1 |
| Stats | Listening time, play counts, top songs; 7/30 days/all time | Passed collection persistence checks in 1.1 |
| History | Timestamped listening records, playback, remove entries | Passed navigation and collection checks in 1.1 |
| Library | Playlists, songs, albums, artists, favorites/downloaded/top lists, sorting/import | Passed navigation and collection checks in 1.1 |

## Settings source inventory

### AboutScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AboutScreen.kt`

- About (`about`): Present in iOS

### AccountSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AccountSettings.kt`

- Account (`account`): Pending / compare iOS-specific behavior
- More content (`more_content`): Pending / compare iOS-specific behavior
- This can influence what content you see and for example shows premium-only albums if you are logged in with a Premium account (`use_login_for_browse_desc`): Pending / compare iOS-specific behavior
- Auto sync with account (`yt_sync`): Pending / compare iOS-specific behavior
- General (`general`): Pending / compare iOS-specific behavior
- Select Playlist To Sync (`select_playlist_to_sync`): Pending / compare iOS-specific behavior
- Play Music Together (`music_together`): Wi-Fi hosting and joining, permissions, approvals, removal, and session bans
- Misc (`misc`): Pending / compare iOS-specific behavior
- Settings (`settings`): Pending / compare iOS-specific behavior

### AppearanceSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/AppearanceSettings.kt`

- Theme (`theme`): Pending / compare iOS-specific behavior
- Enable dynamic theme (`enable_dynamic_theme`): Present in iOS
- Random theme on startup (`random_theme_on_startup`): Present in iOS
- Color Palette (`color_palette`): Pending / compare iOS-specific behavior
- Dark theme (`dark_theme`): System, Dark, or Light
- Pure black (`pure_black`): Present in iOS
- Disable blur effects (`disable_blur`): Present in iOS
- Use system font (`use_system_font`): Present in iOS
- Player (`player`): Pending / compare iOS-specific behavior
- Player design style (`player_design_style`): Compact player controls
- New mini player design (`new_mini_player_design`): Compact or standard mini player
- New library design (`new_library_design`): Pending / compare iOS-specific behavior
- Player background style (`player_background_style`): Solid, gradient, blurred artwork, or a photo selected from Files
- Customized background (`customized_background`): Present in iOS
- Hide Player Thumbnail (`hide_player_thumbnail`): Present in iOS
- Play Canvas (`velune_canvas`): Pending / compare iOS-specific behavior
- Crop thumbnails to 1:1 (`crop_thumbnail_to_square`): Present in iOS
- Player button colors (`player_buttons_style`): Present in iOS
- Player slider style (`player_slider_style`): Present in iOS
- Enable swipe to change song (`enable_swipe_thumbnail`): Present in iOS
- Mini player swipe sensitivity (`swipe_sensitivity`): Present in iOS
- Lyrics (`lyrics`): Pending / compare iOS-specific behavior
- Lyrics text position (`lyrics_text_position`): Present in iOS
- Lyrics animation style (`lyrics_animation_style`): Present in iOS
- Change lyrics on click (`lyrics_click_change`): Present in iOS
- Auto scroll lyrics (`lyrics_auto_scroll`): Present in iOS
- Lyrics text size (`lyrics_text_size`): Present in iOS
- Lyrics line spacing (`lyrics_line_spacing`): Present in iOS
- Misc (`misc`): Pending / compare iOS-specific behavior
- Default open tab (`default_open_tab`): Present in iOS
- Change default library chip (`default_lib_chips`): Present in iOS
- Show home category chips (`show_home_category_chips`): Present in iOS
- Show tags in library (`show_tags_in_library`): Present in iOS
- Swipe song to the left to add it to the queue or to the right to play it next (`swipe_song_to_add`): Present in iOS
- Slim bottom navigation bar (`slim_navbar`): Present in iOS
- Grid cell size (`grid_cell_size`): Pending / compare iOS-specific behavior
- Auto playlists (`auto_playlists`): Pending / compare iOS-specific behavior
- Show \"Liked\" playlist (`show_liked_playlist`): Present in iOS
- Show \"Downloaded\" playlist (`show_downloaded_playlist`): Present in iOS
- Show \"Top\" playlist (`show_top_playlist`): Present in iOS
- Show \"Cached\" playlist (`show_cached_playlist`): Pending / compare iOS-specific behavior
- Appearance (`appearance`): Present in iOS

### BackupAndRestore

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/BackupAndRestore.kt`

- Backup and restore (`backup_restore`): Present in iOS

### ChangelogScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/ChangelogScreen.kt`

- Changelog (`changelog`): Pending / compare iOS-specific behavior

### ContentSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/ContentSettings.kt`

- General (`general`): Pending / compare iOS-specific behavior
- Default content language (`content_language`): Present in iOS
- Default content country (`content_country`): Present in iOS
- Hide explicit content (`hide_explicit`): Present in iOS
- Hide music videos (`hide_video`): Present in iOS
- App language (`app_language`): Pending / compare iOS-specific behavior
- Proxy (`proxy`): Pending / compare iOS-specific behavior
- Enable proxy (`enable_proxy`): Pending / compare iOS-specific behavior
- Proxy type (`proxy_type`): Pending / compare iOS-specific behavior
- Proxy URL (`proxy_url`): Pending / compare iOS-specific behavior
- Bypass proxy for streams (`stream_bypass_proxy`): Pending / compare iOS-specific behavior
- Lyrics (`lyrics`): Pending / compare iOS-specific behavior
- Enable LrcLib lyrics provider (`enable_lrclib`): Present in iOS
- Enable KuGou lyrics provider (`enable_kugou`): Present in iOS
- Enable BetterLyrics (`enable_betterlyrics`): Present in iOS
- Enable SimpMusic lyrics (`enable_simpmusic_lyrics`): Present in iOS
- Preferred lyrics provider (`set_first_lyrics_provider`): Present in iOS
- Preload queue lyrics (`preload_queue_lyrics`): Present in iOS
- Number of songs to preload (`queue_lyrics_preload_count`): Present in iOS
- Misc (`misc`): Pending / compare iOS-specific behavior
- My Top list length (`top_length`): Present in iOS
- Set quick picks (`set_quick_picks`): Pending / compare iOS-specific behavior
- Content (`content`): Pending / compare iOS-specific behavior

### CustomizeBackground

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/CustomizeBackground.kt`

- Customize background (`customize_background_title`): Present in iOS

### DebugSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/DebugSettings.kt`

- Experimental Features (`experimental_features`): Pending / compare iOS-specific behavior
- Show nerd stats (`show_nerd_stats`): Pending / compare iOS-specific behavior
- Display Codec on Player (`display_codec_on_player`): Pending / compare iOS-specific behavior

### DownloadLocationSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/DownloadLocationSettings.kt`

- Download location (`download_location`): Private offline storage with optional copies in a selected Files folder
- Move existing downloads (`download_move_existing`): Copy existing offline downloads to the selected Files folder

### MusicHapticsSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/MusicHapticsSettings.kt`

- Music haptics (`music_haptics`): Present in iOS
- Haptic mode (`music_haptics_mode`): Present in iOS
- Intensity (`music_haptics_intensity`): Present in iOS
- Haptic engine (`music_haptics_engine`): Automatic hardware selection with a separate iPhone 7 fallback
- Pause haptics in battery saver (`music_haptics_battery_saver`): Present in iOS

### MusicTogetherScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/MusicTogetherScreen.kt`

- Play Music Together (`music_together`): Wi-Fi hosting and joining, permissions, approvals, removal, and session bans
- Host a session (`together_welcome_host_title`): Pending / compare iOS-specific behavior
- Join from another device (`together_welcome_join_title`): Pending / compare iOS-specific behavior
- Permissions and safety (`together_welcome_permissions_title`): Pending / compare iOS-specific behavior
- Display name (`together_display_name`): Present in iOS
- Session port (`together_port`): Present in iOS
- Guests can add songs (`together_allow_guests_add`): Present in iOS
- Guests can control playback (`together_allow_guests_control`): Present in iOS
- Require approval (`together_require_approval`): Present in iOS
- Join session (`join_session`): Present in iOS

### PalettePickerScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PalettePickerScreen.kt`

- Color Palette (`color_palette`): Pending / compare iOS-specific behavior

### PlayerSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/PlayerSettings.kt`

- Player (`player`): Pending / compare iOS-specific behavior
- Audio quality (`audio_quality`): Present in iOS
- Playback client (`player_stream_client`): Pending / compare iOS-specific behavior
- Treat network as metered (`network_metered_title`): Present in iOS
- History duration (`history_duration`): Present in iOS
- Crossfade: Native player overlap with an adjustable duration. Disabled for shared listening and repeat-one.
- Skip silence (`skip_silence`): Supported for downloaded and imported audio.
- Audio normalization (`audio_normalization`): Present in iOS
- Audio offload (`audio_offload`): Pending / compare iOS-specific behavior
- Progressive seek (`seek_seconds_addup`): Present in iOS
- Pause when device volume is 0 (`pause_on_device_mute`): Present in iOS
- Auto-start on Bluetooth connect (`auto_start_on_bluetooth`): Present in iOS
- Queue (`queue`): Pending / compare iOS-specific behavior
- Persistent queue (`persistent_queue`): Present in iOS
- Permanent shuffle mode (`permanent_shuffle`): Present in iOS
- Auto download on like (`auto_download_on_like`): Present in iOS
- Auto skip to next song when error occurs (`auto_skip_next_on_error`): Present in iOS
- Misc (`misc`): Pending / compare iOS-specific behavior
- Stop music on task clear (`stop_music_on_task_clear`): Pending / compare iOS-specific behavior
- Symbols to split artists (`artist_separators`): Pending / compare iOS-specific behavior
- Playlist Tags (`manage_playlist_tags`): Present in iOS
- Player and audio (`player_and_audio`): Present in iOS

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
- Pause listen history (`pause_listen_history`): Present in iOS
- Clear listen history (`clear_listen_history`): Present in iOS
- Search history (`search_history`): Pending / compare iOS-specific behavior
- Pause search history (`pause_search_history`): Present in iOS
- Clear search history (`clear_search_history`): Present in iOS
- Misc (`misc`): Pending / compare iOS-specific behavior
- Disable screenshot (`disable_screenshot`): Pending / compare iOS-specific behavior
- Privacy (`privacy`): Pending / compare iOS-specific behavior

### SettingsScreen

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/SettingsScreen.kt`

- User Interface (`settings_section_ui`): Pending / compare iOS-specific behavior
- Appearance (`appearance`): Present in iOS
- Dark theme (`dark_theme`): System, Dark, or Light
- Player & Content (`settings_section_player_content`): Pending / compare iOS-specific behavior
- Player and audio (`player_and_audio`): Present in iOS
- Audio quality (`audio_quality`): Present in iOS
- Content (`content`): Pending / compare iOS-specific behavior
- Default content language (`content_language`): Present in iOS
- PO Token Generation (`po_token_generation`): Pending / compare iOS-specific behavior
- Generate and manage web client PO tokens (`po_token_generation_subtitle`): Pending / compare iOS-specific behavior
- Privacy & Security (`settings_section_privacy`): Pending / compare iOS-specific behavior
- Privacy (`privacy`): Pending / compare iOS-specific behavior
- Pause listen history (`pause_listen_history`): Present in iOS
- Storage & Data (`settings_section_storage`): Pending / compare iOS-specific behavior
- Storage (`storage`): Present in iOS
- Cache (`cache`): Pending / compare iOS-specific behavior
- Backup and restore (`backup_restore`): Present in iOS
- Backup (`action_backup`): Pending / compare iOS-specific behavior
- System & About (`settings_section_system`): Pending / compare iOS-specific behavior
- Open supported links (`default_links`): Pending / compare iOS-specific behavior
- Open supported link by default (`open_supported_links`): Pending / compare iOS-specific behavior
- Experimental Settings (`experiment_settings`): Pending / compare iOS-specific behavior
- Misc (`misc`): Pending / compare iOS-specific behavior
- About (`about`): Present in iOS
- Theme Creator (`theme_creator_title`): Present in iOS
- Tune colors, preview the result, then export or import. (`theme_creator_subtitle`): Pending / compare iOS-specific behavior
- Customize colors (`customize_colors`): Present in iOS
- Customize background (`customize_background_title`): Present in iOS
- Play Music Together (`music_together`): Wi-Fi hosting and joining, permissions, approvals, removal, and session bans
- Internal & subcategory settings (`internal_subcategory_settings`): Pending / compare iOS-specific behavior
- No results found (`no_results_found`): Pending / compare iOS-specific behavior

### StorageSettings

Android source: `app/src/main/kotlin/com/nikhil/yt/ui/screens/settings/StorageSettings.kt`

- Storage (`storage`): Present in iOS
- Downloaded songs (`downloaded_songs`): Present in iOS
- Song Cache (`song_cache`): Pending / compare iOS-specific behavior
- Image Cache (`image_cache`): Pending / compare iOS-specific behavior
- Canvas Cache (`canvas_cache`): Pending / compare iOS-specific behavior
- Clear all downloads (`clear_all_downloads`): Present in iOS
- Clear song cache (`clear_song_cache`): Pending / compare iOS-specific behavior
- Clear image cache (`clear_image_cache`): Present in iOS
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

- Private YouTube account synchronization and upstream Play-account services. Public playlists can be imported from a link.
- Online Together room codes and server configuration need a supported authentication flow. Wi-Fi room approval, moderation, and permissions are implemented.
- Canvas and additional Android layout variants. The Android Canvas service did not resolve in testing. iOS has artwork colors, a custom photo background, and theme import/export.
- Lyrics translation and some word-timed formats. The iOS app supports four lyric providers and TTML word timing. Provider results depend on availability.
- Silence skipping for live streams, playback-client selection, and Android-specific audio routing. Crossfade and saved-audio silence skipping are implemented.
- Android offload, USB audio, notification/default-link behavior and Android Auto need platform-specific iOS treatment; some require Apple entitlements.
- Android backup database files are not interchangeable with the native iOS JSON backup.

Previously removed Discord/integrations/donation/developer/inspiration sections are intentionally not restored.
