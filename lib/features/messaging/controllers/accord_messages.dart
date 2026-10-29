import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/reaction_journal.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/messaging/controllers/history_request.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/controllers/load_failed.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/list_ext.dart';
import 'package:bonfire/features/messaging/utils/send_cooldown.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_messages.g.dart';
part 'accord_messages_reactions.dart';

/// An emoji whose aggregate must be settled from the reactor listing, with the
/// reaction changes the history fetch saw for it.
/// A reactor listing in flight: the snapshot generation it may settle, and
/// the reaction changes received since it started.
final class _ReactorRefresh {
  _ReactorRefresh(this.generation, this.ops);
  final int generation;
  final List<ReactionOp> ops;
}

typedef _PendingRefresh = ({
  String messageId,
  String key,
  Map<String, dynamic> emoji,
  List<ReactionOp> ops,
});

/// Channels that currently have a live message controller. The gateway handler
/// consults this so it only mutates caches the UI has actually opened, rather
/// than instantiating (and history-loading) a controller for every channel
/// that happens to receive a message.
typedef ServerChannelKey = ({String serverKey, String channelId});

final Set<ServerChannelKey> activeMessageChannels = <ServerChannelKey>{};

/// The channel the user is currently viewing, if any. The notification layer
/// consults this to avoid raising a notification for a message in the channel
/// that's already on screen. Set by the home screen as the selection changes.
ServerChannelKey? accordVisibleChannel;

bool isAccordChannelVisible(String serverKey, String channelId) {
  if (accordVisibleChannel != (serverKey: serverKey, channelId: channelId)) {
    return false;
  }
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  return lifecycle == null || lifecycle == AppLifecycleState.resumed;
}

/// Whether this channel's history fetch failed, so the message pane can offer a
/// retry instead of spinning forever. The [LoadFailed] flag for this cache —
/// see there for the shared pattern.
LoadFailedProvider messagesLoadFailedProvider(
  String serverKey,
  String channelId,
) => loadFailedProvider('messages', serverKey, channelId);

/// A channel's recent message history, keyed by channel ID, ordered
/// oldest→newest for display. Self-loads via `messages.list` the first time
/// it's watched (once logged in) and is kept in sync by message
/// create/update/delete gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: false)
class AccordMessagesController extends _$AccordMessagesController
    with _MessageReactions {
  @override
  List<AccordMessage>? build(String serverKey, String channelId) {
    _history.reset();
    _resetReactorRefreshes();
    isLoadingOlder = false;
    hasMoreOlder = true;
    ref.onDispose(_history.reset);
    ref.onDispose(_resetReactorRefreshes);
    final key = (serverKey: serverKey, channelId: channelId);
    activeMessageChannels.add(key);
    ref.onDispose(() => activeMessageChannels.remove(key));

    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) {
      _load(client, channelId);
    }
    return null;
  }

  /// How many messages to request per page. Used by both the initial load and
  /// the older-page cursor fetch; if a page comes back smaller than this we've
  /// reached the start of history.
  static const _pageSize = 50;

  /// True while [loadOlder] has an in-flight REST call. UI uses this to show a
  /// "loading older messages" indicator and to suppress duplicate fetches when
  /// the user keeps scrolling.
  bool isLoadingOlder = false;

  /// False once a page returned fewer than [_pageSize] messages — there's no
  /// older history to fetch. UI hides its "load older" affordance when set.
  bool hasMoreOlder = true;

  @override
  final _history = HistoryRequests();

  bool _owns(HistoryRequest request, AccordClient client) =>
      ref.mounted &&
      _history.owns(request) &&
      ref.isCurrentAccordClient(serverKey, client);

  Future<void> _load(AccordClient client, String channelId) async {
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    final request = _history.begin();
    isLoadingOlder = false;
    try {
      final result = await client.messages.list(
        channelId,
        query: {'limit': _pageSize},
      );
      // build starts this synchronously: writes to other providers must follow
      // the await, and only the current request may publish any result.
      if (!_owns(request, client)) return;
      final list = result.listOrLog<AccordMessage>('messages for $channelId');
      if (list == null) {
        _setLoadFailed(true);
        return;
      }
      hasMoreOlder = list.length >= _pageSize;
      final rows = _history.reconcile(list.reversed, state ?? const []);
      final pending = _replayReactions(rows);
      _snapshotGeneration++;
      state = rows;
      _setLoadFailed(false);
      _refreshReactors(client, pending);
    } finally {
      if (_owns(request, client)) _history.finish(request);
    }
  }

  void _setLoadFailed(bool value) => ref
      .read(messagesLoadFailedProvider(serverKey, channelId).notifier)
      .set(value);

  /// Re-fetches the newest page, replacing the cache in place (no flash to the
  /// loading state). Used after a gateway re-identify: a fresh session gets no
  /// event replay, so anything that happened while disconnected is missing
  /// from the cache until refetched.
  Future<void> reload(AccordClient client) {
    // A reload supersedes an in-flight [loadOlder], whose cleanup will then no
    // longer run. Clear its spinner now, and notify: the older-history header
    // watches only this list, so a bare flag change (and a reload that then
    // fails without publishing a list) would leave the spinner up.
    if (isLoadingOlder) {
      isLoadingOlder = false;
      final s = state;
      if (s != null) state = [...s];
    }
    return _load(client, channelId);
  }

  /// Loads the previous page of messages (older than the currently-oldest one
  /// in cache) and prepends them to [state]. Idempotent under concurrent calls
  /// and a no-op once [hasMoreOlder] is false. Returns the number of new
  /// messages loaded (0 means "no more"). Mirrors the reference client's
  /// scroll-up pagination via the `before` cursor.
  Future<int> loadOlder(AccordClient client) async {
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return 0;
    if (_history.isLoading || !hasMoreOlder) return 0;
    final current = state;
    if (current == null || current.isEmpty) return 0;
    final request = _history.begin();
    isLoadingOlder = true;
    // Bump state so widgets watching the list rebuild and can show a spinner.
    state = [...current];
    try {
      final oldestId = current.first.id;
      final result = await client.messages.list(
        channelId,
        query: {'limit': _pageSize, 'before': oldestId},
      );
      if (!_owns(request, client)) return 0;
      final page = result.listOrLog<AccordMessage>(
        'older messages for $channelId',
      );
      if (page == null) return 0;
      if (page.length < _pageSize) hasMoreOlder = false;
      if (page.isEmpty) return 0;
      // REST returns newest-first within the page; prepend oldest-first.
      final older = _history.reconcile(page.reversed, const []);
      final newest = state ?? current;
      // Dedupe in case an overlapping message snuck in (e.g. live insert).
      final knownIds = newest.map((m) => m.id).toSet();
      final fresh = older.where((m) => knownIds.add(m.id)).toList();
      final pending = _replayReactions(fresh);
      state = [...fresh, ...newest];
      _refreshReactors(client, pending);
      return fresh.length;
    } finally {
      // Cleanup belongs to the request too: an obsolete page must not clear
      // a newer page's spinner or notify its listeners.
      if (_owns(request, client)) {
        _history.finish(request);
        isLoadingOlder = false;
        final s = state;
        if (s != null) state = [...s];
      }
    }
  }

  /// Sends [content] via `messages.create`. Returns null on success, or the
  /// server's own failure (message plus, for a 429, its `retry_after`) —
  /// used by the no-attachments path of [sendWithAttachments].
  ///
  /// One request per call: the SDK doesn't retry a rate-limited send, so a
  /// slowmode or upload-budget 429 comes straight back for the composer to
  /// turn into a countdown rather than a minutes-long busy Send.
  Future<SendFailure?> _createMessage(
    AccordClient client,
    String content, {
    String? replyTo,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const SendFailure('Message is empty.');
    final data = <String, dynamic>{'content': trimmed};
    if (replyTo != null) data['reply_to'] = replyTo;
    final result = await client.messages.create(channelId, data);
    if (!ref.mounted) return const SendFailure('Message view closed.');
    if (!result.ok) {
      debugPrint('Failed to send message to $channelId: ${result.error}');
      return SendFailure.fromResult(result, 'Failed to send message.');
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return null;
  }

  /// Posts a poll to this channel. Returns null on success, or the reason it
  /// failed.
  Future<String?> createPoll(
    AccordClient client, {
    required String question,
    required List<String> answers,
    bool allowMultiselect = false,
    int durationHours = 24,
  }) async {
    final result = await client.messages.createPoll(channelId, {
      'question': question.trim(),
      'answers': [
        for (final answer in answers) {'text': answer.trim()},
      ],
      'allow_multiselect': allowMultiselect,
      'duration_hours': durationHours,
    });
    if (!ref.mounted) return null;
    if (!result.ok) {
      return result.error?.message ?? 'Failed to create the poll.';
    }
    final message = result.data;
    if (message is AccordMessage) addMessage(message);
    return null;
  }

  /// Votes for (or, with [remove], withdraws the vote for) [answerId] in the
  /// poll on [messageId]. Returns null on success, or the reason it failed.
  Future<String?> votePoll(
    AccordClient client,
    String messageId,
    int answerId, {
    bool remove = false,
  }) async {
    final result = remove
        ? await client.messages.unvotePoll(channelId, messageId, answerId)
        : await client.messages.votePoll(channelId, messageId, answerId);
    if (!ref.mounted) return null;
    if (!result.ok) return result.error?.message ?? 'Vote failed.';
    final message = result.data;
    if (message is AccordMessage) updateMessage(message);
    return null;
  }

  /// Ends the poll on [messageId] now. Returns null on success, or the reason
  /// it failed.
  Future<String?> endPoll(AccordClient client, String messageId) async {
    final result = await client.messages.expirePoll(channelId, messageId);
    if (!ref.mounted) return null;
    if (!result.ok) return result.error?.message ?? 'Could not end the poll.';
    final message = result.data;
    if (message is AccordMessage) updateMessage(message);
    return null;
  }

  /// Pins [messageId] in this channel, optimistically flipping its `pinned`
  /// flag (reverted on failure).
  ///
  /// Returns null on success, or the reason the pin failed — the caller must
  /// show it, because the optimistic flag silently flipping back is otherwise
  /// indistinguishable from the tap never registering.
  Future<String?> pin(AccordClient client, String messageId) async {
    _setPinned(messageId, true);
    final result = await client.messages.pin(channelId, messageId);
    if (!ref.mounted) return null;
    if (!result.ok) {
      debugPrint('Failed to pin $messageId: ${result.error}');
      _setPinned(messageId, false);
      return result.errorMessageOr('Failed to pin message.');
    }
    return null;
  }

  /// Unpins [messageId] in this channel, optimistically clearing its `pinned`
  /// flag (reverted on failure). Returns null on success, or the reason it
  /// failed — see [pin].
  Future<String?> unpin(AccordClient client, String messageId) async {
    _setPinned(messageId, false);
    final result = await client.messages.unpin(channelId, messageId);
    if (!ref.mounted) return null;
    if (!result.ok) {
      debugPrint('Failed to unpin $messageId: ${result.error}');
      _setPinned(messageId, true);
      return result.errorMessageOr('Failed to unpin message.');
    }
    return null;
  }

  void _setPinned(String messageId, bool pinned) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null || message.pinned == pinned) return;
    message.pinned = pinned;
    _history.patch(messageId, (m) => m.pinned = pinned);
    state = [...current];
  }

  /// Edits [messageId] to [content] via `messages.edit`, optimistically
  /// applying the result (the gateway echo is then a no-op). Returns true on
  /// success.
  Future<bool> edit(
    AccordClient client,
    String messageId,
    String content,
  ) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;
    final result = await client.messages.edit(channelId, messageId, {
      'content': trimmed,
    });
    if (!ref.mounted) return false;
    if (!result.ok) {
      debugPrint('Failed to edit message $messageId: ${result.error}');
      return false;
    }
    final message = result.data;
    if (message is AccordMessage) updateMessage(message);
    return true;
  }

  /// Deletes [messageId] via `messages.delete`, optimistically removing it.
  /// Returns true on success.
  Future<bool> delete(AccordClient client, String messageId) async {
    final result = await client.messages.delete(channelId, messageId);
    if (!ref.mounted) return false;
    if (!result.ok) {
      debugPrint('Failed to delete message $messageId: ${result.error}');
      return false;
    }
    removeMessage(messageId);
    return true;
  }

  /// Bulk-deletes [messageIds] via `messages.bulkDelete`, optimistically
  /// removing them. The endpoint requires 2–100 ids; a single id falls back to
  /// [delete]. Returns true on success.
  Future<bool> bulkDelete(AccordClient client, List<String> messageIds) async {
    if (messageIds.isEmpty) return false;
    if (messageIds.length == 1) return delete(client, messageIds.first);
    final result = await client.messages.bulkDelete(channelId, messageIds);
    if (!ref.mounted) return false;
    if (!result.ok) {
      debugPrint('Failed to bulk-delete in $channelId: ${result.error}');
      return false;
    }
    for (final id in messageIds) {
      _history.remove(id);
    }
    final current = state;
    if (current != null) {
      final ids = messageIds.toSet();
      state = current.where((m) => !ids.contains(m.id)).toList();
    }
    return true;
  }

  /// Sends [content] plus file [files] to this channel via
  /// `messages.createWithAttachments`. Each file is a map with `filename`,
  /// `content` (bytes) and optional `content_type`. Falls back to
  /// `messages.create` (the same call [send] makes) when there are no files.
  ///
  /// Returns null on success, or the failure message to show the user. The
  /// server's own reason is passed through — a rejected upload (too large, no
  /// `attach_files` permission, unsupported type, or an AutoMod rule that
  /// refuses the file up front with a 400) is otherwise indistinguishable
  /// from a dead Send button.
  ///
  /// A `202 Accepted` is a success: the message exists with its text, and the
  /// attachments AutoMod is still scanning are listed by upload ID rather than
  /// present on the message. Those IDs go to [PendingUploadsController] so the
  /// row shows a processing placeholder; the message is never re-sent just
  /// because its attachment list came back short.
  Future<SendFailure?> sendWithAttachments(
    AccordClient client,
    String content,
    List<Map<String, dynamic>> files, {
    String? replyTo,
  }) async {
    if (files.isEmpty) {
      return _createMessage(client, content, replyTo: replyTo);
    }
    final data = <String, dynamic>{'content': content.trim()};
    if (replyTo != null) data['reply_to'] = replyTo;

    final result = await client.messages.createWithAttachments(
      channelId,
      data,
      files,
    );
    if (!ref.mounted) return const SendFailure('Message view closed.');
    if (!result.ok) {
      debugPrint('Failed to send attachments to $channelId: ${result.error}');
      return SendFailure.fromResult(result, 'Failed to send attachments.');
    }
    final upload = result.data;
    if (upload is AccordMessageUpload) {
      addMessage(upload.message);
      if (upload.hasPendingAttachments) {
        ref
            .read(pendingUploadsControllerProvider(serverKey).notifier)
            .track(upload.message, upload.pendingAttachmentIds, client: client);
      }
    }
    return null;
  }

  /// Appends a newly-received message, ignoring duplicates (e.g. the gateway
  /// echo of a message we just sent).
  void addMessage(AccordMessage message) {
    final current = state ?? const <AccordMessage>[];
    if (current.any((m) => m.id == message.id)) return;
    _history.add(message);
    state = [...current, message];
  }

  void updateMessage(AccordMessage message) {
    final previous = state?.firstWhereOrNull((m) => m.id == message.id);
    if (previous != null) keepViewerState(message, previous);
    _history.update(message);
    final next = state?.replaceById(message, (m) => m.id);
    if (next != null) state = next;
  }

  void removeMessage(String messageId) {
    _history.remove(messageId);
    final current = state;
    if (current == null) return;
    state = current.removeById(messageId, (m) => m.id);
  }
}

/// Carries what an update leaves out from the copy already shown: an update
/// without reactions keeps the known ones, and a poll broadcast (counts only)
/// keeps which answers the user picked. Super reactions travel by their own
/// events, so an update never carries them.
void keepViewerState(AccordMessage next, AccordMessage previous) {
  next.reactions ??= previous.reactions;
  final poll = next.poll;
  final previousPoll = previous.poll;
  if (poll != null && previousPoll != null) poll.adoptMineFrom(previousPoll);
  if (next.superReactions.isEmpty) {
    next.superReactions = previous.superReactions;
  }
}

/// One super reaction aggregate after a change: [current] itself when nothing
/// changes (our own echo), null once it's gone.
AccordSuperReaction? applySuperReactionChange(
  AccordSuperReaction? current,
  String emoji, {
  required bool added,
  required bool isOwn,
}) {
  if (added) {
    if (current == null) {
      return AccordSuperReaction(emoji: emoji, count: 1, me: isOwn);
    }
    if (isOwn && current.me) return current;
    return AccordSuperReaction(
      emoji: emoji,
      count: current.count + 1,
      me: current.me || isOwn,
    );
  }
  if (current == null || (isOwn && !current.me)) return current;
  if (current.count <= 1) return null;
  return AccordSuperReaction(
    emoji: emoji,
    count: current.count - 1,
    me: isOwn ? false : current.me,
  );
}
