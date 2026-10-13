import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/consts/app_identity.dart';
import 'package:jhentai/src/consts/jh_consts.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('Android app, namespace, manifests and provider agree', () {
    final gradle = source('android/app/build.gradle');
    expect(gradle, contains("namespace '${AppIdentity.packageName}'"));
    expect(gradle, contains('applicationId "${AppIdentity.packageName}"'));
    for (final mode in ['main', 'debug', 'profile']) {
      expect(source('android/app/src/$mode/AndroidManifest.xml'),
          contains('package="${AppIdentity.packageName}"'));
    }
    expect(source('android/app/src/main/AndroidManifest.xml'),
        contains(r'android:authorities="${applicationId}.provider"'));
  });
  test('moved Kotlin classes and Dart channels agree', () {
    const root = 'android/app/src/main/kotlin/com/lonstarcat/jhentai';
    for (final name in [
      'MainActivity',
      'BackgroundTaskActionReceiver',
      'BackgroundTaskNotificationManager',
      'BackgroundTaskNotificationBridge'
    ]) {
      expect(source('$root/$name.kt'),
          startsWith('package ${AppIdentity.packageName}'));
      expect(
          File('android/app/src/main/kotlin/top/jtmonster/jhentai/$name.kt')
              .existsSync(),
          isFalse);
    }
    final activity = source('$root/MainActivity.kt');
    expect(activity, contains('"${AppIdentity.volumeChannel}"'));
    expect(activity, contains('"${AppIdentity.backgroundTasksChannel}"'));
    expect(
        source('$root/BackgroundTaskNotificationManager.kt'),
        contains(
            '"${AppIdentity.packageName}.action.TOGGLE_BACKGROUND_TASKS"'));
    expect(source('lib/src/service/volume_service.dart'),
        contains('MethodChannel(AppIdentity.volumeChannel)'));
    expect(source('lib/src/service/background_task_service.dart'),
        contains('MethodChannel(AppIdentity.backgroundTasksChannel)'));
    expect(source('lib/src/pages/setting/advanced/setting_advanced_page.dart'),
        contains(r'package:${AppIdentity.packageName}'));
  });
  test('all Apple configurations use new bundle identity', () {
    final ios = source('ios/Runner.xcodeproj/project.pbxproj');
    expect(
        'PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.packageName};'
            .allMatches(ios)
            .length,
        3);
    expect(ios, isNot(contains('top.jtmonster.jhentai')));
    expect(source('macos/Runner/Configs/AppInfo.xcconfig'),
        contains('PRODUCT_BUNDLE_IDENTIFIER = ${AppIdentity.packageName}'));
    expect(
        source('pkg.sh'), contains('--identifier ${AppIdentity.packageName}'));
  });
  test('Windows storage identity is independent without removing attribution',
      () {
    final rc = source('windows/runner/Runner.rc');
    expect(rc, contains('"CompanyName", "com.lonstarcat"'));
    expect(rc, contains('Copyright (C) 2022 top.jtmonster.'));
  });
  test('Linux identity and desktop filename agree', () {
    expect(source('linux/CMakeLists.txt'),
        contains('set(APPLICATION_ID "${AppIdentity.packageName}")'));
    expect(source('linux/assets/${AppIdentity.packageName}.desktop'),
        contains('Icon=${AppIdentity.packageName}'));
    expect(source('linux/assets/AppImageBuilder.yml'),
        contains('id: ${AppIdentity.packageName}'));
    expect(source('.github/workflows/build_publish.yml'),
        isNot(contains('top.jtmonster.jhentai')));
  });
  test('all Obtainium links decode to enhanced package and repository', () {
    for (final path in ['README.md', 'README_cn.md', 'README_kr.md']) {
      final match =
          RegExp(r'obtainium://app/(\S+)(?=\))').firstMatch(source(path))!;
      final data = jsonDecode(Uri.decodeComponent(match.group(1)!))
          as Map<String, dynamic>;
      expect(data['id'], AppIdentity.packageName);
      expect(data['url'], AppIdentity.repository);
      final settings = jsonDecode(data['additionalSettings'] as String)
          as Map<String, dynamic>;
      expect(settings['about'], startsWith(AppIdentity.repository));
    }
  });
  test('AltSource does not claim an old IPA has the new bundle ID', () {
    final feed =
        jsonDecode(source('altsource/AltSource.json')) as Map<String, dynamic>;
    expect(feed['featuredApps'], [AppIdentity.packageName]);
    expect(feed['apps'][0]['bundleIdentifier'], AppIdentity.packageName);
    expect(feed['apps'][0]['versions'], isEmpty);
  });
  test('push workflow contains only Windows and does not publish tags', () {
    final workflow = source('.github/workflows/build_android_macos_test.yml');
    expect(
        RegExp(r'^  ([a-zA-Z0-9_-]+):$', multiLine: true)
            .allMatches(workflow.substring(workflow.indexOf('jobs:')))
            .map((m) => m.group(1))
            .toList(),
        ['windows']);
    expect(workflow, contains('feature/enhanced'));
    expect(workflow, isNot(contains('tags:')));
  });
  test('upstream server authentication is not an install package name', () {
    expect(JHConsts.APP_ID, 'jhentai');
    expect(AppIdentity.releasesApi,
        'https://api.github.com/repos/Lonstarcat/JHenTai/releases');
    expect(source('lib/src/service/schedule_service.dart'),
        contains('AppIdentity.releasesApi'));
    expect(source('lib/src/widget/update_dialog.dart'),
        contains('AppIdentity.releasesPage'));
  });
}
