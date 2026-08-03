import 'dart:async';

class DownloadSearchScheduler {
  DownloadSearchScheduler({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;

  Timer? _timer;
  int _requestId = 0;
  bool _isDisposed = false;

  void schedule(Future<void> Function(int requestId) callback) {
    if (_isDisposed) {
      return;
    }

    _timer?.cancel();
    int requestId = ++_requestId;
    _timer = Timer(delay, () async {
      _timer = null;
      if (isCurrent(requestId)) {
        await callback(requestId);
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _requestId++;
  }

  bool isCurrent(int requestId) {
    return !_isDisposed && requestId == _requestId;
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }

    cancel();
    _isDisposed = true;
  }
}
