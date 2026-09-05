import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../database/database.dart';
import '../model/background_task_info.dart';
import '../network/eh_request.dart';
import '../setting/favorite_setting.dart';
import '../setting/user_setting.dart';
import '../utils/byte_util.dart';
import '../utils/background_task_control_util.dart';
import '../utils/toast_util.dart';
import 'archive_download_service.dart';
import 'download_task_navigation_service.dart';
import 'gallery_download/gallery_download_service.dart';
import 'jh_service.dart';
import 'log.dart';

BackgroundTaskService backgroundTaskService = BackgroundTaskService();

/// Aggregates existing download state for Android and owns the temporary
/// sequential favorite queue. Download execution remains in the original
/// services; notification refresh is deliberately throttled to once a second.
class BackgroundTaskService
    with JHLifeCircleBeanErrorCatch
    implements JHLifeCircleBean {
  static const MethodChannel _channel =
      MethodChannel('top.jtmonster.jhentai.background_tasks');
  static const Duration _refreshInterval = Duration(seconds: 1);
  static const Duration _favoriteInterval = Duration(seconds: 3);

  Timer? _completionCancelTimer;
  bool _refreshing = false;
  bool _permissionRequested = false;
  bool _notificationVisible = false;
  bool _controlActionInFlight = false;
  bool _globallyPaused = false;
  bool _snapshotInitialized = false;

  final Set<int> _galleryPausedByNotification = <int>{};
  final Set<int> _archivePausedByNotification = <int>{};
  final Map<int, DownloadStatus> _previousGalleryStatuses =
      <int, DownloadStatus>{};
  final Map<int, ArchiveStatus> _previousArchiveStatuses =
      <int, ArchiveStatus>{};
  BackgroundTaskType? _preferredTaskType;
  int? _preferredTaskGid;

  List<BackgroundFavoriteItem> _favoriteItems = const [];
  int _favoriteIndex = 0;
  int _favoriteSuccessCount = 0;
  int _favoriteFailCount = 0;
  int? _favoriteTagIndex;
  String _favoriteTagName = '';
  String _favoriteNote = '';
  String _favoriteCurrentTitle = '';
  BackgroundTaskStatus? _favoriteStatus;
  Future<void>? _favoriteRunner;
  String? _favoriteCompletionPending;
  final List<({int gid, String title, String reason})> favoriteFailures = [];

  bool get isFavoriteTaskActive =>
      _favoriteStatus == BackgroundTaskStatus.running ||
      _favoriteStatus == BackgroundTaskStatus.waiting ||
      _favoriteStatus == BackgroundTaskStatus.paused;

  bool get isGloballyPaused => _globallyPaused;

  @override
  List<JHLifeCircleBean> get initDependencies => [
        galleryDownloadService,
        archiveDownloadService,
        favoriteSetting,
        userSetting,
        ehRequest,
        log,
      ];

  @override
  Future<void> doInitBean() async {
    if (!Platform.isAndroid) {
      return;
    }
    _channel.setMethodCallHandler(_handleNativeMethod);
  }

  @override
  Future<void> doAfterBeanReady() async {
    if (!Platform.isAndroid) {
      return;
    }
    Timer.periodic(_refreshInterval, (_) => _refreshNotification());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final Object? action =
            await _channel.invokeMethod<Object?>('getInitialAction');
        if (action is Map) {
          _openTaskFromNotification(action);
        }
      } on PlatformException catch (e) {
        log.warning('Read initial background notification action failed', e);
      }
      _refreshNotification(force: true);
    });
  }

  Future<void> _handleNativeMethod(MethodCall call) async {
    switch (call.method) {
      case 'togglePause':
        await toggleAllFromNotification();
        break;
      case 'openTask':
        if (call.arguments is Map) {
          _openTaskFromNotification(call.arguments as Map);
        }
        break;
    }
  }

  void _openTaskFromNotification(Map<dynamic, dynamic> arguments) {
    final String taskType = arguments['taskType']?.toString() ?? 'download';
    requestDownloadTaskNavigation(taskType);
  }

  bool startBatchFavorite({
    required List<BackgroundFavoriteItem> items,
    required int favoriteTagIndex,
    required String favoriteTagName,
    String note = '',
  }) {
    if (items.isEmpty || isFavoriteTaskActive || _favoriteRunner != null) {
      return false;
    }

    _favoriteItems = List.unmodifiable(items);
    _favoriteIndex = 0;
    _favoriteSuccessCount = 0;
    _favoriteFailCount = 0;
    _favoriteTagIndex = favoriteTagIndex;
    _favoriteTagName = favoriteTagName;
    _favoriteNote = note;
    _favoriteCurrentTitle = '';
    _favoriteStatus = BackgroundTaskStatus.running;
    _favoriteCompletionPending = null;
    favoriteFailures.clear();
    _favoriteRunner =
        _runBatchFavorite().whenComplete(() => _favoriteRunner = null);
    _refreshNotification(force: true);
    return true;
  }

  Future<void> _runBatchFavorite() async {
    try {
      for (int index = 0; index < _favoriteItems.length; index++) {
        await _waitUntilFavoriteResumed();
        final BackgroundFavoriteItem item = _favoriteItems[index];
        _favoriteCurrentTitle =
            item.title.trim().isEmpty ? 'untitledGallery'.tr : item.title;
        _refreshNotification(force: true);

        Object? lastError;
        bool success = false;
        for (int attempt = 0; attempt < 2; attempt++) {
          await _waitUntilFavoriteResumed();
          try {
            await ehRequest.requestAddFavorite(
                item.gid, item.token, _favoriteTagIndex!, _favoriteNote);
            success = true;
            break;
          } catch (e, stack) {
            lastError = e;
            log.error(
                'Batch favorite failed (gid=${item.gid}, attempt=${attempt + 1})',
                e,
                stack);
            if (attempt == 0) {
              await _pauseAwareDelay(const Duration(seconds: 1));
            }
          }
        }

        if (success) {
          _favoriteSuccessCount++;
        } else {
          _favoriteFailCount++;
          favoriteFailures.add((
            gid: item.gid,
            title: item.title,
            reason: lastError?.toString() ?? 'unknown'
          ));
        }
        _favoriteIndex = index + 1;
        _refreshNotification(force: true);

        if (index + 1 < _favoriteItems.length) {
          await _pauseAwareDelay(_favoriteInterval);
        }
      }

      _favoriteStatus = _favoriteFailCount == 0
          ? BackgroundTaskStatus.completed
          : BackgroundTaskStatus.failed;
      _favoriteCompletionPending = _favoriteFailCount == 0
          ? '${'batchFavoriteCompleted'.tr}: ${'success'.tr} $_favoriteSuccessCount'
          : '${'batchFavoritePartialFailed'.tr}: ${'success'.tr} $_favoriteSuccessCount, ${'failed'.tr} $_favoriteFailCount';
      toast(_favoriteCompletionPending!, isShort: false);
      if (userSetting.hasLoggedIn()) {
        unawaited(favoriteSetting.fetchDataFromEH());
      }
    } catch (e, stack) {
      _favoriteStatus = BackgroundTaskStatus.failed;
      _favoriteCompletionPending = '${'batchFavoriteFailed'.tr}: $e';
      log.error('Batch favorite queue failed', e, stack);
      toast(_favoriteCompletionPending!, isShort: false);
    } finally {
      _favoriteCurrentTitle = '';
      await _refreshNotification(force: true);
    }
  }

  Future<void> _waitUntilFavoriteResumed() async {
    while (_favoriteStatus == BackgroundTaskStatus.paused) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Future<void> _pauseAwareDelay(Duration duration) async {
    int remainingMilliseconds = duration.inMilliseconds;
    while (remainingMilliseconds > 0) {
      await _waitUntilFavoriteResumed();
      final int slice =
          remainingMilliseconds > 200 ? 200 : remainingMilliseconds;
      await Future<void>.delayed(Duration(milliseconds: slice));
      if (_favoriteStatus != BackgroundTaskStatus.paused) {
        remainingMilliseconds -= slice;
      }
    }
  }

  void pauseFavoriteTask() {
    if (_favoriteStatus == BackgroundTaskStatus.running ||
        _favoriteStatus == BackgroundTaskStatus.waiting) {
      _favoriteStatus = BackgroundTaskStatus.paused;
    }
  }

  void resumeFavoriteTask() {
    if (_favoriteStatus == BackgroundTaskStatus.paused) {
      _favoriteStatus = BackgroundTaskStatus.running;
    }
  }

  Future<void> toggleAllFromNotification() async {
    if (_controlActionInFlight) {
      return;
    }
    _controlActionInFlight = true;
    try {
      if (_shouldShowResumeAction()) {
        await _resumeTasksPausedByNotification();
      } else {
        await _pauseRunningTasksFromNotification();
      }
    } catch (e, stack) {
      log.error('Toggle background tasks from notification failed', e, stack);
    } finally {
      _controlActionInFlight = false;
      await _refreshNotification(force: true);
    }
  }

  Future<void> _pauseRunningTasksFromNotification() async {
    _pruneNotificationControlledTasks();
    _galleryPausedByNotification.addAll(
      galleryDownloadService.galleryDownloadInfos.values
          .where((item) =>
              item.downloadProgress.downloadStatus ==
              DownloadStatus.downloading)
          .map((item) => item.gid),
    );
    _archivePausedByNotification.addAll(
      archiveDownloadService.archiveDownloadInfos.entries
          .where((entry) =>
              entry.value.archiveStatus.code > ArchiveStatus.paused.code &&
              entry.value.archiveStatus.code < ArchiveStatus.downloaded.code)
          .map((entry) => entry.key),
    );
    final bool pauseFavorite =
        _favoriteStatus == BackgroundTaskStatus.running ||
            _favoriteStatus == BackgroundTaskStatus.waiting;

    pauseFavoriteTask();
    await Future.wait<void>([
      galleryDownloadService.pauseAllDownloadGallery(),
      archiveDownloadService.pauseAllDownloadArchive(),
    ]);

    _galleryPausedByNotification.removeWhere(
      (gid) =>
          galleryDownloadService
              .galleryDownloadInfos[gid]?.downloadProgress.downloadStatus !=
          DownloadStatus.paused,
    );
    _archivePausedByNotification.removeWhere(
      (gid) =>
          archiveDownloadService.archiveDownloadInfos[gid]?.archiveStatus !=
          ArchiveStatus.paused,
    );
    _globallyPaused = _galleryPausedByNotification.isNotEmpty ||
        _archivePausedByNotification.isNotEmpty ||
        pauseFavorite;
  }

  Future<void> _resumeTasksPausedByNotification() async {
    final List<int> galleryGids = _galleryPausedByNotification.toList();
    final List<int> archiveGids = _archivePausedByNotification.toList();
    _galleryPausedByNotification.clear();
    _archivePausedByNotification.clear();
    _globallyPaused = false;
    resumeFavoriteTask();

    await Future.wait<void>([
      ...galleryGids.map((gid) async {
        if (galleryDownloadService
                .galleryDownloadInfos[gid]?.downloadProgress.downloadStatus ==
            DownloadStatus.paused) {
          await galleryDownloadService.resumeDownloadGalleryByGid(gid);
        }
      }),
      ...archiveGids.map((gid) async {
        if (archiveDownloadService.archiveDownloadInfos[gid]?.archiveStatus ==
            ArchiveStatus.paused) {
          await archiveDownloadService.resumeDownloadArchive(gid);
        }
      }),
    ]);
  }

  void _pruneNotificationControlledTasks() {
    _galleryPausedByNotification.removeWhere((gid) {
      final DownloadStatus? status = galleryDownloadService
          .galleryDownloadInfos[gid]?.downloadProgress.downloadStatus;
      return status != DownloadStatus.paused &&
          status != DownloadStatus.downloading;
    });
    _archivePausedByNotification.removeWhere((gid) {
      final ArchiveStatus? status =
          archiveDownloadService.archiveDownloadInfos[gid]?.archiveStatus;
      return status == null ||
          (status != ArchiveStatus.paused &&
              !(status.code > ArchiveStatus.paused.code &&
                  status.code < ArchiveStatus.downloaded.code));
    });
    _globallyPaused = _galleryPausedByNotification.isNotEmpty ||
        _archivePausedByNotification.isNotEmpty ||
        _favoriteStatus == BackgroundTaskStatus.paused;
  }

  bool _hasRunningTasks() {
    final bool galleryRunning =
        galleryDownloadService.galleryDownloadInfos.values.any((item) =>
            item.downloadProgress.downloadStatus == DownloadStatus.downloading);
    final bool archiveRunning =
        archiveDownloadService.archiveDownloadInfos.values.any((item) =>
            item.archiveStatus.code > ArchiveStatus.paused.code &&
            item.archiveStatus.code < ArchiveStatus.completed.code);
    final bool favoriteRunning =
        _favoriteStatus == BackgroundTaskStatus.running ||
            _favoriteStatus == BackgroundTaskStatus.waiting;
    return galleryRunning || archiveRunning || favoriteRunning;
  }

  bool _shouldShowResumeAction() => _globallyPaused && !_hasRunningTasks();

  List<GalleryDownloadInfo> _activeGalleryDownloads() {
    final List<GalleryDownloadInfo> items =
        galleryDownloadService.galleryDownloadInfos.values.where((item) {
      return item.downloadProgress.downloadStatus ==
              DownloadStatus.downloading ||
          (_globallyPaused &&
              _galleryPausedByNotification.contains(item.gid) &&
              item.downloadProgress.downloadStatus == DownloadStatus.paused);
    }).toList();
    items.sort((a, b) {
      if (_preferredTaskType == BackgroundTaskType.download) {
        if (a.gid == _preferredTaskGid) {
          return -1;
        }
        if (b.gid == _preferredTaskGid) {
          return 1;
        }
      }
      final int running = (b.downloadProgress.downloadStatus ==
                  DownloadStatus.downloading
              ? 1
              : 0)
          .compareTo(
              a.downloadProgress.downloadStatus == DownloadStatus.downloading
                  ? 1
                  : 0);
      if (running != 0) {
        return running;
      }
      final int speed = b.speedComputer.speedBytesPerSecond
          .compareTo(a.speedComputer.speedBytesPerSecond);
      return speed != 0 ? speed : a.priority.compareTo(b.priority);
    });
    return items;
  }

  List<ArchiveDownloadedData> _activeArchiveDownloads() {
    final List<ArchiveDownloadedData> items =
        archiveDownloadService.archives.where((archive) {
      final ArchiveStatus? status = archiveDownloadService
          .archiveDownloadInfos[archive.gid]?.archiveStatus;
      if (status == null) {
        return false;
      }
      return (status.code > ArchiveStatus.paused.code &&
              status.code < ArchiveStatus.completed.code) ||
          (_globallyPaused &&
              _archivePausedByNotification.contains(archive.gid) &&
              status == ArchiveStatus.paused);
    }).toList();
    items.sort((a, b) {
      if (_preferredTaskType == BackgroundTaskType.archiveDownload) {
        if (a.gid == _preferredTaskGid) {
          return -1;
        }
        if (b.gid == _preferredTaskGid) {
          return 1;
        }
      }
      final ArchiveStatus aStatus =
          archiveDownloadService.archiveDownloadInfos[a.gid]!.archiveStatus;
      final ArchiveStatus bStatus =
          archiveDownloadService.archiveDownloadInfos[b.gid]!.archiveStatus;
      final int running = (bStatus == ArchiveStatus.paused ? 0 : 1)
          .compareTo(aStatus == ArchiveStatus.paused ? 0 : 1);
      if (running != 0) {
        return running;
      }
      final double aSpeed = archiveDownloadService
              .archiveDownloadInfos[a.gid]?.speedComputer.speedBytesPerSecond ??
          0;
      final double bSpeed = archiveDownloadService
              .archiveDownloadInfos[b.gid]?.speedComputer.speedBytesPerSecond ??
          0;
      return bSpeed.compareTo(aSpeed);
    });
    return items;
  }

  BackgroundTaskInfo _galleryTaskInfo(GalleryDownloadInfo item) {
    final GalleryDownloadProgress progress = item.downloadProgress;
    final bool paused = progress.downloadStatus == DownloadStatus.paused;
    return BackgroundTaskInfo(
      id: 'download:${item.gid}',
      type: BackgroundTaskType.download,
      status:
          paused ? BackgroundTaskStatus.paused : BackgroundTaskStatus.running,
      galleryId: item.gid,
      title: item.title.trim().isEmpty ? 'untitledGallery'.tr : item.title,
      current: progress.curCount,
      total: progress.totalCount,
      progress: progress.totalCount <= 0
          ? 0
          : progress.curCount / progress.totalCount,
      speedBytesPerSecond: item.speedComputer.speedBytesPerSecond,
    );
  }

  BackgroundTaskInfo _archiveTaskInfo(ArchiveDownloadedData archive) {
    final ArchiveDownloadInfo info =
        archiveDownloadService.archiveDownloadInfos[archive.gid]!;
    final int current =
        info.downloadTask?.currentBytes ?? info.speedComputer.downloadedBytes;
    final int total = info.size;
    return BackgroundTaskInfo(
      id: 'archive:${archive.gid}',
      type: BackgroundTaskType.archiveDownload,
      status: info.archiveStatus == ArchiveStatus.paused
          ? BackgroundTaskStatus.paused
          : BackgroundTaskStatus.running,
      galleryId: archive.gid,
      title:
          archive.title.trim().isEmpty ? 'untitledGallery'.tr : archive.title,
      current: current,
      total: total,
      progress: total <= 0 ? 0 : current / total,
      speedBytesPerSecond: info.speedComputer.speedBytesPerSecond,
    );
  }

  BackgroundTaskInfo? _favoriteTaskInfo() {
    if (!isFavoriteTaskActive) {
      return null;
    }
    return BackgroundTaskInfo(
      id: 'favorite:batch',
      type: BackgroundTaskType.favorite,
      status: _favoriteStatus!,
      galleryId: _favoriteIndex < _favoriteItems.length
          ? _favoriteItems[_favoriteIndex].gid
          : null,
      title: _favoriteCurrentTitle.isEmpty
          ? 'batchFavorite'.tr
          : _favoriteCurrentTitle,
      current: _favoriteIndex,
      total: _favoriteItems.length,
      progress:
          _favoriteItems.isEmpty ? 0 : _favoriteIndex / _favoriteItems.length,
      successCount: _favoriteSuccessCount,
      failCount: _favoriteFailCount,
    );
  }

  List<String> _collectTerminalLines() {
    final List<String> lines = [];
    if (_snapshotInitialized) {
      for (final GalleryDownloadInfo item
          in galleryDownloadService.galleryDownloadInfos.values) {
        final DownloadStatus? previous = _previousGalleryStatuses[item.gid];
        final DownloadStatus current = item.downloadProgress.downloadStatus;
        if (previous != current && current == DownloadStatus.downloading) {
          if (_globallyPaused && !_controlActionInFlight) {
            // Starting one gallery manually while the notification queue is
            // paused transfers the resume target to that gallery. Older
            // notification-paused galleries remain manually paused instead
            // of unexpectedly restarting on the next Resume tap.
            replaceNotificationResumeTarget(
                _galleryPausedByNotification, item.gid);
          }
          _preferredTaskType = BackgroundTaskType.download;
          _preferredTaskGid = item.gid;
        }
        if (previous != current && current == DownloadStatus.downloaded) {
          if (_preferredTaskType == BackgroundTaskType.download &&
              _preferredTaskGid == item.gid) {
            _preferredTaskType = null;
            _preferredTaskGid = null;
          }
          lines.add('${'downloadCompleted'.tr}: ${item.title}');
        } else if (previous != current &&
            current == DownloadStatus.downloadFailed) {
          lines.add('${'downloadFailed'.tr}: ${item.title}');
        }
      }
      for (final ArchiveDownloadedData archive
          in archiveDownloadService.archives) {
        final ArchiveStatus? previous = _previousArchiveStatuses[archive.gid];
        final ArchiveStatus? current = archiveDownloadService
            .archiveDownloadInfos[archive.gid]?.archiveStatus;
        if (previous != current &&
            current != null &&
            current.code > ArchiveStatus.paused.code &&
            current.code < ArchiveStatus.completed.code) {
          if (_globallyPaused && !_controlActionInFlight) {
            replaceNotificationResumeTarget(
                _archivePausedByNotification, archive.gid);
          }
          _preferredTaskType = BackgroundTaskType.archiveDownload;
          _preferredTaskGid = archive.gid;
        }
        if (previous != current && current == ArchiveStatus.completed) {
          if (_preferredTaskType == BackgroundTaskType.archiveDownload &&
              _preferredTaskGid == archive.gid) {
            _preferredTaskType = null;
            _preferredTaskGid = null;
          }
          lines.add('${'archiveDownloadCompleted'.tr}: ${archive.title}');
        }
      }
    }

    _previousGalleryStatuses
      ..clear()
      ..addEntries(galleryDownloadService.galleryDownloadInfos.values.map(
          (item) => MapEntry(item.gid, item.downloadProgress.downloadStatus)));
    _previousArchiveStatuses
      ..clear()
      ..addEntries(archiveDownloadService.archiveDownloadInfos.entries
          .map((entry) => MapEntry(entry.key, entry.value.archiveStatus)));
    _snapshotInitialized = true;

    if (_favoriteCompletionPending != null) {
      lines.add(_favoriteCompletionPending!);
      _favoriteCompletionPending = null;
    }
    return lines;
  }

  Future<void> _refreshNotification({bool force = false}) async {
    if (!Platform.isAndroid || _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      _pruneNotificationControlledTasks();
      final List<String> terminalLines = _collectTerminalLines();
      final List<GalleryDownloadInfo> galleryItems = _activeGalleryDownloads();
      final List<ArchiveDownloadedData> archiveItems =
          _activeArchiveDownloads();
      final BackgroundTaskInfo? download =
          galleryItems.isEmpty ? null : _galleryTaskInfo(galleryItems.first);
      final BackgroundTaskInfo? archive =
          archiveItems.isEmpty ? null : _archiveTaskInfo(archiveItems.first);
      final BackgroundTaskInfo? favorite = _favoriteTaskInfo();
      final int taskCount = galleryItems.length +
          archiveItems.length +
          (favorite == null ? 0 : 1);

      if (taskCount == 0) {
        if (terminalLines.isNotEmpty) {
          await _showNativeNotification(
            title: 'backgroundTasksCompleted'.tr,
            content: terminalLines.first,
            lines: terminalLines,
            primary: null,
            ongoing: false,
            showAction: false,
          );
          _completionCancelTimer?.cancel();
          _completionCancelTimer =
              Timer(const Duration(seconds: 8), _cancelNativeNotification);
        } else if (_notificationVisible && _completionCancelTimer == null) {
          await _cancelNativeNotification();
        }
        return;
      }

      _completionCancelTimer?.cancel();
      _completionCancelTimer = null;
      final List<String> lines = [];
      if (download != null) {
        final String speed = _formatSpeed(download.speedBytesPerSecond);
        lines.add(
            '${'download'.tr}: ${download.title} · ${download.current}/${download.total}${speed.isEmpty ? '' : ' · $speed'}');
      }
      if (archive != null) {
        final String total =
            archive.total > 0 ? byte2String(archive.total.toDouble()) : '?';
        final String speed = _formatSpeed(archive.speedBytesPerSecond);
        lines.add(
            '${'archive'.tr}: ${archive.title} · ${byte2String(archive.current.toDouble())}/$total${speed.isEmpty ? '' : ' · $speed'}');
      }
      if (favorite != null) {
        lines.add(
          '${'batchFavorite'.tr} ($_favoriteTagName): ${favorite.title} · ${favorite.current}/${favorite.total} · ${'success'.tr} ${favorite.successCount} · ${'failed'.tr} ${favorite.failCount}',
        );
      }

      final BackgroundTaskInfo primary = switch (_preferredTaskType) {
        BackgroundTaskType.archiveDownload when archive != null => archive,
        BackgroundTaskType.favorite when favorite != null => favorite,
        BackgroundTaskType.download when download != null => download,
        _ => download ?? archive ?? favorite!,
      };
      final bool showResumeAction = _shouldShowResumeAction();
      final String content = taskCount == 1
          ? lines.first
          : '${'runningBackgroundTasks'.tr}: $taskCount · ${'download'.tr} ${galleryItems.length} · ${'archive'.tr} ${archiveItems.length} · ${'favorite'.tr} ${favorite == null ? 0 : 1}';
      await _showNativeNotification(
        title: showResumeAction
            ? 'backgroundTasksPaused'.tr
            : 'backgroundTasksRunning'.tr,
        content: content,
        lines: lines,
        primary: primary,
        ongoing: true,
        showAction: true,
        paused: showResumeAction,
      );
    } catch (e, stack) {
      log.error(
          'Refresh Android background task notification failed', e, stack);
    } finally {
      _refreshing = false;
    }
  }

  String _formatSpeed(double? bytesPerSecond) {
    if (bytesPerSecond == null || bytesPerSecond <= 0) {
      return '';
    }
    return '${byte2String(bytesPerSecond)}/s';
  }

  String _primaryDetail(BackgroundTaskInfo? primary, String fallback) {
    if (primary == null) {
      return fallback;
    }
    return switch (primary.type) {
      BackgroundTaskType.download =>
        '${'download'.tr} · ${primary.current} / ${primary.total}',
      BackgroundTaskType.archiveDownload =>
        '${'archive'.tr} · ${byte2String(primary.current.toDouble())} / ${primary.total > 0 ? byte2String(primary.total.toDouble()) : '?'}',
      BackgroundTaskType.favorite =>
        '${'batchFavorite'.tr} · ${primary.current} / ${primary.total} · ${'success'.tr} ${primary.successCount} · ${'failed'.tr} ${primary.failCount}',
    };
  }

  String _primarySpeed(BackgroundTaskInfo? primary) {
    if (primary == null || primary.type == BackgroundTaskType.favorite) {
      return '';
    }
    final String speed = _formatSpeed(primary.speedBytesPerSecond);
    return '${'notificationSpeed'.tr}: ${speed.isEmpty ? '0 B/s' : speed}';
  }

  Future<void> _showNativeNotification({
    required String title,
    required String content,
    required List<String> lines,
    required BackgroundTaskInfo? primary,
    required bool ongoing,
    required bool showAction,
    bool? paused,
  }) async {
    if (!_permissionRequested) {
      _permissionRequested = true;
      await _channel.invokeMethod<bool>('requestPermission');
    }
    final int max = primary?.total ?? 0;
    final int current = primary?.current ?? 0;
    final bool? shown = await _channel.invokeMethod<bool>('show', {
      'title': title,
      'content': content,
      'lines': lines,
      'primaryTitle': primary?.title ?? title,
      'primaryDetail': _primaryDetail(primary, content),
      'speedText': _primarySpeed(primary),
      'max': max,
      'progress': current,
      'indeterminate': ongoing && max <= 0,
      'ongoing': ongoing,
      'paused': paused ?? _globallyPaused,
      'showAction': showAction,
      'pauseLabel': 'notificationPause'.tr,
      'resumeLabel': 'notificationResume'.tr,
      'taskType': switch (primary?.type) {
        BackgroundTaskType.archiveDownload => 'archive',
        BackgroundTaskType.favorite => 'favorite',
        _ => 'download',
      },
    });
    _notificationVisible = shown == true;
  }

  Future<void> _cancelNativeNotification() async {
    _completionCancelTimer?.cancel();
    _completionCancelTimer = null;
    if (!_notificationVisible) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('cancel');
    } finally {
      _notificationVisible = false;
    }
  }
}
