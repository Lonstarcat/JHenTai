import 'dart:async';

import 'package:dio/dio.dart';

import '../exception/cancel_exception.dart';
import '../model/archive_unlock_result.dart';

/// Bounds archive preparation checks without choosing their HTTP transport.
/// The upstream archiver uses an unlock POST for each check, so the callback
/// can resubmit the archive form. Do not treat these as read-only GET requests.
class ArchivePagePoller {
  final int maxAttempts;
  final Duration timeout;
  final Duration interval;

  const ArchivePagePoller(
      {this.maxAttempts = 150,
      this.timeout = const Duration(minutes: 5),
      this.interval = const Duration(seconds: 2)});

  Future<ArchiveUnlockResult> run({
    required Future<ArchiveUnlockResult> Function() query,
    required CancelToken cancelToken,
    required bool Function() isCurrent,
  }) async {
    final clock = Stopwatch()..start();
    void checkOwner() {
      if (cancelToken.isCancelled || !isCurrent()) {
        throw CancelException();
      }
    }

    Future<T> awaitOwned<T>(Future<T> future) async {
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('archiveUnlockTimeout');
      }
      final result = await Future.any<T>([
        future,
        cancelToken.whenCancel.then<T>((_) => throw CancelException()),
      ]).timeout(remaining);
      checkOwner();
      return result;
    }

    try {
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        checkOwner();
        if (clock.elapsed >= timeout) {
          throw TimeoutException('archiveUnlockTimeout');
        }
        // Stop on network errors; do not add retries to the upstream POST.
        final result = await awaitOwned(query());
        if (result.state != ArchiveUnlockState.pending) {
          return result;
        }
        if (attempt + 1 < maxAttempts) {
          await awaitOwned(Future<void>.delayed(interval));
        }
      }
      throw TimeoutException('archiveUnlockTimeout');
    } finally {
      clock.stop();
    }
  }
}
