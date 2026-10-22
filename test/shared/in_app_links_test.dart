import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/shared/utils/in_app_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => InAppLinks.unregister(_record));

  test('messageLink round-trips through the deep-link parser', () {
    final link = messageLink(spaceId: '11', channelId: '22', messageId: '33');
    expect(link, 'daccord://navigate/11/22?msg=33');
    final parsed = ServerUri.parseDeepLink(link)!;
    expect(parsed.route, 'navigate');
    expect(parsed.spaceId, '11');
    expect(parsed.channelId, '22');
    expect(parsed.messageId, '33');
  });

  test('daccord:// links open in the app once a handler is installed', () {
    expect(InAppLinks.open('daccord://navigate/1/2?msg=3'), isFalse);
    InAppLinks.register(_record);
    expect(InAppLinks.open('daccord://navigate/1/2?msg=3'), isTrue);
    expect(_opened.last.toString(), 'daccord://navigate/1/2?msg=3');
  });

  test('other links are left to the external opener', () {
    InAppLinks.register(_record);
    expect(InAppLinks.open('https://example.com'), isFalse);
  });

  test('unregistering another handler keeps the installed one', () {
    InAppLinks.register(_record);
    InAppLinks.unregister(_other);
    expect(InAppLinks.open('daccord://navigate/1'), isTrue);
  });
}

final _opened = <Uri>[];
void _record(Uri uri) => _opened.add(uri);
void _other(Uri uri) {}
