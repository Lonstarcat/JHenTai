enum BackgroundTaskType {
  download,
  archiveDownload,
  favorite,
}

enum BackgroundTaskStatus {
  waiting,
  running,
  paused,
  completed,
  failed,
  cancelled,
}

class BackgroundTaskInfo {
  final String id;
  final BackgroundTaskType type;
  final BackgroundTaskStatus status;
  final int? galleryId;
  final String title;
  final int current;
  final int total;
  final double progress;
  final double? speedBytesPerSecond;
  final int successCount;
  final int failCount;

  const BackgroundTaskInfo({
    required this.id,
    required this.type,
    required this.status,
    this.galleryId,
    required this.title,
    required this.current,
    required this.total,
    required this.progress,
    this.speedBytesPerSecond,
    this.successCount = 0,
    this.failCount = 0,
  });
}

class BackgroundFavoriteItem {
  final int gid;
  final String token;
  final String title;

  const BackgroundFavoriteItem(
      {required this.gid, required this.token, required this.title});
}
