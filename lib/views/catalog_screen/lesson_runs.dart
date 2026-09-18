/// Stretches of [items] that share a key, in the order the items came.
///
/// A key that comes back after something else starts a stretch of its own
/// rather than pulling the later items forward: grouping never reorders, so
/// the order the caller gave still holds.
List<({K key, List<T> items})> runsBy<T, K>(Iterable<T> items, K Function(T item) keyOf) {
  final runs = <({K key, List<T> items})>[];

  for (final item in items) {
    final key = keyOf(item);
    if (runs.isNotEmpty && runs.last.key == key) {
      runs.last.items.add(item);
    } else {
      runs.add((key: key, items: [item]));
    }
  }

  return runs;
}
