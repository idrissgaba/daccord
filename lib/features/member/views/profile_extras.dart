import 'package:bonfire/features/member/controllers/profile_extras.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A `0xRRGGBB` profile colour as an opaque [Color].
Color profileColor(int rgb) => Color(0xFF000000 | (rgb & 0xFFFFFF));

/// The colours offered for a profile theme.
const List<int> profileThemePalette = [
  0x5865F2,
  0x57F287,
  0xFEE75C,
  0xEB459E,
  0xED4245,
  0xF47B67,
  0x3BA55C,
  0x1ABC9C,
  0x3498DB,
  0x9B59B6,
  0x2C2F33,
  0x99AAB5,
];

/// The gradient band at the top of a profile card in the user's theme
/// colours (nothing when they haven't picked any).
class ProfileThemeBand extends ConsumerWidget {
  const ProfileThemeBand({
    super.key,
    required this.serverKey,
    required this.userId,
  });

  final String serverKey;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extras = ref
        .watch(profileExtrasProvider(serverKey, userId))
        .asData
        ?.value;
    if (extras == null || !extras.hasTheme) return const SizedBox.shrink();
    final primary = profileColor(extras.themePrimary ?? extras.themeAccent!);
    final accent = profileColor(extras.themeAccent ?? extras.themePrimary!);
    return Container(
      key: const Key('profile-theme-band'),
      height: 56,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(colors: [primary, accent]),
      ),
    );
  }
}

/// Pronouns, about me and — on someone else's card, outside streamer mode —
/// the private note we keep about them.
class ProfileExtrasSection extends ConsumerStatefulWidget {
  const ProfileExtrasSection({
    super.key,
    required this.serverKey,
    required this.userId,
    required this.isSelf,
    this.bio,
  });

  final String serverKey;
  final String userId;
  final bool isSelf;
  final String? bio;

  @override
  ConsumerState<ProfileExtrasSection> createState() =>
      _ProfileExtrasSectionState();
}

class _ProfileExtrasSectionState extends ConsumerState<ProfileExtrasSection> {
  final _note = TextEditingController();
  final _noteFocus = FocusNode();
  String? _savedNote;

  @override
  void initState() {
    super.initState();
    _noteFocus.addListener(() {
      if (!_noteFocus.hasFocus) _saveNote();
    });
  }

  @override
  void dispose() {
    _note.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    final note = _note.text.trim();
    if (note == (_savedNote ?? '')) return;
    final client = ref.accordClient;
    if (client == null) return;
    final result = await client.profiles.setNote(widget.userId, note);
    if (!mounted) return;
    if (result.ok) {
      _savedNote = note;
    } else {
      showInfoSnack(context, result.errorMessageOr('Could not save the note'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final extras = ref
        .watch(profileExtrasProvider(widget.serverKey, widget.userId))
        .asData
        ?.value;
    final streamer = ref.watch(
      settingsControllerProvider.select((s) => s.streamerMode),
    );
    if (extras != null && _savedNote == null) {
      _savedNote = extras.note ?? '';
      _note.text = _savedNote!;
    }
    final label = theme.textTheme.labelSmall!.copyWith(
      color: colors.gray,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    );
    final bio = widget.bio?.trim();
    return Column(
      key: const Key('profile-extras'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extras?.pronouns != null) ...[
          const SizedBox(height: 12),
          Text('PRONOUNS', style: label),
          const SizedBox(height: 2),
          Text(extras!.pronouns!, style: theme.textTheme.bodyMedium),
        ],
        if (bio != null && bio.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('ABOUT ME', style: label),
          const SizedBox(height: 2),
          Text(bio, style: theme.textTheme.bodyMedium),
        ],
        if (!widget.isSelf && extras != null && !streamer) ...[
          const SizedBox(height: 12),
          Text('NOTE', style: label),
          TextField(
            key: const Key('profile-note'),
            controller: _note,
            focusNode: _noteFocus,
            maxLength: 256,
            minLines: 1,
            maxLines: 3,
            onSubmitted: (_) => _saveNote(),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Click to add a note (only you see it)',
              counterText: '',
            ),
          ),
        ],
      ],
    );
  }
}

/// A purple strip while streamer mode is on, with a way to turn it off.
class StreamerModeBar extends ConsumerWidget {
  const StreamerModeBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      settingsControllerProvider.select((s) => s.streamerMode),
    );
    if (!on) return const SizedBox.shrink();
    return Material(
      key: const Key('streamer-mode-bar'),
      color: const Color(0xFF593695),
      child: InkWell(
        onTap: () => ref
            .read(settingsControllerProvider.notifier)
            .setStreamerMode(false),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.videocam, size: 16, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Streamer mode is on',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Text(
                'Turn off',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
