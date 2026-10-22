/// Compare snowflakes without losing precision on web or ordering "10" before
/// "9". Qualified IDs retain their domain as a tie-breaker.
int compareMessageIds(String a, String b) {
  final left = BigInt.tryParse(a.split('@').first);
  final right = BigInt.tryParse(b.split('@').first);
  if (left != null && right != null) {
    final order = left.compareTo(right);
    if (order != 0) return order;
  }
  return a.compareTo(b);
}

/// The read position that makes [messageId] the first unread message: the
/// newest of [loadedIds] older than it, or `"0"` (the whole channel unread)
/// when none is loaded.
String readPositionBefore(Iterable<String> loadedIds, String messageId) {
  String? best;
  for (final id in loadedIds) {
    if (compareMessageIds(id, messageId) >= 0) continue;
    if (best == null || compareMessageIds(id, best) > 0) best = id;
  }
  return best ?? '0';
}
