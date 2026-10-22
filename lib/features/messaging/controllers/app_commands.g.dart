// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_commands.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The slash commands members of a space can use: those of the bots that are
/// members there. Self-loads the first time it's watched and reloads on an
/// `application_commands.update` gateway event. `null` means "not loaded
/// yet".

@ProviderFor(SpaceCommandsController)
final spaceCommandsControllerProvider = SpaceCommandsControllerFamily._();

/// The slash commands members of a space can use: those of the bots that are
/// members there. Self-loads the first time it's watched and reloads on an
/// `application_commands.update` gateway event. `null` means "not loaded
/// yet".
final class SpaceCommandsControllerProvider
    extends $NotifierProvider<SpaceCommandsController, List<AccordCommand>?> {
  /// The slash commands members of a space can use: those of the bots that are
  /// members there. Self-loads the first time it's watched and reloads on an
  /// `application_commands.update` gateway event. `null` means "not loaded
  /// yet".
  SpaceCommandsControllerProvider._({
    required SpaceCommandsControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'spaceCommandsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spaceCommandsControllerHash();

  @override
  String toString() {
    return r'spaceCommandsControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  SpaceCommandsController create() => SpaceCommandsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordCommand>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordCommand>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpaceCommandsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spaceCommandsControllerHash() =>
    r'b37cd2422b68b7b347e610d6180cfe6b6ed9974e';

/// The slash commands members of a space can use: those of the bots that are
/// members there. Self-loads the first time it's watched and reloads on an
/// `application_commands.update` gateway event. `null` means "not loaded
/// yet".

final class SpaceCommandsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SpaceCommandsController,
          List<AccordCommand>?,
          List<AccordCommand>?,
          List<AccordCommand>?,
          (String, String)
        > {
  SpaceCommandsControllerFamily._()
    : super(
        retry: null,
        name: r'spaceCommandsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The slash commands members of a space can use: those of the bots that are
  /// members there. Self-loads the first time it's watched and reloads on an
  /// `application_commands.update` gateway event. `null` means "not loaded
  /// yet".

  SpaceCommandsControllerProvider call(String serverKey, String spaceId) =>
      SpaceCommandsControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'spaceCommandsControllerProvider';
}

/// The slash commands members of a space can use: those of the bots that are
/// members there. Self-loads the first time it's watched and reloads on an
/// `application_commands.update` gateway event. `null` means "not loaded
/// yet".

abstract class _$SpaceCommandsController
    extends $Notifier<List<AccordCommand>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  List<AccordCommand>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<AccordCommand>?, List<AccordCommand>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordCommand>?, List<AccordCommand>?>,
              List<AccordCommand>?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Interactions waiting for their application, keyed by interaction id. One
/// that gets no `interaction.success` within [interactionTimeout] turns
/// [PendingInteraction.failed] for a few seconds, then disappears.

@ProviderFor(InteractionTracker)
final interactionTrackerProvider = InteractionTrackerProvider._();

/// Interactions waiting for their application, keyed by interaction id. One
/// that gets no `interaction.success` within [interactionTimeout] turns
/// [PendingInteraction.failed] for a few seconds, then disappears.
final class InteractionTrackerProvider
    extends
        $NotifierProvider<InteractionTracker, Map<String, PendingInteraction>> {
  /// Interactions waiting for their application, keyed by interaction id. One
  /// that gets no `interaction.success` within [interactionTimeout] turns
  /// [PendingInteraction.failed] for a few seconds, then disappears.
  InteractionTrackerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'interactionTrackerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$interactionTrackerHash();

  @$internal
  @override
  InteractionTracker create() => InteractionTracker();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, PendingInteraction> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, PendingInteraction>>(
        value,
      ),
    );
  }
}

String _$interactionTrackerHash() =>
    r'7455b76d0c6fc2ce2a7a830ec6a8c3aef9caa450';

/// Interactions waiting for their application, keyed by interaction id. One
/// that gets no `interaction.success` within [interactionTimeout] turns
/// [PendingInteraction.failed] for a few seconds, then disappears.

abstract class _$InteractionTracker
    extends $Notifier<Map<String, PendingInteraction>> {
  Map<String, PendingInteraction> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              Map<String, PendingInteraction>,
              Map<String, PendingInteraction>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, PendingInteraction>,
                Map<String, PendingInteraction>
              >,
              Map<String, PendingInteraction>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
