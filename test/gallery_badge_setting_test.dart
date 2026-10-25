import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/pages/setting/style/setting_style_page.dart';
import 'package:jhentai/src/setting/style_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('old or malformed config defaults on; explicit false round-trips',
      () async {
    final writes = <Map<String, dynamic>>[];
    final setting = StyleSetting(configWriter: (config) async {
      writes.add(jsonDecode(config) as Map<String, dynamic>);
      return 1;
    });
    final old = jsonDecode(setting.toConfigString()) as Map<String, dynamic>;
    old.remove('showAdsBadge');
    old.remove('showAiBadge');
    setting.applyBeanConfig(jsonEncode(old));
    expect(setting.showAdsBadge.value, isTrue);
    expect(setting.showAiBadge.value, isTrue);
    for (final malformed in [null, 1, 'false', []]) {
      setting.applyBeanConfig(jsonEncode(
          {...old, 'showAdsBadge': malformed, 'showAiBadge': malformed}));
      expect(setting.showAdsBadge.value, isTrue);
      expect(setting.showAiBadge.value, isTrue);
    }
    await setting.saveShowAdsBadge(false);
    expect(writes.last['showAdsBadge'], isFalse);
    expect(writes.last['showAiBadge'], isTrue);
    await setting.saveShowAiBadge(false);
    expect(writes.last['showAiBadge'], isFalse);
    final restored = StyleSetting()..applyBeanConfig(setting.toConfigString());
    expect(restored.showAdsBadge.value, isFalse);
    expect(restored.showAiBadge.value, isFalse);
    await setting.saveShowAdsBadge(true);
    expect(writes.last['showAdsBadge'], isTrue);
    expect(writes.last['showAiBadge'], isFalse);
  });

  testWidgets('Appearance exposes independent saved badge switches',
      (tester) async {
    final previous = styleSetting;
    final writes = <Map<String, dynamic>>[];
    styleSetting = StyleSetting(configWriter: (config) async {
      writes.add(jsonDecode(config) as Map<String, dynamic>);
      return 1;
    });
    addTearDown(() => styleSetting = previous);
    await tester.pumpWidget(GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        translations: LocaleText(),
        home: const SettingStylePage()));
    final ads = find.widgetWithText(SwitchListTile, '显示广告标识');
    final ai = find.widgetWithText(SwitchListTile, '显示 AI 生成标识');
    expect(ads, findsOneWidget);
    expect(ai, findsOneWidget);
    await tester.ensureVisible(ads);
    await tester.tap(ads);
    await tester.pumpAndSettle();
    expect(styleSetting.showAdsBadge.value, isFalse);
    expect(styleSetting.showAiBadge.value, isTrue);
    await tester.ensureVisible(ai);
    await tester.tap(ai);
    await tester.pumpAndSettle();
    expect(writes.last['showAdsBadge'], isFalse);
    expect(writes.last['showAiBadge'], isFalse);
    expect(tester.takeException(), isNull);
  });
}
