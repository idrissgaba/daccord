import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
  @override
  void setScreenShareResolution(int index) =>
      state = state.copyWith(screenShareResolution: index);
  @override
  void setScreenShareFps(int fps) =>
      state = state.copyWith(screenShareFps: fps);
}

void main() {
  testWidgets('the share dialog picks resolution and frame rate', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [settingsControllerProvider.overrideWith(_Settings.new)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(body: ShareQualityRow()),
        ),
      ),
    );
    for (final label in ['480p', '720p', '1080p']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('480p'));
    await tester.tap(find.text('30'));
    await tester.pump();
    final s = container.read(settingsControllerProvider);
    expect(s.screenShareDimensions, (854, 480));
    expect(s.screenShareFps, 30);
  });
}
