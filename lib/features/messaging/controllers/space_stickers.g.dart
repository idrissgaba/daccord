// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'space_stickers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's stickers. Self-loads the first time it's watched and is kept in
/// sync by `sticker.*` gateway events. `null` means "not loaded yet".

@ProviderFor(SpaceStickersController)
final spaceStickersControllerProvider = SpaceStickersControllerFamily._();

/// A space's stickers. Self-loads the first time it's watched and is kept in
/// sync by `sticker.*` gateway events. `null` means "not loaded yet".
final class SpaceStickersControllerProvider
    extends $NotifierProvider<SpaceStickersController, List<AccordSticker>?> {
  /// A space's stickers. Self-loads the first time it's watched and is kept in
  /// sync by `sticker.*` gateway events. `null` means "not loaded yet".
  SpaceStickersControllerProvider._({
    required SpaceStickersControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'spaceStickersControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spaceStickersControllerHash();

  @override
  String toString() {
    return r'spaceStickersControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SpaceStickersController create() => SpaceStickersController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordSticker>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordSticker>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpaceStickersControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spaceStickersControllerHash() =>
    r'7d22783bfdd0edf200560458c3e78dbd0ade5ee1';

/// A space's stickers. Self-loads the first time it's watched and is kept in
/// sync by `sticker.*` gateway events. `null` means "not loaded yet".

final class SpaceStickersControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SpaceStickersController,
          List<AccordSticker>?,
          List<AccordSticker>?,
          List<AccordSticker>?,
          (String, String)
        > {
  SpaceStickersControllerFamily._()
    : super(
        retry: null,
        name: r'spaceStickersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's stickers. Self-loads the first time it's watched and is kept in
  /// sync by `sticker.*` gateway events. `null` means "not loaded yet".

  SpaceStickersControllerProvider call(String serverKey, String spaceId) =>
      SpaceStickersControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'spaceStickersControllerProvider';
}

/// A space's stickers. Self-loads the first time it's watched and is kept in
/// sync by `sticker.*` gateway events. `null` means "not loaded yet".

abstract class _$SpaceStickersController
    extends $Notifier<List<AccordSticker>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  List<AccordSticker>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<AccordSticker>?, List<AccordSticker>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordSticker>?, List<AccordSticker>?>,
              List<AccordSticker>?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
