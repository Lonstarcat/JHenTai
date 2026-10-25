import 'package:flutter/foundation.dart';
import '../model/background_task_info.dart';
import '../model/download_batch_update.dart';
import '../model/download_multi_select_toolbar.dart';

/// Read-only notification data: no quotes, gallery objects or submit callbacks.
class BatchUpdateBackgroundSnapshot {
  final int sessionId;
  final DownloadToolbarKind kind;
  final BatchUpdatePhase phase;
  final String? currentTitle;
  final int current;
  final int total;
  final int available;
  final int submitted;
  final int failed;
  final int stopped;

  const BatchUpdateBackgroundSnapshot(
      {required this.sessionId,
      required this.kind,
      required this.phase,
      this.currentTitle,
      required this.current,
      required this.total,
      required this.available,
      required this.submitted,
      required this.failed,
      required this.stopped});

  bool get executing =>
      phase == BatchUpdatePhase.checking ||
      phase == BatchUpdatePhase.submitting;
  bool get visible => executing || phase == BatchUpdatePhase.review;
  bool get terminal =>
      phase == BatchUpdatePhase.finished || phase == BatchUpdatePhase.cancelled;
  String get phaseKey => switch (phase) {
        BatchUpdatePhase.checking => 'batchUpdateChecking',
        BatchUpdatePhase.submitting => 'batchUpdateSubmitting',
        BatchUpdatePhase.review => 'batchUpdateWaitingConfirmation',
        BatchUpdatePhase.cancelled => 'batchUpdateCancelled',
        _ => 'batchUpdateFinished',
      };
  String get taskType => kind == DownloadToolbarKind.archive
      ? 'batchArchiveUpdate'
      : 'batchGalleryUpdate';

  BackgroundTaskInfo? taskInfo(
      {required bool paused, required String fallbackTitle}) {
    if (!visible) {
      return null;
    }
    final waiting = phase == BatchUpdatePhase.review;
    return BackgroundTaskInfo(
        id: 'batchUpdate:$sessionId',
        type: BackgroundTaskType.batchUpdate,
        status: waiting
            ? BackgroundTaskStatus.waiting
            : paused
                ? BackgroundTaskStatus.paused
                : BackgroundTaskStatus.running,
        title: currentTitle?.trim().isNotEmpty == true
            ? currentTitle!
            : fallbackTitle,
        current: current,
        total: total,
        progress: total <= 0 ? 0 : (current / total).clamp(0, 1),
        successCount: submitted,
        failCount: failed);
  }
}

final ValueNotifier<BatchUpdateBackgroundSnapshot?>
    batchUpdateBackgroundSnapshot = ValueNotifier(null);

/// Session-scoped pause ownership. A new batch must not inherit an old pause.
class BatchUpdateNotificationControl {
  int? _pausedSession;
  int? _completedSession;

  bool isPaused(BatchUpdateBackgroundSnapshot? snapshot) =>
      snapshot?.executing == true && snapshot!.sessionId == _pausedSession;

  bool pause(BatchUpdateBackgroundSnapshot? snapshot) {
    if (snapshot?.executing != true) {
      return false;
    }
    _pausedSession = snapshot!.sessionId;
    return true;
  }

  void resume() => _pausedSession = null;
  void prune(BatchUpdateBackgroundSnapshot? snapshot) {
    if (!isPaused(snapshot)) {
      resume();
    }
  }

  bool consumeCompletion(BatchUpdateBackgroundSnapshot? snapshot) {
    if (snapshot?.terminal != true ||
        snapshot!.sessionId == _completedSession) {
      return false;
    }
    _completedSession = snapshot.sessionId;
    return true;
  }
}
