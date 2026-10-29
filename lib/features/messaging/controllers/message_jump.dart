import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A request to scroll a channel's message pane to one message (from search,
/// the pinned list, a reply preview…). The pane for [channelId] consumes it
/// and clears the provider; a pane that mounts after the request was made
/// picks it up on its first frame.
class MessageJump {
  const MessageJump(this.channelId, this.messageId, this.nonce);

  final String channelId;
  final String messageId;

  /// Makes two requests for the same message distinct, so repeating a jump
  /// still notifies.
  final int nonce;
}

class MessageJumpNotifier extends Notifier<MessageJump?> {
  @override
  MessageJump? build() => null;

  void request(String channelId, String messageId) {
    state = MessageJump(
      channelId,
      messageId,
      DateTime.now().microsecondsSinceEpoch,
    );
  }

  void clear() => state = null;
}

final messageJumpProvider = NotifierProvider<MessageJumpNotifier, MessageJump?>(
  MessageJumpNotifier.new,
);
