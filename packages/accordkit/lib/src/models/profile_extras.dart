import '../utils/json_utils.dart';

/// The extras of a user's profile — pronouns and a two-colour theme — and,
/// when someone else's, the private [note] the signed-in user keeps about
/// them.
class AccordProfileExtras {
  AccordProfileExtras({
    required this.userId,
    this.pronouns,
    this.themePrimary,
    this.themeAccent,
    this.note,
  });

  final String userId;
  final String? pronouns;

  /// `0xRRGGBB`.
  final int? themePrimary;
  final int? themeAccent;
  final String? note;

  bool get hasTheme => themePrimary != null || themeAccent != null;

  factory AccordProfileExtras.fromJson(Map<String, dynamic> d) =>
      AccordProfileExtras(
        userId: asString(d['user_id']),
        pronouns: asStringOrNull(d['pronouns']),
        themePrimary:
            d['theme_primary'] is int ? d['theme_primary'] as int : null,
        themeAccent: d['theme_accent'] is int ? d['theme_accent'] as int : null,
        note: asStringOrNull(d['note']),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'pronouns': pronouns,
        'theme_primary': themePrimary,
        'theme_accent': themeAccent,
        if (note != null) 'note': note,
      };
}
