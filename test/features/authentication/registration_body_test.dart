import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('registrationBody', () {
    test('omits invite_code when there is no invite', () {
      final body = registrationBody(username: 'amir', password: 'secret123');
      expect(body.containsKey('invite_code'), isFalse);
      expect(body['display_name'], 'amir');
    });

    test('omits a blank invite code', () {
      final body = registrationBody(
        username: 'amir',
        password: 'secret123',
        inviteCode: '  ',
      );
      expect(body.containsKey('invite_code'), isFalse);
    });

    test('sends a trimmed invite code', () {
      final body = registrationBody(
        username: 'amir',
        password: 'secret123',
        displayName: 'Amir',
        inviteCode: ' ma1p4EMw ',
      );
      expect(body['invite_code'], 'ma1p4EMw');
      expect(body['display_name'], 'Amir');
    });
  });
}
