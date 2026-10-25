import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';

/// Whether closing the window hides it to the system tray (the default)
/// instead of quitting. Kept in step with the `closeToTray` setting by
/// `SettingsController`.
bool desktopCloseToTray = true;

bool get _hasTray =>
    !kIsWeb && (UniversalPlatform.isWindows || UniversalPlatform.isLinux);

const _menuOpen = 'open';
const _menuQuit = 'quit';

/// Puts Daccord in the system tray: the close button hides the window (while
/// [desktopCloseToTray]), clicking the tray icon brings it back, and the
/// tray menu's Quit really exits. Call after `setupDesktopWindow`.
Future<void> setupDesktopTray() async {
  if (!_hasTray) return;
  await trayManager.setIcon(
    UniversalPlatform.isWindows
        ? 'assets/images/tray.ico'
        : 'assets/images/tray.png',
  );
  if (!UniversalPlatform.isLinux) await trayManager.setToolTip('Daccord');
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: _menuOpen, label: 'Open Daccord'),
        MenuItem.separator(),
        MenuItem(key: _menuQuit, label: 'Quit Daccord'),
      ],
    ),
  );
  final handler = _TrayHandler();
  trayManager.addListener(handler);
  windowManager.addListener(handler);
  await windowManager.setPreventClose(true);
}

Future<void> _showWindow() async {
  await windowManager.show();
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.focus();
}

Future<void> _quit() async {
  await trayManager.destroy();
  await windowManager.setPreventClose(false);
  await windowManager.close();
}

class _TrayHandler with TrayListener, WindowListener {
  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _menuOpen:
        _showWindow();
      case _menuQuit:
        _quit();
    }
  }

  @override
  void onWindowClose() {
    if (desktopCloseToTray) {
      windowManager.hide();
    } else {
      _quit();
    }
  }
}
