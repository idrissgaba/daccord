# Fork changes (idrissgaba/daccord)

Personal fork of [DaccordProject/daccord](https://github.com/DaccordProject/daccord)
(GPL-3.0, credit to the Daccord project and to Bonfire, which it forks), built as
the web client of a private, invite-only server running the server fork
[idrissgaba/accordserver](https://github.com/idrissgaba/accordserver).

Features reproduce common chat-app conveniences with this project's own code,
Material icons and existing sounds; no third-party brand assets are used.

## Branches

| Branch | Purpose |
|---|---|
| `master` | Mirror of upstream `master` — never commit here |
| `feature/<name>` | One feature per branch, based on `master` |
| `idris/main` | Integration branch that is built and deployed: `master` + every feature branch merged |

`fix/windows-single-instance`, `fix/screen-share-cancel`, `feature/keyboard-shortcuts`, `feature/keybinds-page` and `feature/voice-quality` are based on `idris/main` rather than `master`: they change files every other branch already touches (the composer, the home screen, the voice controller), so they re-merge with `idris/main` and are skipped by the per-branch `git rebase master` step below.

## Features

| Feature | Branch | State | Main files |
|---|---|---|---|
| Per-participant volume ("User Volume", mute for me) | `feature/per-user-volume` | Deployed | `voice/views/user_volume_menu.dart`, `voice/services/voice_session.dart`, `voice/utils/voice_logic.dart`, `settings/models/accord_settings.dart`, `packages/livekit_client/lib/src/track/remote/audio.dart`, `packages/livekit_client/lib/src/track/web/_audio_*.dart` |
| Send the invite code when registering (invite-only servers) | `feature/invite-registration` | Deployed | `authentication/repositories/accord_auth.dart`, `authentication/views/accord_login.dart`, `server/views/add_server_dialog.dart` |
| Noise suppression / echo cancellation / auto gain toggles, high quality (128 kbps) mic | `feature/voice-audio-options` | Deployed | `voice/services/voice_session.dart`, `voice/utils/voice_logic.dart`, `voice/views/voice_settings_screen.dart` |
| Push-to-talk (rebindable key, hold-to-talk button) | `feature/push-to-talk` | Deployed | `voice/controllers/voice.dart`, `voice/services/voice_session.dart`, `voice/views/voice_bar.dart`, `voice/views/voice_settings_screen.dart` |
| Push-to-talk outside the app (Windows desktop) | `feature/global-ptt` | Built | `voice/services/global_key_watcher*.dart`, `voice/controllers/voice.dart`, `voice/views/voice_settings_screen.dart` (adds `win32` as a direct dependency) |
| Updates come from this fork's releases (never upstream's) | `feature/fork-updates` | Built | `shared/app_info.dart` (`kUpdateRepo`) |
| Android app: own application id `com.idrissgaba.daccord` (installs beside the official app), screen share on Android 14+ (mediaProjection foreground service via `flutter_background`) | `feature/android-app` | Built | `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml`, `voice/services/android_screen_capture.dart`, `voice/services/voice_session.dart` |
| Fix: hidden spoilers were invisible (same colour as the pane) | `fix/visible-spoilers` | Built | `messaging/views/box/accord_message_markup.dart` |
| Screen share: 4K, shared tab/screen audio, enabled in desktop browsers | `feature/screen-share-plus` | Deployed | `voice/services/voice_session.dart`, `voice/utils/audio_output_support.dart`, `voice/views/voice_bar.dart`, `voice/views/voice_view.dart` |
| Voice messages (record from the composer, sent as audio files) | `feature/voice-messages` | Deployed | `messaging/utils/voice_message.dart`, `messaging/views/voice_message_recorder.dart`, `messaging/views/message_pane/composer.dart`, `messaging/views/inline_audio_player.dart` (adds the `record` package) |
| Markdown: `-#` subtext and `<t:…>` dynamic timestamps | `feature/markdown-plus` | Deployed | `messaging/utils/message_timestamp.dart`, `messaging/views/box/accord_message_markup.dart` (adds `source_span`) |
| Message actions: forward, copy message link (`daccord://` links open in-app), mark unread | `feature/message-actions` | Deployed | `shared/utils/in_app_links.dart`, `messaging/utils/forward_message.dart`, `messaging/views/forward_message_dialog.dart`, `channels/controllers/read_state.dart`, `messaging/views/message_pane/message_row.dart` |
| Polls (create, vote, results, end early) | `feature/polls` | Deployed | `packages/accordkit/lib/src/models/poll.dart`, `messaging/utils/poll_display.dart`, `messaging/views/poll_view.dart`, `messaging/controllers/accord_messages.dart` |
| Voice moderation: server mute/deafen, move (menu or drag), disconnect, user limits | `feature/voice-moderation` | Deployed | `voice/views/voice_moderation_menu.dart`, `voice/controllers/voice.dart`, `voice/views/voice_participants.dart`, `voice/utils/voice_logic.dart` |
| Webhooks management, APP badge, per-message webhook names | `feature/webhooks` | Deployed | `spaces/views/accord_webhooks.dart`, `packages/accordkit/lib/src/models/webhook.dart`, `packages/accordkit/lib/src/rest/endpoints/webhooks_api.dart`, `messaging/views/message_author_header.dart` |
| Slash commands, bot buttons and menus, ephemeral and "thinking…" answers | `feature/interactions` | Deployed | `messaging/views/command_picker.dart`, `messaging/views/message_components.dart`, `messaging/controllers/app_commands.dart`, `messaging/utils/interaction_logic.dart`, `packages/accordkit/lib/src/models/command.dart`, `packages/accordkit/lib/src/rest/endpoints/interactions_api.dart` |
| Scheduled events (list, create, interested, live banner, `.ics` export, start notification) | `feature/scheduled-events` | Deployed | `spaces/views/space_events.dart`, `spaces/controllers/space_events.dart`, `spaces/utils/event_logic.dart`, `packages/accordkit/lib/src/models/scheduled_event.dart`, `packages/accordkit/lib/src/rest/endpoints/events_api.dart` |
| Stickers (picker, send, manage per space) | `feature/stickers` | Deployed | `messaging/views/stickers.dart`, `messaging/controllers/space_stickers.dart`, `messaging/views/message_pane/composer.dart`, `packages/accordkit/lib/src/models/sticker.dart`, `packages/accordkit/lib/src/rest/endpoints/stickers_api.dart` |
| Profile extras: pronouns, profile theme colours, private notes, streamer mode | `feature/profile-extras` | Deployed | `member/views/profile_extras.dart`, `member/controllers/profile_extras.dart`, `settings/models/accord_settings.dart`, `packages/accordkit/lib/src/models/profile_extras.dart`, `packages/accordkit/lib/src/rest/endpoints/profiles_api.dart` |
| Welcome screen (shown once per space, editor in space settings) | `feature/welcome-screen` | Deployed | `spaces/views/welcome_screen.dart`, `settings/models/accord_settings.dart`, `packages/accordkit/lib/src/models/welcome_screen.dart`, `packages/accordkit/lib/src/rest/endpoints/welcome_screen_api.dart` |
| Stage channels (audience, raise hand, invite to speak) | `feature/stage-channels` | Deployed | `voice/views/stage_view.dart`, `voice/utils/stage_logic.dart`, `voice/views/voice_view.dart`, `voice/views/voice_moderation_menu.dart`, `packages/accordkit/lib/src/models/voice_state.dart` |
| Super reactions (glowing, animated, unlimited) | `feature/super-reactions` | Deployed | `messaging/views/message_pane/reactions.dart`, `messaging/views/message_pane/message_row.dart`, `messaging/controllers/accord_messages.dart`, `events/services/accord_message_events.dart`, `packages/accordkit/lib/src/models/reaction.dart`, `packages/accordkit/lib/src/rest/endpoints/reactions_api.dart` |
| Keyboard shortcuts: Ctrl+K quick switcher, Alt+↑/↓ channels, Ctrl+Alt+↑/↓ spaces, Ctrl+Shift+M/D mute/deafen, Ctrl+U members, Ctrl+, settings, Ctrl+/ list (also in Settings › App); ↑ edits your last message, Escape cancels a reply/edit, Tab/Enter and ↑/↓ drive the @mention list | `feature/keyboard-shortcuts` | Deployed | `spaces/utils/home_shortcuts.dart`, `spaces/views/quick_switcher.dart`, `spaces/views/keyboard_shortcuts_dialog.dart`, `spaces/views/accord_home.dart`, `messaging/views/message_pane/composer.dart`, `messaging/views/message_pane/mention_popup.dart`, `messaging/views/message_pane/message_row.dart`, `docs/troubleshooting/keyboard-shortcuts.md` |
| Keybinds page (Settings › Keybinds): add a keybind, pick its action, record your own chord, remove it; every built-in chord can be re-recorded, removed or restored; the Ctrl+/ list shows what is in force | `feature/keybinds-page` | Deployed | `settings/models/custom_keybind.dart`, `settings/views/keybinds_section.dart`, `settings/models/accord_settings.dart`, `spaces/utils/home_shortcuts.dart`, `spaces/views/keyboard_shortcuts_dialog.dart` |
| Voice at 96 kbps Opus without DTX by default (DTX clipped the first syllable after each pause); high quality is 128 kbps mono with RED | `feature/voice-quality` | Deployed | `voice/utils/voice_logic.dart` |
| Threads in a side panel, profile popouts beside the click, space menu under the space name (create category, mark as read, leave…), one-click voice join on desktop, live tab names, plain previews, visible inline code, colour emoji fallback, Escape closes settings | `feature/discord-polish` | Deployed | `messaging/views/thread_view.dart`, `member/views/accord_member_popout.dart`, `spaces/views/accord_home*.dart`, `messaging/utils/message_display.dart`, `shared/components/escape_to_close.dart`, `shared/components/settings_scaffold.dart`, `theme/app_theme.dart` |
| Fixes from the 2026-10-28 QA (`docs/qa/`): one Windows instance (a second launch restores the running window and forwards its `daccord://` link), Shift+Enter breaks the line on the web, Enter saves / Escape cancels an inline edit, a cancelled screen-share prompt no longer shows a phantom share, Reply focuses the composer, DM placeholder reads "Message @name" | `fix/qa-2026-10-28` | Deployed | `windows/runner/main.cpp`, `windows/runner/CMakeLists.txt`, `messaging/views/message_pane/composer.dart`, `messaging/views/message_pane/message_row.dart`, `messaging/views/message_pane/message_pane.dart`, `voice/controllers/voice.dart`, `voice/services/voice_session.dart`, `user/views/accord_direct_messages_conversations.dart` |
| Stream volume for viewers (its own slider and "Mute stream" from a Volume button on a watched stream, or right-click/long-press), apart from the streamer's voice volume | `feature/stream-volume` | Deployed | `voice/views/user_volume_menu.dart`, `voice/views/voice_view/video_grid.dart`, `voice/services/voice_session.dart`, `voice/utils/voice_logic.dart` |
| Mute/deafen keybinds outside the app (Windows desktop, during a call) | `feature/global-voice-keybinds` | Deployed | `voice/services/global_key_watcher.dart`, `voice/controllers/voice_push_to_talk.dart`, `spaces/utils/home_shortcuts.dart`, `spaces/views/accord_home_navigation.dart` |
| Fix: starting a screen share froze Android phones (the app previewed its own capture, filming itself, and the full-panel capture was encoded unscaled) | `fix/android-screen-share` | Deployed | `voice/views/voice_view/video_grid.dart`, `voice/views/voice_pip_overlay.dart`, `voice/services/voice_session.dart`, `voice/services/android_screen_capture.dart` |

| Discord-style interface sounds (rounder mallet notes, reverb tail, melodic ringtones), all synthesized by `tool/make_sfx.py` | `feature/sounds-v2` | Deployed | `assets/sfx/*.wav`, `tool/make_sfx.py` |
| Emoji: the whole Unicode catalogue (generated, 1 900 emoji, skin tones), a desktop popover beside the button with category rail / continuous grid / preview bar, `:shortcode:` autocomplete in the composer, Ctrl+E, default skin tone setting | `feature/emoji-picker` | Deployed | `messaging/views/emoji_picker.dart`, `messaging/views/emoji_picker/panel.dart`, `messaging/views/message_pane/composer_emoji.dart`, `messaging/utils/emoji_catalog*.dart`, `tool/make_emoji_catalog.py`, `tool/emoji_shortnames.py` |
| Search filters `from:` `in:` `before:` `after:` `pinned:`; channel and date on each hit; search hits and pins jump to the message in place (highlighted) | `feature/search-filters` | Deployed | `spaces/utils/search_query.dart`, `spaces/views/accord_search.dart`, `messaging/controllers/message_jump.dart`, `messaging/views/message_pane/message_pane.dart` |
| "X pinned a message" system message (server fork `feature/pin-system-message`, type `pin`, references the pinned message), pinned list with timestamps and Jump | `feature/pin-messages` | Deployed | `messaging/views/pinned_messages.dart`, `messaging/utils/message_display.dart` |
| Delete dialog with a preview of the message and Shift to skip it; Voice Connected card (status + channel/space, camera, screen, soundboard, disconnect) with mute/deafen in the user panel; tighter grouped messages; floating hover bar on the row edge; Events row no longer stays lit; web address bar follows the open channel (refresh, share, Back) | `feature/discord-polish-2` | Deployed | `messaging/views/message_pane/message_row*.dart`, `voice/views/voice_bar.dart`, `spaces/views/space_events.dart`, `spaces/views/accord_home.dart` |
| Settings laid out like Discord: My Account, Privacy & Safety, Connections, Appearance, Accessibility (reduced motion, UI scale, saturation), Voice & Video, Text & Images (embeds, emoticons, skin tone), Notifications (with one switch and a listen button per sound), Keybinds, Streamer Mode, Advanced, System, About | `feature/settings-layout` | Deployed | `settings/views/accord_settings_screen.dart`, `settings/views/settings_screen/sections.dart`, `notifications/services/sound.dart`, `shared/components/app_shell.dart` |
Paths are under `lib/features/` unless they start with `packages/`.

Notes:

- On the web, remote audio plays through `<audio>` elements, which cannot
  amplify: per-user volume stops at 100 % there (200 % on native builds).
  Upstream's `Helper.setVolume` had no effect on the web at all; the
  `RemoteAudioTrack.setVolume` added to the LiveKit fork fixes the global
  output volume there too.
- Shared screen audio comes from the browser (desktop Chrome/Edge). The native
  desktop app shares video only.
- Push-to-talk works while another app has focus in the Windows desktop app
  (`feature/global-ptt`, polling `GetAsyncKeyState` through `win32` every
  15 ms during a call); elsewhere it listens while the app has focus. The
  mute and deafen keybinds are watched the same way during a call
  (`feature/global-voice-keybinds`); other keybinds need the app focused.
- Android captures the whole screen at its native size whatever resolution
  is chosen; the encoder scales it down to the chosen one. Phones show a
  "You're sharing your screen" card instead of previewing their own share.
- Events, stickers, profile extras, the welcome screen, stages and super
  reactions need the
  server fork too; against an upstream server those panels stay empty or report
  the server's error.
- Polls, mark unread and voice moderation need the server fork; against an
  upstream server the poll button fails with the server's error and the
  moderation actions are refused.
- Voice moderation is enforced by the server in LiveKit; the client only
  reflects it (locked mic, icons) and follows moves.

## Android release signing

Release APKs are signed with the fork's own key, kept outside the repository
(`%USERPROFILE%\.daccord-signing\`, mirrored into the untracked
`android/key.properties`). Losing it means existing installs can't update — keep
a copy in the password manager. Build: `flutter build apk --release --flavor
github --split-per-abi`.

## Building and deploying

Pinned Flutter: `.fvmrc` (currently 3.48.0-0.5.pre).

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --no-tree-shake-icons --release
```

The built `build/web` replaces the files served by the `daccord-web`
container; see `/srv/data/stack/daccord/README.md` on the server.

## Updating from upstream

```bash
git fetch upstream
git checkout master && git merge --ff-only upstream/master && git push origin master
for b in $(git branch --format='%(refname:short)' --list 'feature/*'); do
  git checkout "$b" && git rebase master   # fix conflicts, flutter test
done
git checkout idris/main && git reset --hard master
for b in $(git branch --format='%(refname:short)' --list 'feature/*'); do git merge --no-ff "$b"; done
flutter analyze --no-fatal-infos && flutter test
git push --force-with-lease origin idris/main 'feature/*' master
```

The voice feature branches touch the same files (`voice_session.dart`,
`voice.dart`, `accord_settings.dart`); their conflicts in `idris/main` are
always "keep both sides".
