// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_extras.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// [userId]'s profile extras (pronouns, theme) and our private note about
/// them, fetched when a profile card opens. Null when the server doesn't
/// offer them.

@ProviderFor(profileExtras)
final profileExtrasProvider = ProfileExtrasFamily._();

/// [userId]'s profile extras (pronouns, theme) and our private note about
/// them, fetched when a profile card opens. Null when the server doesn't
/// offer them.

final class ProfileExtrasProvider
    extends
        $FunctionalProvider<
          AsyncValue<AccordProfileExtras?>,
          AccordProfileExtras?,
          FutureOr<AccordProfileExtras?>
        >
    with
        $FutureModifier<AccordProfileExtras?>,
        $FutureProvider<AccordProfileExtras?> {
  /// [userId]'s profile extras (pronouns, theme) and our private note about
  /// them, fetched when a profile card opens. Null when the server doesn't
  /// offer them.
  ProfileExtrasProvider._({
    required ProfileExtrasFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'profileExtrasProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$profileExtrasHash();

  @override
  String toString() {
    return r'profileExtrasProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AccordProfileExtras?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AccordProfileExtras?> create(Ref ref) {
    final argument = this.argument as (String, String);
    return profileExtras(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is ProfileExtrasProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$profileExtrasHash() => r'c0e46d4719fa5413987c153fc1d8e4c0d968466a';

/// [userId]'s profile extras (pronouns, theme) and our private note about
/// them, fetched when a profile card opens. Null when the server doesn't
/// offer them.

final class ProfileExtrasFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AccordProfileExtras?>,
          (String, String)
        > {
  ProfileExtrasFamily._()
    : super(
        retry: null,
        name: r'profileExtrasProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// [userId]'s profile extras (pronouns, theme) and our private note about
  /// them, fetched when a profile card opens. Null when the server doesn't
  /// offer them.

  ProfileExtrasProvider call(String serverKey, String userId) =>
      ProfileExtrasProvider._(argument: (serverKey, userId), from: this);

  @override
  String toString() => r'profileExtrasProvider';
}
