import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_extras.g.dart';

/// [userId]'s profile extras (pronouns, theme) and our private note about
/// them, fetched when a profile card opens. Null when the server doesn't
/// offer them.
@riverpod
Future<AccordProfileExtras?> profileExtras(
  Ref ref,
  String serverKey,
  String userId,
) async {
  final client = ref.watchAccordClientFor(serverKey);
  if (client == null) return null;
  final result = await client.profiles.get(userId);
  final data = result.data;
  return result.ok && data is AccordProfileExtras ? data : null;
}
