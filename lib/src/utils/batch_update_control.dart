import 'dart:async';
import 'package:dio/dio.dart';

/// One batch-created archive pipeline at a time, including across cancelled
/// sessions. Cancellation never releases a slot still owned by a paid download.
class BatchArchiveSlot {
  Future<void>? _active;
  Future<void> wait(CancelToken cancel) async {
    final active = _active;
    if (active != null) {
      await Future.any([
        active,
        cancel.whenCancel.then((_) => throw StateError('batchUpdateCancelled'))
      ]);
    }
    if (cancel.isCancelled) {
      throw StateError('batchUpdateCancelled');
    }
  }

  Future<void> run(Future<void> Function() task) {
    if (_active != null) {
      throw StateError('Archive slot is occupied');
    }
    final result = Future<void>.sync(task);
    final tracked =
        result.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    _active = tracked;
    unawaited(tracked.then((_) {
      if (identical(_active, tracked)) {
        _active = null;
      }
    }));
    return result;
  }
}

/// Rate-limit every read request, not just galleries (which need several reads).
class BatchUpdateRequestGate {
  final Duration interval;
  final DateTime Function() now;
  final Future<void> Function(Duration) sleep;
  DateTime? _lastStart;
  BatchUpdateRequestGate(
      {this.interval = const Duration(seconds: 2),
      DateTime Function()? now,
      Future<void> Function(Duration)? sleep})
      : now = now ?? DateTime.now,
        sleep = sleep ?? Future<void>.delayed;

  Future<T> request<T>(CancelToken token, Future<T> Function() read) async {
    if (token.isCancelled) {
      throw StateError('batchUpdateCancelled');
    }
    final last = _lastStart;
    if (last != null) {
      final remaining = interval - now().difference(last);
      if (remaining > Duration.zero) {
        await Future.any([sleep(remaining), token.whenCancel]);
      }
    }
    if (token.isCancelled) {
      throw StateError('batchUpdateCancelled');
    }
    _lastStart = now();
    final result = await read();
    if (token.isCancelled) {
      throw StateError('batchUpdateCancelled');
    }
    return result;
  }
}
