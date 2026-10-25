import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/model/background_task_info.dart';
import 'package:jhentai/src/consts/app_identity.dart';
import 'package:jhentai/src/service/background_task_service.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/service/batch_update_background_bridge.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/service/download_task_navigation_service.dart';
import 'batch_update_fakes.dart';

BatchUpdateBackgroundSnapshot snapshot(BatchUpdatePhase phase, {int id = 1}) =>
    BatchUpdateBackgroundSnapshot(
        sessionId: id,
        kind: DownloadToolbarKind.archive,
        phase: phase,
        currentTitle: 'Comic',
        current: 2,
        total: 5,
        available: 3,
        submitted: 1,
        failed: 1,
        stopped: 0);

class PauseAwareBackend extends FakeBatchBackend {
  final BatchUpdateNotificationControl control;
  final ValueNotifier<BatchUpdateBackgroundSnapshot?> progress;
  PauseAwareBackend(this.control, this.progress);
  @override
  bool get globallyPaused => control.isPaused(progress.value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'production notification payload and batch-only toggle preserve confirmation boundary',
      () async {
    const channel = MethodChannel(AppIdentity.backgroundTasksChannel);
    final oldSnapshot = batchUpdateBackgroundSnapshot.value;
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      batchUpdateBackgroundSnapshot.value = oldSnapshot;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final background = BackgroundTaskService();
    batchUpdateBackgroundSnapshot.value = snapshot(BatchUpdatePhase.checking);
    await background.refreshNotificationForTesting();
    Map payload() =>
        calls.lastWhere((call) => call.method == 'show').arguments as Map;
    expect(payload()['showProgress'], isTrue);
    expect(payload()['progress'], 2);
    expect(payload()['max'], 5);
    expect(payload()['taskType'], 'batchArchiveUpdate');
    expect(payload()['showAction'], isTrue);
    expect(payload()['speedText'], isEmpty);
    await background.toggleAllFromNotification();
    expect(background.isGloballyPaused, isTrue);
    await background.refreshNotificationForTesting();
    expect(payload()['paused'], isTrue);
    await background.toggleAllFromNotification();
    expect(background.isGloballyPaused, isFalse);
    batchUpdateBackgroundSnapshot.value = snapshot(BatchUpdatePhase.review);
    await background.refreshNotificationForTesting();
    expect(payload()['showProgress'], isFalse);
    expect(payload()['showAction'], isFalse);
    expect(
        payload()['primaryDetail'], contains('batchUpdateWaitingConfirmation'));
    await background.toggleAllFromNotification();
    expect(background.isGloballyPaused, isFalse);
    expect(batchUpdateBackgroundSnapshot.value!.phase, BatchUpdatePhase.review);
    batchUpdateBackgroundSnapshot.value = null;
    await background.refreshNotificationForTesting();
  });
  test(
      'checking/submitting project real progress; review never implies execution',
      () {
    for (final phase in [
      BatchUpdatePhase.checking,
      BatchUpdatePhase.submitting
    ]) {
      final state = snapshot(phase);
      expect(state.executing, isTrue);
      final task = state.taskInfo(paused: false, fallbackTitle: 'Batch');
      expect(task!.type, BackgroundTaskType.batchUpdate);
      expect(task.current, 2);
      expect(task.total, 5);
      expect(task.progress, .4);
      expect(task.status, BackgroundTaskStatus.running);
      expect(state.taskInfo(paused: true, fallbackTitle: 'Batch')!.status,
          BackgroundTaskStatus.paused);
    }
    final review = snapshot(BatchUpdatePhase.review);
    expect(review.visible, isTrue);
    expect(review.executing, isFalse);
    expect(review.phaseKey, 'batchUpdateWaitingConfirmation');
    expect(review.taskInfo(paused: true, fallbackTitle: 'Batch')!.status,
        BackgroundTaskStatus.waiting);
    final control = BatchUpdateNotificationControl();
    expect(control.pause(review), isFalse);
    control.resume();
    expect(review.phase, BatchUpdatePhase.review);
    for (final phase in [
      BatchUpdatePhase.finished,
      BatchUpdatePhase.cancelled
    ]) {
      final terminal = snapshot(phase, id: phase.index);
      expect(terminal.taskInfo(paused: false, fallbackTitle: 'Batch'), isNull);
      expect(control.consumeCompletion(terminal), isTrue);
      expect(control.consumeCompletion(terminal), isFalse);
    }
  });

  test('pause ownership is pruned on review or replacement session', () {
    final control = BatchUpdateNotificationControl();
    expect(control.pause(snapshot(BatchUpdatePhase.checking)), isTrue);
    expect(control.isPaused(snapshot(BatchUpdatePhase.checking)), isTrue);
    control.prune(snapshot(BatchUpdatePhase.checking, id: 2));
    expect(
        control.isPaused(snapshot(BatchUpdatePhase.checking, id: 2)), isFalse);
    control.pause(snapshot(BatchUpdatePhase.submitting));
    control.prune(snapshot(BatchUpdatePhase.review));
    expect(control.isPaused(snapshot(BatchUpdatePhase.review)), isFalse);
  });

  test(
      'published progress and real service checkpoint pause/resume without submitting',
      () async {
    final progress = ValueNotifier<BatchUpdateBackgroundSnapshot?>(null);
    final control = BatchUpdateNotificationControl();
    final backend = PauseAwareBackend(control, progress)
      ..details.addAll({1: testDetail(1), 2: testDetail(2)});
    final firstRead = Completer<void>();
    final releaseFirst = Completer<void>();
    final pausedCheckpoint = Completer<void>();
    final resumeCheckpoint = Completer<void>();
    backend.onRead = (gid) async {
      if (gid == 1) {
        firstRead.complete();
        await releaseFirst.future;
      }
    };
    final service = DownloadBatchUpdateService(backend,
        backgroundProgress: progress, sleep: (_) async {
      if (!pausedCheckpoint.isCompleted) {
        pausedCheckpoint.complete();
      }
      await resumeCheckpoint.future;
    });
    final running = service.check([testSource(1), testSource(2)]);
    await firstRead.future;
    expect(progress.value!.phase, BatchUpdatePhase.checking);
    expect(control.pause(progress.value), isTrue);
    releaseFirst.complete();
    await pausedCheckpoint.future;
    expect(backend.reads, [1]);
    control.resume();
    resumeCheckpoint.complete();
    await running;
    expect(backend.reads, [1, 2]);
    expect(progress.value!.phase, BatchUpdatePhase.review);
    expect(progress.value!.current, 2);
    expect(control.pause(progress.value), isFalse);
    control.resume();
    expect(backend.submissions, isEmpty);
    service.cancel();
    expect(progress.value!.phase, BatchUpdatePhase.cancelled);
    service.dispose();
    progress.dispose();
  });

  test(
      'notification routing selects correct batch kind; regular tasks unchanged',
      () {
    expect(
        const DownloadTaskNavigationTarget(taskType: 'batchArchiveUpdate')
            .batchUpdateKind,
        DownloadToolbarKind.archive);
    expect(
        const DownloadTaskNavigationTarget(taskType: 'batchGalleryUpdate')
            .batchUpdateKind,
        DownloadToolbarKind.gallery);
    expect(
        const DownloadTaskNavigationTarget(taskType: 'favorite')
            .batchUpdateKind,
        isNull);
  });
}
