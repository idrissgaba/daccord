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

## Features

| Feature | Branch | State | Main files |
|---|---|---|---|
| Per-participant volume ("User Volume", mute for me) | `feature/per-user-volume` | Deployed | `voice/views/user_volume_menu.dart`, `voice/services/voice_session.dart`, `voice/utils/voice_logic.dart`, `settings/models/accord_settings.dart`, `packages/livekit_client/lib/src/track/remote/audio.dart`, `packages/livekit_client/lib/src/track/web/_audio_*.dart` |
| Send the invite code when registering (invite-only servers) | `feature/invite-registration` | Deployed | `authentication/repositories/accord_auth.dart`, `authentication/views/accord_login.dart`, `server/views/add_server_dialog.dart` |
| Noise suppression / echo cancellation / auto gain toggles, high quality (128 kbps) mic | `feature/voice-audio-options` | Deployed | `voice/services/voice_session.dart`, `voice/utils/voice_logic.dart`, `voice/views/voice_settings_screen.dart` |
| Push-to-talk (rebindable key, hold-to-talk button) | `feature/push-to-talk` | Deployed | `voice/controllers/voice.dart`, `voice/services/voice_session.dart`, `voice/views/voice_bar.dart`, `voice/views/voice_settings_screen.dart` |
| Screen share: 4K, shared tab/screen audio, enabled in desktop browsers | `feature/screen-share-plus` | Deployed | `voice/services/voice_session.dart`, `voice/utils/audio_output_support.dart`, `voice/views/voice_bar.dart`, `voice/views/voice_view.dart` |
| Voice messages (record from the composer, sent as audio files) | `feature/voice-messages` | Deployed | `messaging/utils/voice_message.dart`, `messaging/views/voice_message_recorder.dart`, `messaging/views/message_pane/composer.dart`, `messaging/views/inline_audio_player.dart` (adds the `record` package) |
| Markdown: `-#` subtext and `<t:…>` dynamic timestamps | `feature/markdown-plus` | Deployed | `messaging/utils/message_timestamp.dart`, `messaging/views/box/accord_message_markup.dart` (adds `source_span`) |
| Message actions: forward, copy message link (`daccord://` links open in-app), mark unread | `feature/message-actions` | Deployed | `shared/utils/in_app_links.dart`, `messaging/utils/forward_message.dart`, `messaging/views/forward_message_dialog.dart`, `channels/controllers/read_state.dart`, `messaging/views/message_pane/message_row.dart` |
| Polls (create, vote, results, end early) | `feature/polls` | Deployed | `packages/accordkit/lib/src/models/poll.dart`, `messaging/utils/poll_display.dart`, `messaging/views/poll_view.dart`, `messaging/controllers/accord_messages.dart` |
| Voice moderation: server mute/deafen, move (menu or drag), disconnect, user limits | `feature/voice-moderation` | Deployed | `voice/views/voice_moderation_menu.dart`, `voice/controllers/voice.dart`, `voice/views/voice_participants.dart`, `voice/utils/voice_logic.dart` |

Paths are under `lib/features/` unless they start with `packages/`.

Notes:

- On the web, remote audio plays through `<audio>` elements, which cannot
  amplify: per-user volume stops at 100 % there (200 % on native builds).
  Upstream's `Helper.setVolume` had no effect on the web at all; the
  `RemoteAudioTrack.setVolume` added to the LiveKit fork fixes the global
  output volume there too.
- Shared screen audio comes from the browser (desktop Chrome/Edge). The native
  desktop app shares video only.
- Push-to-talk listens while the app has focus (no global OS hotkey).
- Polls, mark unread and voice moderation need the server fork; against an
  upstream server the poll button fails with the server's error and the
  moderation actions are refused.
- Voice moderation is enforced by the server in LiveKit; the client only
  reflects it (locked mic, icons) and follows moves.

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
