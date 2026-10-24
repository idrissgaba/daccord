// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'space_events.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's scheduled events that are coming up or under way, live first
/// then soonest first. Self-loads the first time it's watched and is kept in
/// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".

@ProviderFor(SpaceEventsController)
final spaceEventsControllerProvider = SpaceEventsControllerFamily._();

/// A space's scheduled events that are coming up or under way, live first
/// then soonest first. Self-loads the first time it's watched and is kept in
/// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".
final class SpaceEventsControllerProvider
    extends
        $NotifierProvider<SpaceEventsController, List<AccordScheduledEvent>?> {
  /// A space's scheduled events that are coming up or under way, live first
  /// then soonest first. Self-loads the first time it's watched and is kept in
  /// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".
  SpaceEventsControllerProvider._({
    required SpaceEventsControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'spaceEventsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spaceEventsControllerHash();

  @override
  String toString() {
    return r'spaceEventsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SpaceEventsController create() => SpaceEventsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordScheduledEvent>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordScheduledEvent>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpaceEventsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spaceEventsControllerHash() =>
    r'e55bcc47d2b7110eb52e5e99e3984e754050fbff';

/// A space's scheduled events that are coming up or under way, live first
/// then soonest first. Self-loads the first time it's watched and is kept in
/// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".

final class SpaceEventsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SpaceEventsController,
          List<AccordScheduledEvent>?,
          List<AccordScheduledEvent>?,
          List<AccordScheduledEvent>?,
          (String, String)
        > {
  SpaceEventsControllerFamily._()
    : super(
        retry: null,
        name: r'spaceEventsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's scheduled events that are coming up or under way, live first
  /// then soonest first. Self-loads the first time it's watched and is kept in
  /// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".

  SpaceEventsControllerProvider call(String serverKey, String spaceId) =>
      SpaceEventsControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'spaceEventsControllerProvider';
}

/// A space's scheduled events that are coming up or under way, live first
/// then soonest first. Self-loads the first time it's watched and is kept in
/// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".

abstract class _$SpaceEventsController
    extends $Notifier<List<AccordScheduledEvent>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  List<AccordScheduledEvent>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<List<AccordScheduledEvent>?, List<AccordScheduledEvent>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                List<AccordScheduledEvent>?,
                List<AccordScheduledEvent>?
              >,
              List<AccordScheduledEvent>?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
