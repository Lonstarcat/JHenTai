import 'package:flutter/foundation.dart';

class DownloadTaskNavigationTarget {
  final String taskType;

  const DownloadTaskNavigationTarget({required this.taskType});
}

/// A lightweight bridge used when an Android notification opens an existing
/// DownloadPage. A new object is assigned on every tap so repeated taps notify.
final ValueNotifier<DownloadTaskNavigationTarget?>
    downloadTaskNavigationTarget = ValueNotifier(null);

/// Kept separate from [downloadTaskNavigationTarget] because DownloadPage may
/// consume the requested download/archive segment while it is still offstage.
/// The outer layout consumes this flag to expose its existing download tab.
final ValueNotifier<bool> downloadPageNavigationPending = ValueNotifier(false);

void requestDownloadTaskNavigation(String taskType) {
  downloadTaskNavigationTarget.value =
      DownloadTaskNavigationTarget(taskType: taskType);
  if (downloadPageNavigationPending.value) {
    downloadPageNavigationPending.value = false;
  }
  downloadPageNavigationPending.value = true;
}

void completeDownloadPageNavigation() {
  downloadPageNavigationPending.value = false;
}

void retryPendingDownloadPageNavigation() {
  if (!downloadPageNavigationPending.value) {
    return;
  }
  downloadPageNavigationPending.value = false;
  downloadPageNavigationPending.value = true;
}
