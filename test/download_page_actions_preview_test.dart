import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_page_actions.dart';
import 'package:jhentai/src/pages/setting/style/download_page_actions_setting_page.dart';
import 'package:jhentai/src/pages/setting/style/widget/download_page_actions_preview.dart';
import 'package:jhentai/src/setting/style_setting.dart';

Finder get _menu => find.byKey(const ValueKey('download-page-preview-menu'));
Finder get _external =>
    find.byKey(const ValueKey('download-page-preview-external'));
Finder _entry(DownloadPageAction action) => find.byWidgetPredicate((widget) =>
    widget is PopupMenuItem<DownloadPageAction> && widget.value == action);

Future<void> _mount(WidgetTester tester, StyleSetting settings) async {
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('zh', 'CN'),
    translations: LocaleText(),
    home: DownloadPageActionsSettingPage(settings: settings),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  testWidgets(
      'selector is compact; same-row preview stays at right; popup balanced',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await _mount(tester, settings);
    final field = tester
        .getRect(find.byKey(const ValueKey('download-page-external-selector')));
    final preview = tester
        .getRect(find.byKey(const ValueKey('download-page-actions-preview')));
    expect(field.width, lessThan(300));
    expect(preview.right,
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 16);
    expect(field.center.dy, closeTo(preview.center.dy, 1));
    expect(preview.left - field.right, greaterThanOrEqualTo(12));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final option = find.byWidgetPredicate(
        (w) => w is DropdownMenuItem<String> && w.value == 'switchView');
    final text = find.descendant(of: option, matching: find.text('切换列表/网格视图'));
    final optionRect = tester.getRect(option);
    final textRect = tester.getRect(text);
    expect(textRect.left - optionRect.left,
        closeTo(optionRect.right - textRect.right, 1));
    expect(optionRect.width, lessThan(350));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview reflects external selection, toggles, order and reset',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await _mount(tester, settings);
    expect(tester.widget<IconButton>(_external).icon,
        isA<Icon>().having((i) => i.icon, 'icon', Icons.search));
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    dropdown.onChanged!('pauseAll');
    await tester.pumpAndSettle();
    expect(
        (tester.widget<IconButton>(_external).icon as Icon).icon, Icons.pause);
    await settings.updateDownloadPageActions(
        (c) => c.toggle(DownloadPageAction.multiSelect, false).reorder(6, 0));
    await tester.pumpAndSettle();
    await tester.tap(_menu);
    await tester.pumpAndSettle();
    final entries = tester
        .widgetList<PopupMenuItem<DownloadPageAction>>(
            find.byType(PopupMenuItem<DownloadPageAction>))
        .toList();
    expect(entries.first.value, DownloadPageAction.search);
    expect(entries.map((e) => e.value),
        isNot(contains(DownloadPageAction.pauseAll)));
    expect(entries.map((e) => e.value),
        isNot(contains(DownloadPageAction.multiSelect)));
    expect(
        tester
            .widget<PopupMenuItem<DownloadPageAction>>(
                _entry(DownloadPageAction.batchUpdateTask))
            .enabled,
        isFalse);
    await tester.tap(_entry(DownloadPageAction.search));
    await tester.pumpAndSettle();
    await settings.updateDownloadPageActions((c) => c.withExternal(null));
    await tester.pumpAndSettle();
    expect(_external, findsNothing);
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    expect(
        (tester.widget<IconButton>(_external).icon as Icon).icon, Icons.search);
    await settings.updateDownloadPageActions(
        (c) => c.toggle(DownloadPageAction.search, false));
    await tester.pumpAndSettle();
    expect(_external, findsNothing);
    await settings.updateDownloadPageActions((c) {
      for (final action in c.order) {
        c = c.toggle(action, false);
      }
      return c;
    });
    await tester.pumpAndSettle();
    expect(tester.widget<PopupMenuButton<DownloadPageAction>>(_menu).enabled,
        isFalse);
    await tester.tap(_menu);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<DownloadPageAction>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every preview click is inert: no settings writes or navigation',
      (tester) async {
    int writes = 0;
    final settings = StyleSetting(configWriter: (_) async {
      writes++;
      return 1;
    });
    await _mount(tester, settings);
    final before = settings.toConfigString();
    await tester.tap(_external);
    await tester.pumpAndSettle();
    for (final action in settings.downloadPageActions.value.menuActions) {
      await tester.tap(_menu);
      await tester.pumpAndSettle();
      if (action == DownloadPageAction.batchUpdateTask) {
        await tester.tap(_entry(action));
        await tester.pumpAndSettle();
        expect(_entry(action), findsOneWidget);
        await tester.tap(_entry(DownloadPageAction.switchView));
      } else {
        await tester.tap(_entry(action));
      }
      await tester.pumpAndSettle();
    }
    expect(writes, 0);
    expect(settings.toConfigString(), before);
    expect(find.byType(DownloadPageActionsSettingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending save rollback restores preview without extra writes',
      (tester) async {
    final gate = Completer<void>();
    int writes = 0;
    final settings = StyleSetting(configWriter: (_) async {
      writes++;
      await gate.future;
      return 0;
    });
    await _mount(tester, settings);
    final save = settings.updateDownloadPageActions(
        (c) => c.withExternal(DownloadPageAction.pauseAll));
    final failed = expectLater(save, throwsStateError);
    await tester.pump();
    expect(
        (tester.widget<IconButton>(_external).icon as Icon).icon, Icons.pause);
    await tester.tap(_external);
    gate.complete();
    await failed;
    await tester.pumpAndSettle();
    expect(
        (tester.widget<IconButton>(_external).icon as Icon).icon, Icons.search);
    expect(writes, 1);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
    Locale('ko', 'KR'),
    Locale('pt', 'BR'),
    Locale('ru', 'RU')
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('settings/preview at 320px, $locale scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settings = StyleSetting(configWriter: (_) async => 1);
        for (final dark in [false, true]) {
          await tester.pumpWidget(GetMaterialApp(
            locale: locale,
            translations: LocaleText(),
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: const Size(320, 800),
                  textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: DownloadPageActionsSettingPage(settings: settings),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(DownloadPageActionsPreview), findsOneWidget);
          await tester.tap(_menu);
          await tester.pumpAndSettle();
          expect(find.byType(PopupMenuItem<DownloadPageAction>), findsWidgets);
          expect(tester.takeException(), isNull);
          Navigator.of(tester.element(_menu)).pop();
          await tester.pumpAndSettle();
        }
      });
    }
  }
}
