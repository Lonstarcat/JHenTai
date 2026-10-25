/// Whole-config writes and transactional edits share one queue. Build JSON at
/// execution time, so a later style write cannot persist a failed toolbar edit.
class SerialConfigWriter {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return result;
  }
}
