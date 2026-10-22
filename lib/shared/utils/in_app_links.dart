/// Opens `daccord://` links from inside the app (a message link someone
/// pasted, "Copy message link") through the same handler the OS uses for deep
/// links, instead of bouncing them through the platform — which a browser
/// cannot do for a custom scheme at all.
library;

/// Builds the link to message [messageId] in [channelId] of [spaceId]; it
/// opens the channel and shows the message.
String messageLink({
  required String spaceId,
  required String channelId,
  required String messageId,
}) =>
    'daccord://navigate/${Uri.encodeComponent(spaceId)}/'
    '${Uri.encodeComponent(channelId)}?msg=${Uri.encodeQueryComponent(messageId)}';

class InAppLinks {
  InAppLinks._();

  static void Function(Uri uri)? _handler;

  /// Installs the app's deep-link [handler] (the main window does this).
  static void register(void Function(Uri uri) handler) => _handler = handler;

  /// Removes [handler] if it is still the installed one.
  static void unregister(void Function(Uri uri) handler) {
    if (_handler == handler) _handler = null;
  }

  /// Opens [href] in the app when it is a `daccord://` link and a handler is
  /// installed. Returns false for anything else, so the caller opens it
  /// externally as before.
  static bool open(String href) {
    final handler = _handler;
    if (handler == null || !href.startsWith('daccord://')) return false;
    final uri = Uri.tryParse(href);
    if (uri == null) return false;
    handler(uri);
    return true;
  }
}
