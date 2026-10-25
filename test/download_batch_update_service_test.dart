import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/utils/batch_update_control.dart';
import 'package:jhentai/src/utils/update_submission_util.dart';
import 'batch_update_fakes.dart';

void main() {
  test(
      'completed-only, latest, target dedup, failures continue, no submit before confirmation',
      () async {
    final backend = FakeBatchBackend()
      ..excluded.add(2)
      ..existing.add(50);
    backend.details.addAll({
      1: testDetail(1),
      3: testDetail(3, next: 30),
      30: testDetail(30),
      4: testDetail(4, next: 30),
      5: testDetail(5, next: 50),
      50: testDetail(50)
    });
    final service = DownloadBatchUpdateService(backend);
    await service.check([for (int i = 1; i <= 6; i++) testSource(i)]);
    expect(service.count(BatchUpdateItemStatus.latest), 1);
    expect(service.count(BatchUpdateItemStatus.skipped), 1);
    expect(service.count(BatchUpdateItemStatus.available), 1);
    expect(service.count(BatchUpdateItemStatus.existing), 2);
    expect(service.count(BatchUpdateItemStatus.failed), 1);
    expect(backend.reads, isNot(contains(2)));
    expect(backend.submissions, isEmpty);
    await service.submit();
    expect(backend.submissions, [30]);
    expect(service.count(BatchUpdateItemStatus.submitted), 1);
    service.dispose();
  });

  test('cyclic version chains are failures, not latest', () async {
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1, next: 2), 2: testDetail(2, next: 1)});
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1)]);
    expect(service.items.single.reason, 'batchUpdateInvalidVersion');
    expect(service.count(BatchUpdateItemStatus.failed), 1);
    service.dispose();
  });

  test('check cancellation and running guard stop pending reads', () async {
    final gate = Completer<void>();
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1), 2: testDetail(2)})
      ..onRead = (_) => gate.future;
    final service = DownloadBatchUpdateService(backend);
    final checking = service.check([testSource(1), testSource(2)]);
    await Future<void>.delayed(Duration.zero);
    await expectLater(service.check([testSource(2)]), throwsStateError);
    service.cancel();
    gate.complete();
    await checking;
    expect(backend.reads, [1]);
    expect(service.phase, BatchUpdatePhase.cancelled);
    await expectLater(service.submit(), throwsStateError);
    service.dispose();
  });

  test('submission rechecks live eligibility, existing targets and checkbox',
      () async {
    final backend = FakeBatchBackend();
    for (int i = 1; i <= 4; i++) {
      backend.details
          .addAll({i: testDetail(i, next: i + 10), i + 10: testDetail(i + 10)});
    }
    final service = DownloadBatchUpdateService(backend);
    await service.check([for (int i = 1; i <= 4; i++) testSource(i)]);
    backend.excluded.add(1);
    backend.existing.add(12);
    service.select(service.items[2], false);
    await service.submit();
    expect(backend.submissions, [14]);
    expect(service.items[0].status, BatchUpdateItemStatus.failed);
    expect(service.items[1].status, BatchUpdateItemStatus.existing);
    service.dispose();
  });

  test('quote failure, changed price, budget failure never register or unlock',
      () async {
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1, next: 11), 11: testDetail(11)})
      ..quoteFailures.add(1);
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1, archive: true)]);
    expect(service.items.single.status, BatchUpdateItemStatus.failed);
    await service.submit();
    expect(backend.submissions, isEmpty);
    backend.quoteFailures.clear();
    await service.check([testSource(1, archive: true)]);
    backend.priceChanged = true;
    await service.submit();
    expect(service.items.single.reason, 'batchUpdateQuoteChanged');
    expect(backend.pipelines, isEmpty);
    backend.priceChanged = false;
    await service.check([testSource(1, archive: true)]);
    backend.budgetFailure = true;
    await service.submit();
    expect(service.items.single.reason, 'batchUpdateInsufficientFunds');
    expect(backend.submissions, isEmpty);
    service.dispose();
  });

  test(
      'archive max one pipeline, cancellation preserves registered task and stops next',
      () async {
    final backend = FakeBatchBackend()..pipelineGate = Completer<void>();
    backend.details.addAll({
      1: testDetail(1, next: 11),
      11: testDetail(11),
      2: testDetail(2, next: 12),
      12: testDetail(12)
    });
    final service = DownloadBatchUpdateService(backend);
    await service
        .check([testSource(1, archive: true), testSource(2, archive: true)]);
    final submitting = service.submit();
    await Future<void>.delayed(Duration.zero);
    expect(backend.submissions, [11]);
    expect(backend.pipelines, [11]);
    expect(service.items.first.status, BatchUpdateItemStatus.submitted);
    service.cancel();
    await submitting;
    expect(backend.existing, contains(11));
    expect(backend.submissions, [11]);
    final wait = backend.slot.wait(CancelToken());
    bool free = false;
    unawaited(wait.then((_) => free = true));
    await Future<void>.delayed(Duration.zero);
    expect(free, isFalse);
    backend.pipelineGate!.complete();
    await wait;
    service.dispose();
  });

  test(
      'unregistered failure is never successful; queue continues to next candidate',
      () async {
    bool exists = false;
    expect(
        (await verifyUpdateRegistration(
                exists: () => exists, register: () async {}))
            .status,
        UpdateSubmissionStatus.failed);
    expect(
        (await verifyUpdateRegistration(
                exists: () => exists,
                register: () async {
                  exists = true;
                }))
            .status,
        UpdateSubmissionStatus.submitted);
    expect(
        (await verifyUpdateRegistration(
                exists: () => exists,
                register: () async {
                  fail('duplicate registration');
                }))
            .status,
        UpdateSubmissionStatus.alreadyPresent);
    final backend = FakeBatchBackend()
      ..submissionFailures.add(1)
      ..details.addAll({
        1: testDetail(1, next: 11),
        11: testDetail(11),
        2: testDetail(2, next: 12),
        12: testDetail(12)
      });
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1), testSource(2)]);
    await service.submit();
    expect(service.items.first.status, BatchUpdateItemStatus.failed);
    expect(service.items.last.status, BatchUpdateItemStatus.submitted);
    service.dispose();
  });

  test(
      'every request start is rate-limited; cancel during delay starts nothing',
      () async {
    var now = DateTime(2026);
    final gate = BatchUpdateRequestGate(
        now: () => now,
        sleep: (duration) async {
          now = now.add(duration);
        });
    final starts = <DateTime>[];
    final token = CancelToken();
    for (int i = 0; i < 3; i++) {
      await gate.request(token, () async {
        starts.add(now);
        return 1;
      });
    }
    expect(starts[1].difference(starts[0]), const Duration(seconds: 2));
    expect(starts[2].difference(starts[1]), const Duration(seconds: 2));
    final pause = Completer<void>();
    final blocked = BatchUpdateRequestGate(sleep: (_) => pause.future);
    await blocked.request(token, () async => 1);
    final cancelled = blocked.request(token, () async {
      fail('cancelled request started');
    });
    token.cancel();
    await expectLater(cancelled, throwsStateError);
    pause.complete();
  });
}
