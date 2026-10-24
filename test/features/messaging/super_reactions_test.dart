import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('messages carry super reactions apart from plain ones', () {
    final message = AccordMessage.fromJson({
      'id': 'm1',
      'channel_id': 'c1',
      'content': 'hi',
      'reactions': [
        {'emoji': '🔥', 'count': 1, 'me': false},
      ],
      'super_reactions': [
        {'emoji': '🔥', 'count': 2, 'me': true},
      ],
    });
    expect(message.reactions!.single.count, 1);
    expect(message.superReactions.single.count, 2);
    expect(message.superReactions.single.me, isTrue);
    expect(
      AccordMessage.fromJson(message.toJson()).superReactions.single.emoji,
      '🔥',
    );
  });

  test('a change adds, counts, ignores our own echo and removes', () {
    final added = applySuperReactionChange(
      null,
      '🔥',
      added: true,
      isOwn: true,
    )!;
    expect((added.count, added.me), (1, true));
    // Our own gateway echo after the optimistic add.
    expect(
      identical(
        applySuperReactionChange(added, '🔥', added: true, isOwn: true),
        added,
      ),
      isTrue,
    );
    final two = applySuperReactionChange(
      added,
      '🔥',
      added: true,
      isOwn: false,
    )!;
    expect((two.count, two.me), (2, true));
    final one = applySuperReactionChange(two, '🔥', added: false, isOwn: true)!;
    expect((one.count, one.me), (1, false));
    expect(
      applySuperReactionChange(one, '🔥', added: false, isOwn: false),
      isNull,
    );
  });

  test('the API puts and deletes the super reaction', () async {
    final requests = <http.Request>[];
    final client = AccordClient(
      token: 't',
      baseUrl: 'https://chat.example/api/v1',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'data': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await client.reactions.addSuper('c1', 'm1', 'party:42');
    await client.reactions.removeSuper('c1', 'm1', '🔥');
    expect(requests[0].method, 'PUT');
    expect(
      requests[0].url.path,
      endsWith('/channels/c1/messages/m1/super-reactions/party%3A42'),
    );
    expect(requests[1].method, 'DELETE');
    expect(requests[1].url.path, contains('/super-reactions/'));
  });
}
