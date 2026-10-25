import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/model/background_task_info.dart';
import 'package:jhentai/src/utils/background_notification_selector.dart';

NotificationTaskCandidate candidate(
  String id, {
  BackgroundTaskType type = BackgroundTaskType.download,
  NotificationTaskStage stage = NotificationTaskStage.working,
  double speed = 0,
  int bytes = 0,
  int current = 0,
}) =>
    NotificationTaskCandidate(
      task: BackgroundTaskInfo(
          id: id,
          type: type,
          status: stage == NotificationTaskStage.paused
              ? BackgroundTaskStatus.paused
              : BackgroundTaskStatus.running,
          title: id,
          current: current,
          total: 100,
          progress: current / 100,
          speedBytesPerSecond: speed),
      stage: stage,
      canTransfer: type == BackgroundTaskType.download ||
          (type == BackgroundTaskType.archiveDownload &&
              stage == NotificationTaskStage.transferring),
      transferredBytes: bytes,
    );

void main() {
  test(
      'actual transfer beats a newer preferred waiting/preparing task of either type',
      () {
    for (final type in [
      BackgroundTaskType.download,
      BackgroundTaskType.archiveDownload
    ]) {
      final selector = BackgroundNotificationSelector();
      final transferring = candidate('active',
          type: type, stage: NotificationTaskStage.transferring, speed: 100);
      final waiting = candidate('waiting',
          type: type == BackgroundTaskType.download
              ? BackgroundTaskType.archiveDownload
              : BackgroundTaskType.download);
      expect(
          selector
              .select([waiting, transferring], preferredId: 'waiting')
              .first
              .id,
          'active');
    }
  });

  test('same tier stays stable through speed fluctuations and new tasks', () {
    final selector = BackgroundNotificationSelector();
    expect(selector.select([candidate('a', speed: 100)]).first.id, 'a');
    expect(
        selector
            .select([candidate('a', speed: 10), candidate('b', speed: 1000)],
                preferredId: 'b')
            .first
            .id,
        'a');
    expect(selector.select([candidate('b', speed: 1000)]).first.id, 'b');
  });

  test(
      'short zero-speed stall is stable; fresh data can preempt a longer stall',
      () {
    var now = DateTime(2026, 10, 24);
    final selector = BackgroundNotificationSelector(now: () => now);
    selector.select([candidate('a', speed: 100)]);
    now = now.add(const Duration(seconds: 2));
    expect(
        selector
            .select([candidate('a'), candidate('b', speed: 100)],
                preferredId: 'b')
            .first
            .id,
        'a');
    now = now.add(const Duration(seconds: 2));
    expect(
        selector.select([candidate('a'), candidate('b', speed: 100)]).first.id,
        'b');
  });

  test('byte/page deltas detect real transfers but old resumed bytes do not',
      () {
    final selector = BackgroundNotificationSelector();
    selector.select(
        [candidate('queued', bytes: 400), candidate('active', bytes: 100)]);
    expect(
        selector
            .select([
              candidate('queued', bytes: 400),
              candidate('active', bytes: 200)
            ], preferredId: 'queued')
            .first
            .id,
        'active');
    selector.select([]);
    selector.select([candidate('queued'), candidate('active')]);
    expect(
        selector
            .select([candidate('queued'), candidate('active', current: 1)])
            .first
            .id,
        'active');
  });

  test('paused and waiting tasks cannot keep stale speed evidence', () {
    final selector = BackgroundNotificationSelector();
    selector.select([candidate('a', speed: 100)]);
    expect(
        selector
            .select([
              candidate('a', stage: NotificationTaskStage.paused, speed: 100),
              candidate('b',
                  type: BackgroundTaskType.archiveDownload,
                  stage: NotificationTaskStage.transferring)
            ])
            .first
            .id,
        'b');
    expect(
        selector
            .select([
              candidate('b',
                  type: BackgroundTaskType.archiveDownload,
                  stage: NotificationTaskStage.waiting,
                  speed: 100),
              candidate('c', type: BackgroundTaskType.favorite)
            ])
            .first
            .id,
        'c');
  });

  test(
      'per-type summaries use the primary, retain other stable representatives',
      () {
    final selector = BackgroundNotificationSelector();
    selector.select([
      candidate('a', speed: 100),
      candidate('archive', type: BackgroundTaskType.archiveDownload)
    ]);
    final selected = selector.select([
      candidate('queued'),
      candidate('a', speed: 100),
      candidate('archive', type: BackgroundTaskType.archiveDownload),
      candidate('archive-new', type: BackgroundTaskType.archiveDownload),
    ], preferredId: 'queued');
    expect(selected.map((item) => item.id), ['a', 'archive']);
  });
}
