/// Capture order values at enqueue time, not mutable gallery objects. Strict
/// serialization prevents older writes finishing after newer moves. A failed
/// subset is merged into the next save so disjoint subsequent moves can retry it.
class DownloadOrderWriter {
  Future<void> _tail = Future<void>.value();
  final Map<int, int> _retry = {};

  Future<void> save(Map<int, int> values, Future<void> Function(Map<int, int>) write) {
    final snapshot = Map<int, int>.unmodifiable(values);
    final result = _tail.then((_) async {
      _retry.addAll(snapshot);
      await write(Map<int, int>.unmodifiable(_retry));
      _retry.clear();
    });
    // Return failure to the caller, but keep the queue usable for future saves.
    _tail = result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }
}

/// Canonicalize legacy duplicate/sparse orders on the first drop. Once canonical,
/// only the moved range differs. Also handles title/date-sorted input correctly.
Map<int, int> changedDownloadOrders<T>(List<T> entries, int Function(T) id, int Function(T) order) => {
      for (int index = 0; index < entries.length; index++)
        if (order(entries[index]) != index) id(entries[index]): index,
    };
