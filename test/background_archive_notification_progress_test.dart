import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/consts/app_identity.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/background_task_service.dart';
import 'package:jhentai/src/service/batch_update_background_bridge.dart';
import 'package:jhentai/src/service/gallery_download/gallery_download_service.dart';
import 'package:jhentai/src/utils/byte_util.dart';
import 'package:jhentai/src/utils/speed_computer.dart';

/// Keep production notification aggregation/control; replace only the pause
/// and resume effects so the test never touches files, a database or network.
class NotificationArchiveService extends ArchiveDownloadService {
  @override
  Future<void> pauseDownloadArchive(int gid,
      {bool needReUnlock = false}) async {
    archiveDownloadInfos[gid]!.archiveStatus = ArchiveStatus.paused;
  }

  @override
  Future<void> resumeDownloadArchive(int gid) async {
    archiveDownloadInfos[gid]!.archiveStatus = ArchiveStatus.downloading;
  }
}

void main() {
  testWidgets(
      'large archive production payload stays safe through its lifecycle',
      (tester) async {
    const int gib = 1024 * 1024 * 1024;
    final int current = (2.91 * gib).round();
    final int total = (4.72 * gib).round();
    final speed = SpeedComputer()
      ..resetDownloadedBytes(current)
      ..speedBytesPerSecond = 8.05 * 1024 * 1024;
    final info = ArchiveDownloadInfo(
        size: total,
        parseSource: 1,
        archiveStatus: ArchiveStatus.downloading,
        cancelToken: CancelToken(),
        speedComputer: speed,
        sortOrder: 0,
        group: 'test');
    final archiveService = NotificationArchiveService();
    archiveService.archives.add(ArchiveDownloadedData(
        gid: 1,
        token: 'test-token',
        title: 'Large archive',
        category: 'Manga',
        pageCount: 48,
        galleryUrl: 'https://example.invalid/g/1/test/',
        coverUrl: 'https://example.invalid/cover.jpg',
        size: total,
        publishTime: '2026-10-19',
        archiveStatusCode: ArchiveStatus.downloading.code,
        archivePageUrl: 'https://example.invalid/archive/1',
        isOriginal: true,
        insertTime: '2026-10-19',
        sortOrder: 0,
        groupName: 'test',
        tags: '{}',
        parseSource: 1));
    archiveService.archiveDownloadInfos[1] = info;
    final previousArchives = archiveDownloadService;
    final previousGalleries = galleryDownloadService;
    final previousBatch = batchUpdateBackgroundSnapshot.value;
    archiveDownloadService = archiveService;
    galleryDownloadService = GalleryDownloadService();
    batchUpdateBackgroundSnapshot.value = null;
    const channel = MethodChannel(AppIdentity.backgroundTasksChannel);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      archiveDownloadService = previousArchives;
      galleryDownloadService = previousGalleries;
      batchUpdateBackgroundSnapshot.value = previousBatch;
      speed.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    Map<dynamic, dynamic> payload() =>
        calls.lastWhere((call) => call.method == 'show').arguments as Map;
    final service = BackgroundTaskService();
    await service.refreshNotificationForTesting();
    expect(payload()['max'], 10000);
    expect(payload()['progress'], 6165);
    expect(payload()['showProgress'], isTrue);
    expect(payload()['indeterminate'], isFalse);
    expect(payload()['taskType'], 'archive');
    expect(payload()['primaryTitle'], 'Large archive');
    expect(payload()['primaryDetail'], contains('2.91GB / 4.72GB'));
    expect(payload()['speedText'], contains('8.05MB/s'));
    expect(payload()['showAction'], isTrue);

    await service.toggleAllFromNotification();
    await service.refreshNotificationForTesting();
    expect(info.archiveStatus, ArchiveStatus.paused);
    expect(payload()['paused'], isTrue);
    expect(payload()['progress'], 6165);
    expect(payload()['showProgress'], isTrue);
    expect(payload()['taskType'], 'archive');
    await service.toggleAllFromNotification();
    await service.refreshNotificationForTesting();
    expect(info.archiveStatus, ArchiveStatus.downloading);
    expect(payload()['paused'], isFalse);
    expect(payload()['progress'], 6165);

    for (final bytes in [2 * gib - 1, 2 * gib, 4 * gib - 1, 4 * gib]) {
      speed.resetDownloadedBytes(bytes);
      await service.refreshNotificationForTesting();
      expect(payload()['max'], 10000);
      expect(payload()['progress'] / payload()['max'],
          closeTo(bytes / total, .0001));
      expect(
          payload()['primaryDetail'], contains(byte2String(bytes.toDouble())));
    }
    info.size = 0;
    await service.refreshNotificationForTesting();
    expect(payload()['max'], 0);
    expect(payload()['progress'], 0);
    expect(payload()['indeterminate'], isTrue);
    expect(payload()['showProgress'], isTrue);

    info.size = total;
    speed.resetDownloadedBytes(total + 1);
    await service.refreshNotificationForTesting();
    expect(payload()['progress'], 10000);
    // The notification clamps display values only, not real byte counters.
    expect(speed.downloadedBytes, total + 1);
    expect(info.size, total);

    info.archiveStatus = ArchiveStatus.completed;
    await service.refreshNotificationForTesting();
    expect(payload()['showProgress'], isFalse);
    expect(payload()['indeterminate'], isFalse);
    expect(payload()['ongoing'], isFalse);
    expect(payload()['showAction'], isFalse);
    await tester.pump(const Duration(seconds: 8));
    expect(calls.last.method, 'cancel');
  });
}
