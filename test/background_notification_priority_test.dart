import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/consts/app_identity.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/background_task_service.dart';
import 'package:jhentai/src/service/batch_update_background_bridge.dart';
import 'package:jhentai/src/service/gallery_download/gallery_download_service.dart';
import 'package:jhentai/src/utils/speed_computer.dart';

GalleryDownloadInfo gallery(int gid, {double speed = 0}) {
  final item = GalleryDownloadInfo(
    gid: gid,
    token: 'test',
    galleryUrl: 'https://example.invalid/g/$gid/test/',
    title: 'Gallery $gid',
    category: 'Manga',
    pageCount: 10,
    thumbnailsCountPerPage: 20,
    tasks: [],
    cancelToken: CancelToken(),
    downloadProgress: GalleryDownloadProgress(
        curCount: 2,
        totalCount: 10,
        downloadStatus: DownloadStatus.downloading),
    imageHrefs: [],
    priority: 0,
    sortOrder: gid,
    group: 'test',
    downloadOriginalImage: false,
    tags: '{}',
    tagRefreshTime: null,
    publishTime: '2026-10-24 00:00:00',
    insertTime: '2026-10-24 00:00:00',
    onSpeedUpdate: () {},
  );
  item.speedComputer.speedBytesPerSecond = speed;
  return item;
}

void main() {
  testWidgets(
      'production payload keeps real transfers ahead of latest queued tasks',
      (tester) async {
    final previousGallery = galleryDownloadService;
    final previousArchive = archiveDownloadService;
    final previousBatch = batchUpdateBackgroundSnapshot.value;
    final galleries = GalleryDownloadService();
    final archives = ArchiveDownloadService();
    galleryDownloadService = galleries;
    archiveDownloadService = archives;
    batchUpdateBackgroundSnapshot.value = null;
    final first = gallery(1, speed: 1024);
    final queued = gallery(2);
    galleries.galleryDownloadInfos[1] = first;
    final archiveSpeed = SpeedComputer()..resetDownloadedBytes(25);
    final archiveInfo = ArchiveDownloadInfo(
        size: 100,
        parseSource: 1,
        archiveStatus: ArchiveStatus.unlocking,
        cancelToken: CancelToken(),
        speedComputer: archiveSpeed,
        sortOrder: 0,
        group: 'test');
    const channel = MethodChannel(AppIdentity.backgroundTasksChannel);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      galleryDownloadService = previousGallery;
      archiveDownloadService = previousArchive;
      batchUpdateBackgroundSnapshot.value = previousBatch;
      first.speedComputer.dispose();
      queued.speedComputer.dispose();
      archiveSpeed.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    Map payload() =>
        calls.lastWhere((call) => call.method == 'show').arguments as Map;
    final service = BackgroundTaskService();
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Gallery 1');
    galleries.galleryDownloadInfos[2] = queued; // Becomes the preferred task.
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Gallery 1');
    expect(payload()['taskType'], 'download');
    expect(payload()['primaryDetail'], contains('2 / 10'));
    expect(payload()['speedText'], contains('1.00KB/s'));
    expect((payload()['lines'] as List).first, contains('Gallery 1'));

    archives.archives.add(ArchiveDownloadedData(
        gid: 3,
        token: 'test',
        title: 'Archive 3',
        category: 'Manga',
        pageCount: 10,
        galleryUrl: 'https://example.invalid/g/3/test/',
        coverUrl: '',
        size: 100,
        publishTime: '2026-10-24',
        archiveStatusCode: ArchiveStatus.unlocking.code,
        archivePageUrl: 'https://example.invalid/archive/3',
        isOriginal: true,
        insertTime: '2026-10-24',
        sortOrder: 0,
        groupName: 'test',
        tags: '{}',
        parseSource: 1));
    archives.archiveDownloadInfos[3] = archiveInfo;
    await service
        .refreshNotificationForTesting(); // Newly preferred archive is still preparing.
    expect(payload()['primaryTitle'], 'Gallery 1');
    archiveInfo.archiveStatus = ArchiveStatus.waitingIsolate;
    archiveSpeed.speedBytesPerSecond =
        100000; // Ignore stale speed outside transfer stage.
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Gallery 1');

    first.downloadProgress.downloadStatus = DownloadStatus.paused;
    archiveInfo.archiveStatus = ArchiveStatus.downloading;
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Archive 3');
    expect(payload()['taskType'], 'archive');
    expect(payload()['max'], 100);
    expect(payload()['progress'], 25);
    expect((payload()['lines'] as List).last, contains('Archive 3'));

    // A new ordinary task must not replace an archive that is transferring.
    queued.downloadProgress.downloadStatus = DownloadStatus.paused;
    await service.refreshNotificationForTesting();
    queued.downloadProgress.downloadStatus = DownloadStatus.downloading;
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Archive 3');
    expect(payload()['taskType'], 'archive');
    archiveInfo.archiveStatus = ArchiveStatus.completed;
    await service.refreshNotificationForTesting();
    expect(payload()['primaryTitle'], 'Gallery 2');
    expect(payload()['taskType'], 'download');
    queued.downloadProgress.downloadStatus = DownloadStatus.downloaded;
    await service.refreshNotificationForTesting();
    expect(payload()['showProgress'], isFalse);
    await tester.pump(const Duration(seconds: 8));
  });
}
