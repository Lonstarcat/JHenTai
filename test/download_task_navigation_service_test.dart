import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/service/download_task_navigation_service.dart';

void main() {
  setUp(() {
    downloadTaskNavigationTarget.value = null;
    completeDownloadPageNavigation();
  });

  tearDown(() {
    downloadTaskNavigationTarget.value = null;
    completeDownloadPageNavigation();
  });

  test('notification navigation requests the archive tab and outer layout', () {
    requestDownloadTaskNavigation('archive');

    expect(downloadTaskNavigationTarget.value?.taskType, 'archive');
    expect(downloadPageNavigationPending.value, isTrue);
  });

  test('repeated notification taps notify the outer layout again', () {
    int notifications = 0;
    void listener() => notifications++;
    downloadPageNavigationPending.addListener(listener);

    requestDownloadTaskNavigation('download');
    requestDownloadTaskNavigation('archive');

    downloadPageNavigationPending.removeListener(listener);
    expect(notifications, 3);
    expect(downloadPageNavigationPending.value, isTrue);
    expect(downloadTaskNavigationTarget.value?.taskType, 'archive');
  });

  test('pending navigation can be retriggered after unlocking', () {
    requestDownloadTaskNavigation('download');
    int notifications = 0;
    void listener() => notifications++;
    downloadPageNavigationPending.addListener(listener);

    retryPendingDownloadPageNavigation();

    downloadPageNavigationPending.removeListener(listener);
    expect(notifications, 2);
    expect(downloadPageNavigationPending.value, isTrue);
  });
}
