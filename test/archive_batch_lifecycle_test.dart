import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/download_batch_update_backend.dart';
import 'package:jhentai/src/utils/batch_update_control.dart';
import 'package:jhentai/src/utils/speed_computer.dart';
import 'batch_update_fakes.dart';

/// Only the network/files pipeline is replaced. The inherited production
/// runRegisteredArchiveUpdate owns status waiting, bounded GIDs and cleanup.
class LifecycleArchiveService extends ArchiveDownloadService {
  final List<int> calls = [];
  void add(int gid) {
    archives.add(buildArchiveUpdateData(
        testSource(gid, archive: true),
        testDetail(gid),
        const ArchiveUpdateQuote(sizeBytes: 1, cost: '1 GP'),
        DateTime(2026)));
    archiveDownloadInfos[gid] = ArchiveDownloadInfo(
        size: 1,
        parseSource: 1,
        archiveStatus: ArchiveStatus.unlocking,
        cancelToken: CancelToken(),
        speedComputer: SpeedComputer(),
        sortOrder: 0,
        group: 'test');
  }

  @override
  Future<void> downloadArchive(ArchiveDownloadedData archive,
      {bool resume = false, bool reParse = false}) async {
    calls.add(archive.gid);
    archiveDownloadInfos[archive.gid]!.archiveStatus =
        ArchiveStatus.waitingIsolate;
  }
}

void main() {
  test(
      'production lifetime keeps slot and bounded retries across waitingIsolate/wakeup until completed',
      () async {
    final service = LifecycleArchiveService()
      ..add(1)
      ..add(2);
    final slot = BatchArchiveSlot();
    bool firstDone = false;
    final first = slot.run(() => service.runRegisteredArchiveUpdate(1));
    unawaited(first.then((_) => firstDone = true));
    await Future<void>.delayed(Duration.zero);
    expect(service.archiveDownloadInfos[1]!.archiveStatus,
        ArchiveStatus.waitingIsolate);
    expect(service.isBatchUpdateManaged(1), isTrue);
    final free = slot.wait(CancelToken());
    bool freeDone = false;
    unawaited(free.then((_) => freeDone = true));
    await Future<void>.delayed(const Duration(milliseconds: 230));
    expect(firstDone, isFalse);
    expect(freeDone, isFalse);
    expect(service.calls, [1]);
    service.archiveDownloadInfos[1]!.archiveStatus = ArchiveStatus.downloading;
    expect(service.isBatchUpdateManaged(1), isTrue);
    service.archiveDownloadInfos[1]!.archiveStatus = ArchiveStatus.completed;
    await first;
    await free;
    expect(service.isBatchUpdateManaged(1), isFalse);
    final second = slot.run(() => service.runRegisteredArchiveUpdate(2));
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, [1, 2]);
    service.archiveDownloadInfos[2]!.archiveStatus = ArchiveStatus.completed;
    await second;
  });

  test(
      'production waiter stops on pause/removal, never auto-resumes and releases owned GID',
      () async {
    for (final remove in [false, true]) {
      final service = LifecycleArchiveService()..add(1);
      final first = service.runRegisteredArchiveUpdate(1);
      final failure = expectLater(first, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(service.isBatchUpdateManaged(1), isTrue);
      if (remove) {
        service.archiveDownloadInfos.remove(1);
      } else {
        service.archiveDownloadInfos[1]!.archiveStatus = ArchiveStatus.paused;
        service.archiveDownloadInfos[1]!.cancelToken = CancelToken();
      }
      await failure;
      expect(service.calls, [1]);
      expect(service.isBatchUpdateManaged(1), isFalse);
    }
  });

  test('owned retry policy remains in effect after wake then paused failure',
      () async {
    final service = LifecycleArchiveService()..add(1);
    final running = service.runRegisteredArchiveUpdate(1);
    final failure = expectLater(running, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    service.archiveDownloadInfos[1]!.archiveStatus =
        ArchiveStatus.parsingDownloadUrl;
    expect(service.isBatchUpdateManaged(1), isTrue);
    service.archiveDownloadInfos[1]!.archiveStatus = ArchiveStatus.paused;
    await failure;
    expect(service.isBatchUpdateManaged(1), isFalse);
  });
}
