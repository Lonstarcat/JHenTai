import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/widget/batch_update_statistics.dart';
import 'package:jhentai/src/widget/download_batch_update_dialog.dart';
import 'batch_update_fakes.dart';

BatchUpdateItem item(int gid, BatchUpdateItemStatus status,
        {String? reason, bool target = true}) =>
    BatchUpdateItem(testSource(gid))
      ..status = status
      ..target = target ? testDetail(gid + 10) : null
      ..selected = true
      ..reason = reason;

List<BatchUpdateStatistic> counters(WidgetTester tester) => tester
    .widgetList<BatchUpdateStatistics>(find.byType(BatchUpdateStatistics))
    .singleWhere((widget) => widget.compact)
    .items;

Future<void> mount(WidgetTester tester, DownloadBatchUpdateService service,
    {Brightness brightness = Brightness.dark, double scale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  Get.testMode = true;
  addTearDown(Get.reset);
  await tester.pumpWidget(GetMaterialApp(
    locale: const Locale('zh', 'CN'),
    translations: LocaleText(),
    theme: ThemeData(brightness: brightness),
    builder: (context, child) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
        body: DownloadBatchUpdateDialog(service: service, onSubmit: () {})),
  ));
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
          'six ordered counters and read-only failure details: $brightness/$scale',
          (tester) async {
        final backend = FakeBatchBackend();
        final service = DownloadBatchUpdateService(backend)
          ..phase = BatchUpdatePhase.finished
          ..items = [
            item(1, BatchUpdateItemStatus.available),
            item(2, BatchUpdateItemStatus.failed,
                target: false, reason: 'batchUpdateQuoteFailed'),
            item(3, BatchUpdateItemStatus.failed),
            item(4, BatchUpdateItemStatus.submitted,
                reason: 'batchUpdateArchiveStopped'),
            item(5, BatchUpdateItemStatus.existing),
            item(6, BatchUpdateItemStatus.latest, target: false),
            item(7, BatchUpdateItemStatus.cancelled, target: false),
            item(8, BatchUpdateItemStatus.skipped, target: false),
          ];
        await mount(tester, service, brightness: brightness, scale: scale);
        expect(counters(tester).map((entry) => entry.label), [
          '全部',
          '可更新',
          '进行中',
          '失败',
          '新版已存在/重复',
          '已创建但停止/暂停',
        ]);
        expect(counters(tester).map((entry) => entry.value),
            ['8', '1', '0', '2', '1', '1']);
        final failed = find.text('失败: 2');
        await tester.ensureVisible(failed);
        await tester.pumpAndSettle();
        await tester.tap(failed);
        await tester.pumpAndSettle();
        expect(find.text('更新失败的漫画'), findsOneWidget);
        expect(find.byKey(const ValueKey('batch-update-failure-2')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('batch-update-failure-3')),
            findsOneWidget);
        expect(find.textContaining('失败原因: 无法获取归档大小或费用'), findsOneWidget);
        expect(find.textContaining('失败原因: 未记录具体失败原因'), findsOneWidget);
        expect(find.textContaining('GID: 2\n'), findsOneWidget);
        expect(
            find.byKey(const ValueKey('batch-update-failure-4')), findsNothing);
        expect(backend.reads, isEmpty);
        expect(backend.submissions, isEmpty);
        expect(backend.pipelines, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        service.dispose();
      });
    }
  }

  testWidgets(
      'failure details stay with their batch, empty reasons use fallback',
      (tester) async {
    final service = DownloadBatchUpdateService(FakeBatchBackend())
      ..phase = BatchUpdatePhase.finished
      ..items = [item(1, BatchUpdateItemStatus.failed, reason: ' ')];
    await mount(tester, service);
    await tester.ensureVisible(find.text('失败: 1'));
    await tester.tap(find.text('失败: 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('未记录具体失败原因'), findsOneWidget);
    service.items = [
      item(9, BatchUpdateItemStatus.failed, reason: 'batchUpdateInvalidVersion')
    ];
    service.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('batch-update-failure-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('batch-update-failure-9')), findsNothing);
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('失败: 1'));
    await tester.tap(find.text('失败: 1'));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('batch-update-failure-9')), findsOneWidget);
    expect(find.textContaining('失败原因: 版本链无效或出现循环'), findsOneWidget);
    service.items.single.status = BatchUpdateItemStatus.latest;
    service.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('暂无失败漫画'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'no failures disables drill-down; running counts only one active item',
      (tester) async {
    final backend = FakeBatchBackend();
    final service = DownloadBatchUpdateService(backend)
      ..phase = BatchUpdatePhase.review
      ..items = [
        item(1, BatchUpdateItemStatus.available),
        item(2, BatchUpdateItemStatus.available)
      ]
      ..total = 2;
    await mount(tester, service);
    expect(counters(tester)[2].value, '0');
    expect(counters(tester)[1].value, '2');
    service.items.first.selected = false;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[1].value, '2');
    expect(counters(tester)[3].onTap, isNull);
    await tester.ensureVisible(find.text('失败: 0'));
    await tester.tap(find.text('失败: 0'));
    await tester.pumpAndSettle();
    expect(find.text('更新失败的漫画'), findsNothing);
    service.phase = BatchUpdatePhase.checking;
    service.currentTitle = 'Old 1';
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[2].value, '1');
    backend.globallyPaused = true;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[2].value, '0');
    backend.globallyPaused = false;
    service.phase = BatchUpdatePhase.submitting;
    service.current = 1;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[2].value, '1');
    service.current = 2;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[2].value, '0');
    service.items.first.status = BatchUpdateItemStatus.submitted;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[1].value, '1');
    service.items.last.status = BatchUpdateItemStatus.failed;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[1].value, '0');
    expect(counters(tester)[3].value, '1');
    expect(counters(tester)[3].onTap, isNotNull);
    service.phase = BatchUpdatePhase.cancelled;
    service.notifyListeners();
    await tester.pump();
    expect(counters(tester)[2].value, '0');
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
