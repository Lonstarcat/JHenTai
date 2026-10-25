/// Install identity and distribution source of the enhanced fork.
/// This is not the upstream server's X-App-Id authentication value.
abstract final class AppIdentity {
  static const String packageName = 'com.lonstarcat.jhentai';
  /// Human-facing release name, not Android's ABI-prefixed versionCode.
  /// The About-page test checks this against pubspec.yaml to prevent drift.
  static const String releaseVersion = '8.0.18+341e';
  static const String upstreamRepository = 'https://github.com/jiangtian616/JHenTai';
  static const String repository = 'https://github.com/Lonstarcat/JHenTai';
  static const String releasesPage = '$repository/releases';
  static const String releasesApi =
      'https://api.github.com/repos/Lonstarcat/JHenTai/releases';
  static const String volumeChannel = '$packageName.volume.event.intercept';
  static const String backgroundTasksChannel = '$packageName.background_tasks';
}
