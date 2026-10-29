import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The long side, in pixels, of what Android's screen capture produces: the
/// whole display at its native size. Null elsewhere, where capture honours
/// the requested resolution.
int? get androidCaptureLongSide {
  if (!_isAndroid) return null;
  final displays = PlatformDispatcher.instance.displays;
  if (displays.isEmpty) return null;
  final size = displays.first.size;
  return math.max(size.width, size.height).round();
}

/// Gets Android ready to capture the screen: the user's consent for this
/// session, then the mediaProjection foreground service Android 14+ requires
/// while capturing (the order LiveKit's Flutter example uses). True when the
/// share may start; always true elsewhere.
Future<bool> prepareScreenCapture() async {
  if (!_isAndroid) return true;
  if (!await rtc.Helper.requestCapturePermission()) return false;
  var ready = await FlutterBackground.initialize(
    androidConfig: const FlutterBackgroundAndroidConfig(
      notificationTitle: 'Daccord',
      notificationText: 'You are sharing your screen.',
      notificationImportance: AndroidNotificationImportance.normal,
      notificationIcon: AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
    ),
  );
  if (ready && !FlutterBackground.isBackgroundExecutionEnabled) {
    ready = await FlutterBackground.enableBackgroundExecution();
  }
  return ready;
}

/// Stops the capture service once the share has ended.
Future<void> releaseScreenCapture() async {
  if (!_isAndroid || !FlutterBackground.isBackgroundExecutionEnabled) return;
  await FlutterBackground.disableBackgroundExecution();
}
