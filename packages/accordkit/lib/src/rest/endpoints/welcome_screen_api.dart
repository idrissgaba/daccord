import '../../models/welcome_screen.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// A space's welcome screen.
class WelcomeScreenApi extends EndpointBase {
  WelcomeScreenApi(super.rest);

  Future<RestResult> get(String spaceId) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/welcome-screen');
    return result.deserialize(AccordWelcomeScreen.fromJson);
  }

  /// Replaces it (needs `manage_space`).
  Future<RestResult> update(String spaceId, AccordWelcomeScreen screen) async {
    final result = await rest.makeRequest(
      'PATCH',
      '/spaces/$spaceId/welcome-screen',
      body: screen.toJson(),
    );
    return result.deserialize(AccordWelcomeScreen.fromJson);
  }
}
