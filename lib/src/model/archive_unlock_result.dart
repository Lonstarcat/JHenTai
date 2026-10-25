enum ArchiveUnlockState { ready, pending, error }

class ArchiveUnlockResult {
  final bool success;
  final String msg;
  final String? url;

  const ArchiveUnlockResult(
      {required this.success, required this.msg, this.url});

  const ArchiveUnlockResult.ready(String url)
      : this(success: true, msg: 'success', url: url);
  const ArchiveUnlockResult.pending() : this(success: true, msg: 'pending');
  const ArchiveUnlockResult.error(String message)
      : this(success: false, msg: message);

  ArchiveUnlockState get state => !success
      ? ArchiveUnlockState.error
      : url == null
          ? ArchiveUnlockState.pending
          : ArchiveUnlockState.ready;

  @override
  String toString() {
    return 'ArchiveUnlockResult{success: $success, msg: $msg, url: $url}';
  }
}
