import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/settings/models/custom_keybind.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:bonfire/features/spaces/views/quick_switcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AccordChannel _channel(String id, {String type = 'text', String? parent}) =>
    AccordChannel.fromJson({
      'id': id,
      'name': id,
      'type': type,
      if (parent != null) 'parent_id': parent,
    });

void main() {
  group('matchHomeShortcut', () {
    test('maps the chords users know from other chat apps', () {
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
        ),
        HomeShortcut.quickSwitcher,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.arrowDown,
          control: false,
          shift: false,
          alt: true,
        ),
        HomeShortcut.nextChannel,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.arrowUp,
          control: true,
          shift: false,
          alt: true,
        ),
        HomeShortcut.previousSpace,
      );
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyM,
          control: true,
          shift: true,
          alt: false,
        ),
        HomeShortcut.toggleMute,
      );
    });

    test('a plain or differently modified key is nobody\'s shortcut', () {
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: false,
          shift: false,
          alt: false,
        ),
        isNull,
      );
      // Ctrl+Shift+K is not Ctrl+K: typing must never jump channels.
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: true,
          alt: false,
        ),
        isNull,
      );
    });

    test('describe prints the chord the dialog shows', () {
      final mute = homeShortcutBindings.firstWhere(
        (b) => b.shortcut == HomeShortcut.toggleMute,
      );
      expect(mute.describe(), 'Ctrl+Shift+M');
      expect(mute.describe(mac: true), '⌘+⇧+M');
      final up = homeShortcutBindings.firstWhere(
        (b) => b.shortcut == HomeShortcut.previousChannel,
      );
      expect(up.describe(), 'Alt+↑');
    });
  });

  group('custom keybinds', () {
    test('a recorded keybind triggers its action and wins over a built-in', () {
      final custom = [
        CustomKeybind(
          action: HomeShortcut.toggleMute.name,
          keyId: LogicalKeyboardKey.keyK.keyId,
          keyLabel: 'K',
          control: true,
        ),
      ];
      // Ctrl+K is the built-in quick switcher; the user bound it to mute.
      expect(
        matchHomeShortcut(
          pressed: LogicalKeyboardKey.keyK,
          control: true,
          shift: false,
          alt: false,
          custom: custom,
        ),
        HomeShortcut.toggleMute,
      );
      expect(
        effectiveBindings(custom).first.describe(),
        'Ctrl+K',
      );
    });

    test('an unrecorded or unknown keybind is ignored', () {
      final custom = [
        CustomKeybind(action: HomeShortcut.toggleMute.name),
        const CustomKeybind(action: 'no-such-action', keyId: 0x61),
      ];
      expect(effectiveBindings(custom).length, homeShortcutBindings.length);
    });

    test('round-trips through json', () {
      const keybind = CustomKeybind(
        action: 'nextChannel',
        keyId: 0x100000301,
        keyLabel: '↓',
        alt: true,
      );
      expect(CustomKeybind.fromJson(keybind.toJson()), keybind);
    });
  });

  group('orderedNavigableChannelIds', () {
    test('walks the list the way the sidebar draws it, skipping categories', () {
      final channels = [
        _channel('cat-a', type: 'category'),
        _channel('a1', parent: 'cat-a'),
        _channel('loose'),
        _channel('cat-b', type: 'category'),
        _channel('b1', type: 'voice', parent: 'cat-b'),
        _channel('a2', parent: 'cat-a'),
      ];
      expect(orderedNavigableChannelIds(channels), [
        'loose',
        'a1',
        'a2',
        'b1',
      ]);
    });
  });

  group('adjacentId', () {
    test('steps forward and back, wrapping at the ends', () {
      const ids = ['a', 'b', 'c'];
      expect(adjacentId(ids, 'a', forward: true), 'b');
      expect(adjacentId(ids, 'c', forward: true), 'a');
      expect(adjacentId(ids, 'a', forward: false), 'c');
    });

    test('starts from an end when nothing is current', () {
      const ids = ['a', 'b'];
      expect(adjacentId(ids, null, forward: true), 'a');
      expect(adjacentId(ids, 'zz', forward: false), 'b');
      expect(adjacentId(const [], 'a', forward: true), isNull);
    });
  });

  group('orderBySavedOrder', () {
    test('saved order first, then the rest as given', () {
      expect(orderBySavedOrder(['x', 'y', 'z'], ['z', 'gone', 'x']), [
        'z',
        'x',
        'y',
      ]);
    });
  });

  group('filterQuickSwitchEntries', () {
    final entries = [
      QuickSwitchEntry(
        spaceId: 's1',
        spaceName: 'Maison',
        channel: _channel('general'),
      ),
      QuickSwitchEntry(
        spaceId: 's1',
        spaceName: 'Maison',
        channel: _channel('chill', type: 'voice'),
      ),
      QuickSwitchEntry(
        spaceId: 's2',
        spaceName: 'Gaming',
        channel: _channel('general-chat'),
      ),
    ];

    test('prefix matches rank before substring and space-name matches', () {
      final names = filterQuickSwitchEntries(
        entries,
        'gen',
      ).map((e) => e.channelName).toList();
      expect(names, ['general', 'general-chat']);
      final bySpace = filterQuickSwitchEntries(
        entries,
        'gam',
      ).map((e) => e.channelName).toList();
      expect(bySpace, ['general-chat']);
    });

    test('an empty query lists everything, capped', () {
      expect(filterQuickSwitchEntries(entries, '  ').length, 3);
      expect(filterQuickSwitchEntries(entries, '', limit: 2).length, 2);
    });
  });
}
