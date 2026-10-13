/// Install identity and distribution source of the enhanced fork.
/// This is not the upstream server's X-App-Id authentication value.
abstract final class AppIdentity {
  static const String packageName = 'com.lonstarcat.jhentai';
  static const String repository = 'https://github.com/Lonstarcat/JHenTai';
  static const String releasesPage = '$repository/releases';
  static const String releasesApi =
      'https://api.github.com/repos/Lonstarcat/JHenTai/releases';
  static const String volumeChannel = '$packageName.volume.event.intercept';
  static const String backgroundTasksChannel = '$packageName.background_tasks';
}
