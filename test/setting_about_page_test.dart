import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/consts/app_identity.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/pages/setting/about/setting_about_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('About release version stays synchronized with pubspec', () {
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    expect(AppIdentity.releaseVersion, '${version}e');
  });

  for (final build in ['341', '1341', '2341', '4341']) {
    testWidgets(
        'About shows enhanced release, attribution and repo order ($build)',
        (tester) async {
      Get.testMode = true;
      addTearDown(Get.reset);
      PackageInfo.setMockInitialValues(
        appName: 'JHenTai',
        packageName: AppIdentity.packageName,
        version: '8.0.18',
        buildNumber: build,
        buildSignature: '',
      );
      await tester.pumpWidget(GetMaterialApp(
        translations: LocaleText(),
        locale: const Locale('zh', 'CN'),
        home: const SettingAboutPage(),
      ));
      await tester.pumpAndSettle();
      expect(find.text('8.0.18+341e'), findsOneWidget);
      expect(find.text('酱天小禽兽(JTMonster)\nLonstarcat'), findsOneWidget);
      expect(find.text('上游仓库'), findsOneWidget);
      expect(find.text('Github'), findsOneWidget);
      expect(tester.getTopLeft(find.text(AppIdentity.upstreamRepository)).dy,
          lessThan(tester.getTopLeft(find.text(AppIdentity.repository)).dy));
      expect(find.text('Telegram(Chinese Mainly)'), findsOneWidget);
      expect(find.textContaining('https://t.me/+PindoE9yvIpmOWI9'),
          findsOneWidget);
      expect(find.text('https://github.com/jiangtian616/JHenTai/wiki'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
