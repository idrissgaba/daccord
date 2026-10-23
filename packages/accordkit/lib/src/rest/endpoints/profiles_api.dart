import '../../models/profile_extras.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Profile extras (pronouns, theme colours) and private notes.
class ProfilesApi extends EndpointBase {
  ProfilesApi(super.rest);

  /// Someone's extras, with our note about them (`@me` for ours).
  Future<RestResult> get(String userId) async {
    final result = await rest.makeRequest('GET', '/users/$userId/profile');
    return result.deserialize(AccordProfileExtras.fromJson);
  }

  /// Updates our extras; a key set to null clears that field, a missing key
  /// leaves it.
  Future<RestResult> updateMine(Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/users/@me/profile', body: data);
    return result.deserialize(AccordProfileExtras.fromJson);
  }

  /// Saves our private note about [userId]; an empty note removes it.
  Future<RestResult> setNote(String userId, String note) {
    return rest
        .makeRequest('PUT', '/users/@me/notes/$userId', body: {'note': note});
  }
}
