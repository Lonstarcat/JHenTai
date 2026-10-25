import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_batch_update.dart';
import 'package:jhentai/src/utils/batch_update_display.dart';
import 'package:jhentai/src/widget/batch_update_statistics.dart';
import 'package:jhentai/src/service/download_batch_update_service.dart';
import 'package:jhentai/src/widget/download_batch_update_dialog.dart';
import 'batch_update_fakes.dart';

String statisticValue(WidgetTester tester, String label) => tester
    .widget<BatchUpdateStatistics>(find.byType(BatchUpdateStatistics).first)
    .items
    .singleWhere((item) => item.label == label)
    .value;

void main() {
  test('display GP is separate from Bot GP and never converts Credits', () {
    expect(parseOfficialGp('1,234 GP or 567 Credits'), 1234);
    expect(parseOfficialGp('Free'), 0);
    expect(parseOfficialGp('150 Credits'), isNull);
    expect(parseOfficialGp('unknown'), isNull);
    expect(parseOfficialGp('1.5 GP'), isNull);
    final official = BatchUpdateItem(BatchUpdateSource(
      kind: testSource(1, archive: true).kind,
      gid: 1,
      title: 'Official',
      galleryUrl: testUrl(1).url,
      group: 'test',
      original: true,
    ))
      ..target = testDetail(11)
      ..status = BatchUpdateItemStatus.available
      ..selected = true
      ..quote = const ArchiveUpdateQuote(
          sizeBytes: 1024, cost: '1,234 GP or 567 Credits');
    final bot = BatchUpdateItem(testSource(2, archive: true))
      ..target = testDetail(12)
      ..status = BatchUpdateItemStatus.submitted
      ..selected = true
      ..quote =
          const ArchiveUpdateQuote(sizeBytes: 2048, cost: '20 GP', botGp: 20);
    var stats = BatchUpdateDisplayStats.fromItems([official, bot]);
    expect(stats.gp, 1234);
    expect(stats.botGp, 20);
    expect(stats.updateCount, 2);
    expect(stats.sizeBytes, 3072);
    official.quote =
        const ArchiveUpdateQuote(sizeBytes: 1024, cost: '567 Credits');
    stats = BatchUpdateDisplayStats.fromItems([official, bot]);
    expect(stats.unknownGp, isTrue);
    expect(stats.gp, 0);
    bot.selected = false;
    expect(BatchUpdateDisplayStats.fromItems([official, bot]).botGp, 0);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'filtered results, exact Chinese text and footer layout ($brightness)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = FakeBatchBackend()
        ..excluded.add(3)
        ..existing.add(15)
        ..quoteFailures.add(6)
        ..details.addAll({
          1: testDetail(1, next: 11),
          11: testDetail(11),
          2: testDetail(2),
          5: testDetail(5, next: 15),
          15: testDetail(15),
          6: testDetail(6, next: 16),
          16: testDetail(16)
        });
      final service = DownloadBatchUpdateService(backend);
      await service.check([1, 2, 3, 4, 5, 6]
          .map((gid) => testSource(gid, archive: true))
          .toList());
      await tester.pumpWidget(GetMaterialApp(
          locale: const Locale('zh', 'CN'),
          translations: LocaleText(),
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
              body: DownloadBatchUpdateDialog(
                  service: service, onSubmit: () {}))));
      expect(find.byKey(const ValueKey('batch-update-1')), findsOneWidget);
      for (final gid in [2, 3, 4, 5]) {
        expect(find.byKey(ValueKey('batch-update-$gid')), findsNothing);
      }
      expect(service.items.length, 6);
      expect(find.text('新版归档需完整下载，可能消耗GP/Bot GP/Credits。'), findsOneWidget);
      expect(find.text('确认更新'), findsOneWidget);
      expect(find.textContaining('确认费用并更新'), findsNothing);
      expect(statisticValue(tester, '可更新漫画'), '1');
      expect(find.text('可更新漫画数量'), findsNothing);
      final list = find.byKey(const ValueKey('batch-update-list'));
      final footer = find.byKey(const ValueKey('batch-update-statistics'));
      expect(tester.getBottomLeft(list).dy,
          lessThan(tester.getTopLeft(footer).dy));
      expect(tester.getBottomLeft(footer).dy,
          lessThan(tester.getTopLeft(find.byType(FilledButton)).dy));
      await tester.tap(find.byKey(const ValueKey('batch-update-1')));
      await tester.pump();
      expect(statisticValue(tester, '可更新漫画'), '0');
      expect(statisticValue(tester, 'Bot GP'), '0');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });
  }
  testWidgets(
      'dark narrow-screen archive checklist displays quotes and requires explicit confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1, next: 11), 11: testDetail(11)});
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1, archive: true)]);
    int confirmed = 0;
    await tester.pumpWidget(GetMaterialApp(
        locale: const Locale('en', 'US'),
        translations: LocaleText(),
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
            body: DownloadBatchUpdateDialog(
                service: service, onSubmit: () => confirmed++))));
    expect(find.textContaining('20 GP'), findsOneWidget);
    expect(find.textContaining('may cost GP/Bot GP/Credits'), findsOneWidget);
    expect(backend.submissions, isEmpty);
    await tester.tap(find.byType(FilledButton));
    expect(confirmed, 1);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets(
      'finished submission removes progress and labels task-created, not download-complete',
      (tester) async {
    final backend = FakeBatchBackend()
      ..details.addAll({1: testDetail(1, next: 11), 11: testDetail(11)});
    final service = DownloadBatchUpdateService(backend);
    await service.check([testSource(1)]);
    await service.submit();
    await tester.pumpWidget(GetMaterialApp(
        locale: const Locale('en', 'US'),
        translations: LocaleText(),
        home: Scaffold(
            body:
                DownloadBatchUpdateDialog(service: service, onSubmit: () {}))));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Task created'), findsWidgets);
    expect(find.textContaining('Download completed'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
