import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/database/database.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/model/jh_layout.dart';
import 'package:jhentai/src/pages/download/download_base_page.dart';
import 'package:jhentai/src/pages/download/download_page_controller_scope.dart';
import 'package:jhentai/src/pages/download/grid/archive/archive_grid_download_page.dart';
import 'package:jhentai/src/pages/download/grid/mixin/grid_download_page_mixin.dart';
import 'package:jhentai/src/pages/download/list/archive/archive_list_download_page.dart';
import 'package:jhentai/src/pages/download/list/archive/archive_list_download_page_logic.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/service/local_config_service.dart';
import 'package:jhentai/src/service/super_resolution_service.dart';
import 'package:jhentai/src/setting/preference_setting.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/utils/speed_computer.dart';

class _Config extends LocalConfigService {
  _Config(this.bodyType);
  final int bodyType;

  @override
  Future<String?> read(
          {required ConfigEnum configKey, String subConfigKey = ''}) async =>
      configKey == ConfigEnum.downloadPageBodyType ? '$bodyType' : '["first"]';

  @override
  Future<int> write(
          {required ConfigEnum configKey,
          String subConfigKey = '',
          required String value}) async =>
      1;
}

class _Archives extends ArchiveDownloadService {
  @override
  void onClose() {} // No live download workers are started in these tests.
}

class _Controller extends GetxController {
  int starts = 0;
  int closes = 0;
  @override
  void onInit() {
    super.onInit();
    starts++;
  }

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

class _PendingConfig extends LocalConfigService {
  final Completer<String?> groups = Completer<String?>();
  @override
  Future<String?> read(
          {required ConfigEnum configKey, String subConfigKey = ''}) =>
      groups.future;
}

Future<void> pumpFrames(WidgetTester tester) async {
  // Download progress and image placeholders animate continuously.
  for (int frame = 0; frame < 25; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('legacy shared scroll position is ambiguous across two views',
      (tester) async {
    final shared = ScrollController();
    await tester.pumpWidget(MaterialApp(
        home: Row(children: [
      Expanded(
          child: ListView(
              controller: shared, children: const [SizedBox(height: 2000)])),
      Expanded(
          child: ListView(
              controller: shared, children: const [SizedBox(height: 2000)])),
    ])));
    expect(shared.positions.length, 2);
    expect(() => shared.position, throwsAssertionError);
    await tester.pumpWidget(const SizedBox());
    shared.dispose();
  });

  testWidgets('closing during group initialization does not recreate workers',
      (tester) async {
    final previous = localConfigService;
    final config = _PendingConfig();
    localConfigService = config;
    addTearDown(() => localConfigService = previous);
    final scope = DownloadPageControllerScope();
    final controller = scope.obtain(ArchiveListDownloadPageLogic.new);
    scope.dispose();
    config.groups.complete('["first"]');
    await tester.pump();
    expect(controller.isClosed, isTrue);
    expect(controller.maxGalleryNum4AnimationListener, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one controller per type per page; close owns only that page',
      (tester) async {
    final first = DownloadPageControllerScope();
    final second = DownloadPageControllerScope();
    int disposed = 0;
    _Controller obtain(DownloadPageControllerScope scope) =>
        scope.obtain(_Controller.new, disposeResources: (_) => disposed++);
    final a = obtain(first);
    expect(obtain(first), same(a));
    final b = obtain(second);
    expect(b, isNot(same(a)));
    expect(a.starts, 1);
    first.dispose();
    first.dispose();
    expect(a.closes, 1);
    expect(b.closes, 0);
    expect(disposed, 1);
    second.dispose();
    expect(disposed, 2);
    expect(() => obtain(first), throwsStateError);
    await tester.pump();
  });

  for (final bodyType in [0, 1]) {
    testWidgets(
        'archive view $bodyType locates only the pushed DownloadPage and survives reopening',
        (tester) async {
      Get.testMode = true;
      final previousConfig = localConfigService;
      final previousArchives = archiveDownloadService;
      final previousLayout = styleSetting.layout.value;
      final previousTab = preferenceSetting.defaultDownloadTab.value;
      localConfigService = _Config(bodyType);
      styleSetting.layout.value = LayoutMode.mobileV2;
      preferenceSetting.defaultDownloadTab.value =
          DownloadPageGalleryType.archive;
      final archives = _Archives();
      archiveDownloadService = archives;
      archives.allGroups.addAll(['first', 'target']);
      for (int gid = 1; gid <= 40; gid++) {
        final group = gid <= 10 ? 'first' : 'target';
        archives.archives.add(ArchiveDownloadedData(
            gid: gid,
            token: 'test',
            title: 'Archive $gid',
            category: 'Manga',
            pageCount: 10,
            galleryUrl: 'https://example.invalid/g/$gid/test/',
            coverUrl: 'https://example.invalid/cover.jpg',
            size: 100,
            publishTime: '2026-10-27 00:00:00',
            archiveStatusCode: ArchiveStatus.paused.code,
            archivePageUrl: 'https://example.invalid/archive/$gid',
            isOriginal: true,
            insertTime: '2026-10-27 00:00:00',
            sortOrder: gid,
            groupName: group,
            tags: '{}',
            parseSource: 1));
        archives.archiveDownloadInfos[gid] = ArchiveDownloadInfo(
            size: 100,
            parseSource: 1,
            archiveStatus:
                gid == 40 ? ArchiveStatus.downloading : ArchiveStatus.paused,
            cancelToken: CancelToken(),
            speedComputer: SpeedComputer(),
            sortOrder: gid,
            group: group);
      }
      Get.put<ArchiveDownloadService>(archives, permanent: true);
      Get.put<SuperResolutionService>(superResolutionService, permanent: true);
      final navigator = GlobalKey<NavigatorState>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        for (final info in archives.archiveDownloadInfos.values) {
          info.speedComputer.dispose();
        }
        localConfigService = previousConfig;
        archiveDownloadService = previousArchives;
        styleSetting.layout.value = previousLayout;
        preferenceSetting.defaultDownloadTab.value = previousTab;
        Get.reset();
      });

      await tester.pumpWidget(
          GetMaterialApp(navigatorKey: navigator, home: const DownloadPage()));
      await pumpFrames(tester);
      final main = bodyType == 0
          ? tester
              .widget<ArchiveListDownloadPage>(
                  find.byType(ArchiveListDownloadPage))
              .logic
          : tester
              .widget<ArchiveGridDownloadPage>(
                  find.byType(ArchiveGridDownloadPage))
              .logic;
      final mainScroll = bodyType == 0
          ? (main as dynamic).state.scrollController as ScrollController
          : (main as dynamic).state.rootScrollController as ScrollController;
      for (int attempt = 0; attempt < 2; attempt++) {
        navigator.currentState!.push(
            MaterialPageRoute<void>(builder: (_) => const DownloadPage()));
        await pumpFrames(tester);
        final dynamic current = bodyType == 0
            ? tester
                .widget<ArchiveListDownloadPage>(
                    find.byType(ArchiveListDownloadPage))
                .logic
            : tester
                .widget<ArchiveGridDownloadPage>(
                    find.byType(ArchiveGridDownloadPage))
                .logic;
        expect(current, isNot(same(main)));
        expect(mainScroll.positions.length, 1);
        final mainOffset = mainScroll.offset;
        await tester
            .tap(find.byKey(const ValueKey('locateRunningArchiveDownload')));
        await pumpFrames(tester);
        expect(current.state.navigationItemKeys, isEmpty);
        if (bodyType == 0) {
          expect(current.state.displayGroups, contains('target'));
          expect(current.state.scrollController.offset, greaterThan(0));
        } else {
          expect(current.state.currentGroup, 'target');
          expect(current.state.galleryScrollController.offset, greaterThan(0));
        }
        expect(mainScroll.offset, mainOffset);
        expect(
            bodyType == 0
                ? find.text('Archive 40')
                : find
                    .byWidgetPredicate((widget) =>
                        widget is GridGallery && widget.title == 'Archive 40')
                    .hitTestable(),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        navigator.currentState!.pop();
        await pumpFrames(tester);
        expect(current.isClosed, isTrue);
        expect((main as dynamic).isClosed, isFalse);
      }
    });
  }
}
