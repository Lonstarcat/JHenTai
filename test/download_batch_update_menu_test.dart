import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/pages/download/widget/download_page_more_menu.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/utils/batch_update_util.dart';
import 'package:jhentai/src/widget/download_batch_update_dialog.dart';
import 'batch_update_fakes.dart';

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en', 'US'),
    const Locale('ru', 'RU')
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('persistent menu reacts while open: $locale scale $scale',
          (tester) async {
        Get.testMode = true;
        addTearDown(Get.reset);
        final retained = ValueNotifier(false);
        addTearDown(retained.dispose);
        int opened = 0;
        await tester.pumpWidget(GetMaterialApp(
          locale: locale,
          translations: LocaleText(),
          home: Scaffold(
              body: MediaQuery(
            data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(scale)),
            child: DownloadPageMoreMenu(
              switchViewIcon: Icons.view_list,
              switchViewLabel: 'List',
              onSwitchView: () {},
              onMultiSelect: () {},
              onResumeAll: () {},
              onPauseAll: () {},
              onSearch: () {},
              hasBatchUpdateTask: () => retained.value,
              batchUpdateTaskChanges: retained,
              onBatchUpdateTask: () => opened++,
            ),
          )),
        ));
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        final label = find.text('batchUpdateTask'.tr);
        final entry = find.ancestor(
            of: label,
            matching: find.byWidgetPredicate((w) => w is PopupMenuItem));
        final before = tester.getSize(entry).width;
        expect((tester.widget(entry) as PopupMenuItem).enabled, isFalse);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(opened, 0);
        expect(label, findsOneWidget);
        retained.value = true;
        await tester.pumpAndSettle();
        expect((tester.widget(entry) as PopupMenuItem).enabled, isTrue);
        expect(tester.getSize(entry).width, before);
        retained.value = false;
        await tester.pumpAndSettle();
        expect((tester.widget(entry) as PopupMenuItem).enabled, isFalse);
        expect(tester.getSize(entry).width, before);
        retained.value = true;
        await tester.pumpAndSettle();
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(opened, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('menu evaluates retained task at opening, callback once',
      (tester) async {
    bool hasTask = false;
    int opened = 0;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('en', 'US'),
      translations: LocaleText(),
      home: Scaffold(
          body: DownloadPageMoreMenu(
        switchViewIcon: Icons.view_list,
        switchViewLabel: 'List',
        onSwitchView: () {},
        onMultiSelect: () {},
        onResumeAll: () {},
        onPauseAll: () {},
        onSearch: () {},
        hasBatchUpdateTask: () => hasTask,
        onBatchUpdateTask: () => opened++,
      )),
    ));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('View update task'), findsOneWidget);
    final taskItem = find.ancestor(
        of: find.text('View update task'),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem));
    expect((tester.widget(taskItem) as PopupMenuItem).enabled, isFalse);
    final widthBefore = tester.getSize(taskItem).width;
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    hasTask = true; // No page rebuild required after a background check.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect((tester.widget(taskItem) as PopupMenuItem).enabled, isTrue);
    expect(tester.getSize(taskItem).width, widthBefore);
    await tester.tap(find.text('View update task'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('view existing task does not check, login, or overwrite results',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1, next: 11), 11: testDetail(11)});
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1)]);
    final flow = BatchUpdateFlow(service: service);
    final reads = List<int>.of(backend.reads);
    final items = service.items;
    expect(flow.hasSessionFor(DownloadToolbarKind.archive), isFalse);
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('en', 'US'),
      translations: LocaleText(),
      home: Scaffold(
          body: TextButton(
              onPressed: () {
                flow.openExisting(DownloadToolbarKind.gallery);
                flow.openExisting(DownloadToolbarKind.gallery);
              },
              child: const Text('Open'))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(DownloadBatchUpdateDialog), findsOneWidget);
    expect(find.textContaining('Check selected completed'), findsNothing);
    expect(backend.reads, reads);
    expect(identical(service.items, items), isTrue);
    expect(backend.submissions, isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(service.hasSessionFor(DownloadToolbarKind.gallery), isTrue);
    service.cancel();
    expect(service.hasSessionFor(DownloadToolbarKind.gallery), isTrue);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
