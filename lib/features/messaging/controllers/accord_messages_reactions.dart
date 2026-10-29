part of 'accord_messages.dart';

/// Reactions and super reactions: the optimistic toggles, the gateway
/// echoes, and the reconciliation of events that race a history page or a
/// reactor listing. Split from [AccordMessagesController] for size; it only
/// needs the controller's history ledger.
mixin _MessageReactions on _$AccordMessagesController {
  HistoryRequests get _history;

  // ── Super reactions ────────────────────────────────────────────────────────

  /// Applies a super reaction change: a `super_reaction.*` event, or our own
  /// optimistic toggle (whose echo is then a no-op).
  void applySuperReaction(
    String messageId,
    String emoji, {
    required bool added,
    required bool isOwn,
  }) {
    final current = state;
    final message = current?.firstWhereOrNull((m) => m.id == messageId);
    if (current == null || message == null) return;
    final list = [...message.superReactions];
    final i = list.indexWhere((r) => r.emoji == emoji);
    final next = applySuperReactionChange(
      i < 0 ? null : list[i],
      emoji,
      added: added,
      isOwn: isOwn,
    );
    if (identical(next, i < 0 ? null : list[i])) return;
    if (i < 0) {
      list.add(next!);
    } else if (next == null) {
      list.removeAt(i);
    } else {
      list[i] = next;
    }
    message.superReactions = list;
    state = [...current];
  }

  /// Adds or removes our super reaction [emoji] (a reaction token), reverting
  /// on failure. Returns null on success, or why it failed.
  Future<String?> toggleSuperReaction(
    AccordClient client,
    String messageId,
    String emoji,
  ) async {
    final message = state?.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return null;
    final adding =
        !(message.superReactions
                .firstWhereOrNull((r) => r.emoji == emoji)
                ?.me ??
            false);
    applySuperReaction(messageId, emoji, added: adding, isOwn: true);
    final result = adding
        ? await client.reactions.addSuper(channelId, messageId, emoji)
        : await client.reactions.removeSuper(channelId, messageId, emoji);
    if (!ref.mounted) return null;
    if (!result.ok) {
      applySuperReaction(messageId, emoji, added: !adding, isOwn: true);
      return result.errorMessageOr(
        adding ? 'Failed to super react.' : 'Failed to remove super reaction.',
      );
    }
    return null;
  }

  // ── Reactions ──────────────────────────────────────────────────────────────

  /// Adds or removes the current user's [emojiName] reaction on [messageId],
  /// flipping based on whether it currently includes us. Optimistically updates
  /// the cache, then reverts if the REST call fails (the gateway echo is then a
  /// no-op).
  ///
  /// [emojiName] is the bare name (unicode char, or the custom emoji's name);
  /// [emojiId] is set for custom emoji. The REST API expects the token
  /// `name:id` for custom emoji, but aggregates are matched/stored by name
  /// (the form the gateway echoes back).
  ///
  /// Returns null on success, or the reason the toggle failed — the caller must
  /// show it, because the optimistic badge silently disappearing again is
  /// otherwise indistinguishable from the tap never registering.
  Future<String?> toggleReaction(
    AccordClient client,
    String messageId,
    String emojiName, {
    String? emojiId,
  }) async {
    final message = state?.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return null;
    final existing = message.reactions?.firstWhereOrNull(
      (r) => _emojiName(r) == _emojiKey(emojiName, emojiId),
    );
    final adding = !(existing?.includesMe ?? false);
    final token = emojiId == null
        ? resolveEmojiGlyph(emojiName)
        : '$emojiName:$emojiId';

    applyReaction(
      messageId,
      emojiName,
      added: adding,
      isOwn: true,
      emojiId: emojiId,
    );

    final result = adding
        ? await client.reactions.add(channelId, messageId, token)
        : await client.reactions.removeOwn(channelId, messageId, token);
    if (!ref.mounted) return null;
    if (!result.ok) {
      debugPrint('Failed to toggle reaction on $messageId: ${result.error}');
      // Revert the optimistic change.
      applyReaction(
        messageId,
        emojiName,
        added: !adding,
        isOwn: true,
        emojiId: emojiId,
      );
      return result.errorMessageOr(
        adding ? 'Failed to add reaction.' : 'Failed to remove reaction.',
      );
    }
    return null;
  }

  /// Lists the users who reacted to [messageId] with [emojiName] (custom emoji
  /// pass [emojiId]). Lazy — called when the reactor popup opens. Returns an
  /// empty list on failure.
  Future<List<AccordUser>> reactionUsers(
    AccordClient client,
    String messageId,
    String emojiName, {
    String? emojiId,
  }) async {
    final token = emojiId == null
        ? resolveEmojiGlyph(emojiName)
        : '$emojiName:$emojiId';
    final result = await client.reactions.listUsers(
      channelId,
      messageId,
      token,
      query: {'limit': 100},
    );
    if (!ref.mounted) return const [];
    if (!result.ok) {
      debugPrint('Failed to list reactors for $messageId: ${result.error}');
      return const [];
    }
    final data = result.data;
    if (data is! List) return const [];
    // The endpoint returns bare user-id strings, not user objects — resolve each
    // to an AccordUser, falling back to an id-only stub if the fetch fails so the
    // reactor still appears (and the list matches the badge count).
    final users = ref.read(accordUsersControllerProvider(serverKey).notifier);
    final resolved = <Future<AccordUser>>[];
    for (final item in data) {
      if (item is AccordUser) {
        if (item.id.isEmpty) continue;
        users.upsert(item, client: client);
        resolved.add(Future.value(item));
        continue;
      }
      final id = item.toString();
      if (id.isEmpty) continue;
      resolved.add(
        users
            .resolve(id, client: client)
            .then((user) => user ?? AccordUser(id: id)),
      );
    }
    return Future.wait(resolved);
  }

  /// Applies a reaction add/remove to [messageId]'s aggregate counts. Used both
  /// for optimistic local toggles ([isOwn] true) and for gateway echoes of
  /// other users' reactions ([isOwn] reflects whether the actor is us).
  void applyReaction(
    String messageId,
    String emojiName, {
    required bool added,
    required bool isOwn,
    String? emojiId,
    String? userId,
  }) {
    final key = _emojiKey(emojiName, emojiId);
    // Journal before the cache checks: a message missing from the cache may
    // be in the snapshot being fetched.
    _journalReaction(
      messageId,
      ReactionDelta(
        key: key,
        emoji: {'id': emojiId, 'name': key},
        actor: isOwn ? selfReactor : userId,
        added: added,
      ),
    );
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;

    final reactions = [...(message.reactions ?? const <AccordReaction>[])];
    final index = reactions.indexWhere((r) => _emojiName(r) == key);

    if (added) {
      if (index >= 0) {
        final r = reactions[index];
        if (isOwn && r.includesMe) return; // already counted
        r.count += 1;
        if (isOwn) r.includesMe = true;
      } else {
        reactions.add(
          AccordReaction(
            // Store the canonical key (glyph for unicode) so an optimistic pill
            // and its later gateway echo dedup to one — see [_emojiKey].
            emoji: {'id': emojiId, 'name': key},
            count: 1,
            includesMe: isOwn,
          ),
        );
      }
    } else {
      if (index < 0) return;
      final r = reactions[index];
      if (isOwn && !r.includesMe) return; // nothing of ours to remove
      r.count = r.count > 0 ? r.count - 1 : 0;
      if (isOwn) r.includesMe = false;
      if (r.count <= 0) reactions.removeAt(index);
    }

    message.reactions = reactions;
    state = [...current];
  }

  /// Removes a single emoji's reactions from [messageId] (gateway
  /// `reaction.clear_emoji`).
  void clearReactionEmoji(String messageId, String emojiName) {
    final key = _emojiKey(emojiName, null);
    _journalReaction(messageId, ReactionClear(key));
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message?.reactions == null) return;
    message!.reactions = message.reactions!
        .where((r) => _emojiName(r) != key)
        .toList();
    state = [...current];
  }

  /// Removes all reactions from [messageId] (gateway `reaction.clear`).
  void clearReactions(String messageId) {
    _journalReaction(messageId, const ReactionClear());
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    message.reactions = <AccordReaction>[];
    state = [...current];
  }

  // ── Reaction reconciliation ───────────────────────────────────────────────
  // A reaction event that arrives while a history page or a reactor listing
  // is in flight is recorded per user and replayed onto the fetched copy, so
  // server reactions the event did not touch survive and the event is never
  // counted twice. See reaction_journal.dart.

  /// The reactor listing in flight per (message, emoji). Only this one may
  /// settle that emoji.
  final _reactorRefreshes = <(String, String), _ReactorRefresh>{};
  int _reactorSession = 0;

  /// Advanced each time a newest-page snapshot is published. A reactor listing
  /// settles only the snapshot it was started for. A newer snapshot already
  /// includes every change the older listing was started for, and replacing
  /// it with that listing (which may finish later) would bring back an old
  /// count.
  int _snapshotGeneration = 0;

  /// Reactor listings larger than this are truncated and cannot be trusted as
  /// a full set; the server count then stands.
  static const _reactorLimit = 100;

  void _resetReactorRefreshes() {
    _reactorSession++;
    _reactorRefreshes.clear();
  }

  void _journalReaction(String messageId, ReactionOp op) {
    _history.recordReaction(messageId, op);
    for (final entry in _reactorRefreshes.entries) {
      final (id, key) = entry.key;
      if (id == messageId && op.touches(key)) entry.value.ops.add(op);
    }
  }

  /// Replays the reaction changes journaled during the fetch onto [rows].
  /// Returns the emojis whose other-user changes need the reactor listing.
  /// Each carries the fetch's changes for it, to replay onto the listing too.
  List<_PendingRefresh> _replayReactions(List<AccordMessage> rows) {
    final pending = <_PendingRefresh>[];
    for (final row in rows) {
      final ops = _history.reactionOps(row.id);
      if (ops.isEmpty) continue;
      for (final p in replayReactionOps(row, ops, _emojiName)) {
        pending.add((
          messageId: row.id,
          key: p.key,
          emoji: p.emoji,
          ops: [...ops.where((op) => op.touches(p.key))],
        ));
      }
    }
    return pending;
  }

  void _refreshReactors(AccordClient client, List<_PendingRefresh> pending) {
    for (final p in pending) {
      unawaited(_refreshReactor(client, p.messageId, p.key, p.emoji, p.ops));
    }
  }

  /// Settles one emoji's aggregate from the server's reactor list, with the
  /// changes received since the request replayed per user on top.
  Future<void> _refreshReactor(
    AccordClient client,
    String messageId,
    String key,
    Map<String, dynamic> emoji,
    List<ReactionOp> earlier,
  ) async {
    final id = (messageId, key);
    // One in flight for the same snapshot already journals every change since
    // it started. One started for an older snapshot is replaced: its result
    // can no longer be applied.
    if (_reactorRefreshes[id]?.generation == _snapshotGeneration) return;
    // The fetch's changes are replayed too. The listing is requested after
    // they arrived, so replaying them per user is idempotent.
    final refresh = _reactorRefreshes[id] = _ReactorRefresh(
      _snapshotGeneration,
      [...earlier],
    );
    final ops = refresh.ops;
    final session = _reactorSession;
    try {
      final emojiId = emoji['id']?.toString();
      final token = emojiId != null && emojiId.isNotEmpty
          ? '$key:$emojiId'
          : resolveEmojiGlyph(key);
      final result = await client.reactions.listUsers(
        channelId,
        messageId,
        token,
        query: {'limit': _reactorLimit},
      );
      if (!ref.mounted ||
          session != _reactorSession ||
          !ref.isCurrentAccordClient(serverKey, client)) {
        return;
      }
      // A newer snapshot, or a newer listing for this emoji, has won.
      if (!identical(_reactorRefreshes[id], refresh) ||
          refresh.generation != _snapshotGeneration) {
        return;
      }
      final data = result.data;
      if (!result.ok || data is! List) {
        debugPrint('Failed to list reactors for $messageId: ${result.error}');
        return;
      }
      if (data.length >= _reactorLimit) return;
      final reactors = <String>{
        for (final item in data)
          if (item is AccordUser ? item.id : item.toString() case final uid
              when uid.isNotEmpty)
            _isSelf(uid) ? selfReactor : uid,
      };
      _setReactors(
        messageId,
        key,
        emoji,
        replayOntoReactors(reactors, ops, key),
      );
    } finally {
      if (session == _reactorSession &&
          identical(_reactorRefreshes[id], refresh)) {
        _reactorRefreshes.remove(id);
      }
    }
  }

  bool _isSelf(String userId) {
    final auth = ref.read(accordAuthProvider);
    return auth is AccordAuthLoggedIn &&
        isSameUser(
          userId,
          auth.session.userId,
          localDomain: auth.session.server.homeDomain,
        );
  }

  void _setReactors(
    String messageId,
    String key,
    Map<String, dynamic> emoji,
    Set<String> reactors,
  ) {
    final current = state;
    if (current == null) return;
    final message = current.firstWhereOrNull((m) => m.id == messageId);
    if (message == null) return;
    final reactions = [...(message.reactions ?? const <AccordReaction>[])];
    final index = reactions.indexWhere((r) => _emojiName(r) == key);
    if (reactors.isEmpty) {
      if (index < 0) return;
      reactions.removeAt(index);
    } else {
      final settled = AccordReaction(
        emoji: index < 0 ? Map.of(emoji) : reactions[index].emoji,
        count: reactors.length,
        includesMe: reactors.contains(selfReactor),
      );
      if (index < 0) {
        reactions.add(settled);
      } else {
        reactions[index] = settled;
      }
    }
    message.reactions = reactions;
    state = [...current];
  }

  // Dedup/match key for a reaction.
  String _emojiName(AccordReaction r) =>
      _emojiKey(r.emoji['name']?.toString() ?? '', r.emoji['id']?.toString());

  // Canonical dedup key for an emoji reference. Custom emoji key on their name
  // (the id is carried separately, and may arrive baked into the name as
  // `name:id` when the source didn't split it — strip it). Unicode emoji key on
  // their glyph: the picker hands us a shortcode (`hamburger`) while the gateway
  // echoes the glyph (`🍔`), so without resolving both to the glyph an optimistic
  // pill and its echo wouldn't match, leaving two pills for one reaction.
  String _emojiKey(String name, String? id) {
    if (id != null && id.isNotEmpty) return name;
    return resolveEmojiGlyph(parseEmojiToken(name).name);
  }
}
