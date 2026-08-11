import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/pages/download/download_reorder_mode.dart';
import 'package:jhentai/src/pages/download/list/widget/download_reorder_widgets.dart';
import 'package:jhentai/src/pages/download/widget/download_page_more_menu.dart';

void main() {
  test('leaving the download view exits every active reorder mode once', () {
    final first = _FakeReorderMode();
    final second = _FakeReorderMode();
    registerDownloadReorderMode(first);
    registerDownloadReorderMode(second);

    exitAllDownloadReorderModes();
    exitAllDownloadReorderModes();

    expect(first.exitCount, 1);
    expect(second.exitCount, 1);
  });

  test('reorder entries retain expanded groups and hide collapsed items', () {
    final entries = buildDownloadReorderEntries<String>(
      groups: const ['open', 'closed'],
      isGroupOpen: (group) => group == 'open',
      itemsForGroup: (group) => ['$group-1', '$group-2'],
    );

    expect(
      entries.map((entry) => entry.item ?? 'group:${entry.groupName}'),
      ['group:open', 'open-1', 'open-2', 'group:closed'],
    );
  });

  test('reorder entries use the adjusted destination index', () {
    const entries = [
      DownloadReorderEntry<String>.group('group'),
      DownloadReorderEntry<String>.item('group', 'A'),
      DownloadReorderEntry<String>.item('group', 'B'),
      DownloadReorderEntry<String>.item('group', 'C'),
    ];

    final reordered = reorderDownloadEntries(entries, 1, 3);
    expect(reordered.map((entry) => entry.item), [null, 'B', 'C', 'A']);
  });

  test('manual order uses sortOrder and falls back for equal values', () {
    expect(
      compareDownloadManualOrder(
        firstOrder: 2,
        secondOrder: 5,
        fallbackComparison: 99,
      ),
      lessThan(0),
    );
    expect(
      compareDownloadManualOrder(
        firstOrder: 0,
        secondOrder: 0,
        fallbackComparison: 7,
      ),
      7,
    );
  });

  for (final TargetPlatform platform in [
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    testWidgets('whole item starts dragging after 200ms on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      bool dragStarted = false;
      int? reorderedFrom;
      int? reorderedTo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: 2,
              onReorderItem: (from, to) {
                reorderedFrom = from;
                reorderedTo = to;
              },
              onReorderStart: (_) => dragStarted = true,
              itemBuilder: (_, index) => DownloadReorderItem(
                key: ValueKey('item_$index'),
                index: index,
                child: const SizedBox(height: 100, width: 200),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester
          .startGesture(tester.getCenter(find.byKey(const ValueKey('item_0'))));
      await tester.pump(const Duration(milliseconds: 199));
      expect(dragStarted, isFalse);
      await tester.pump(const Duration(milliseconds: 2));
      expect(dragStarted, isTrue);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reorderedFrom, 0);
      expect(reorderedTo, 1);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('switching to reorder mode restores the visible scroll offset',
      (tester) async {
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);
    bool reorderMode = false;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, updateState) {
            setState = updateState;
            if (reorderMode) {
              return ReorderableListView.builder(
                scrollController: controller,
                buildDefaultDragHandles: false,
                itemCount: 30,
                onReorderItem: (_, __) {},
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey('reorder_$index'),
                  height: 100,
                ),
              );
            }
            return ListView.builder(
              controller: controller,
              itemCount: 30,
              itemBuilder: (_, index) => SizedBox(
                key: ValueKey('normal_$index'),
                height: 100,
              ),
            );
          },
        ),
      ),
    );

    controller.jumpTo(1200);
    final double oldOffset = controller.offset;
    setState(() => reorderMode = true);
    restoreDownloadListScrollOffset(controller, oldOffset);
    await tester.pump();

    expect(controller.offset, oldOffset);
  });

  testWidgets('macOS group displays one immediate drag handle', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DownloadReorderGroupTile(
            index: 0,
            groupName: 'group',
            itemCount: 1,
            isOpen: true,
            onTap: _noop,
          ),
        ),
      ),
    );

    expect(find.byType(ReorderableDragStartListener), findsOneWidget);
    expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android group displays one custom delayed drag handle',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DownloadReorderGroupTile(
            index: 0,
            groupName: 'group',
            itemCount: 1,
            isOpen: true,
            onTap: _noop,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
          (widget) => widget is ReorderableDragStartListener),
      findsOneWidget,
    );
    expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  for ((Locale locale, String countText, String backText) testCase in [
    (const Locale('zh', 'CN'), '128 个条目', '返回分组列表'),
    (const Locale('en', 'US'), '128 items', 'Back to groups'),
  ]) {
    testWidgets('reorder groups fit a narrow screen in ${testCase.$1}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(Get.reset);

      await tester.pumpWidget(
        GetMaterialApp(
          translations: LocaleText(),
          locale: testCase.$1,
          home: Scaffold(
            body: Column(
              children: [
                const DownloadReorderHint(),
                Expanded(
                  child: ReorderableListView(
                    onReorderItem: (_, __) {},
                    children: [
                      DownloadReorderGroupTile(
                        key: const ValueKey('long_group'),
                        index: 0,
                        groupName:
                            'A very long downloaded gallery group name 用于测试很长的分组名称',
                        itemCount: 128,
                        isOpen: true,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                DownloadReorderBackTile(onTap: () {}),
              ],
            ),
          ),
        ),
      );

      expect(find.text(testCase.$2), findsOneWidget);
      expect(find.text(testCase.$3), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reorder mode has a dedicated button beside the more menu',
      (tester) async {
    bool inEditMode = false;
    late StateSetter setState;
    addTearDown(Get.reset);

    await tester.pumpWidget(
      GetMaterialApp(
        translations: LocaleText(),
        locale: const Locale('zh', 'CN'),
        home: StatefulBuilder(
          builder: (context, updateState) {
            setState = updateState;
            return Scaffold(
              appBar: AppBar(
                actions: [
                  DownloadReorderModeButton(
                    inReorderMode: inEditMode,
                    onPressed: () => setState(
                      () => inEditMode = !inEditMode,
                    ),
                  ),
                  DownloadPageMoreMenu(
                    switchViewIcon: Icons.grid_view,
                    switchViewLabel: '切换到网格模式',
                    onSwitchView: () {},
                    onMultiSelect: () {},
                    onResumeAll: () {},
                    onPauseAll: () {},
                    onSearch: () {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.sort), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.byTooltip('进入调序模式'), findsOneWidget);
    final Finder reorderButton = find.ancestor(
      of: find.byIcon(Icons.sort),
      matching: find.byType(IconButton),
    );
    final Finder moreButton = find.ancestor(
      of: find.byIcon(Icons.more_vert),
      matching: find.byType(IconButton),
    );
    expect(
      tester.getSize(reorderButton.first),
      tester.getSize(moreButton.first),
    );

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byTooltip('退出调序模式'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sort), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('local page shows refresh before a direct view switch button',
      (tester) async {
    bool refreshed = false;
    bool switched = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              LocalDownloadPageActions(
                switchViewIcon: Icons.grid_view,
                switchViewLabel: 'Switch view',
                onRefresh: () => refreshed = true,
                onSwitchView: () => switched = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.refresh)).dx,
      lessThan(tester.getCenter(find.byIcon(Icons.grid_view)).dx),
    );
    expect(
      tester.getSize(find
          .ancestor(
            of: find.byIcon(Icons.refresh),
            matching: find.byType(IconButton),
          )
          .first),
      tester.getSize(find
          .ancestor(
            of: find.byIcon(Icons.grid_view),
            matching: find.byType(IconButton),
          )
          .first),
    );
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.tap(find.byIcon(Icons.grid_view));
    expect(refreshed, isTrue);
    expect(switched, isTrue);
  });
}

void _noop() {}

class _FakeReorderMode implements DownloadReorderModeParticipant {
  int exitCount = 0;

  @override
  void exitEditMode() {
    exitCount += 1;
  }
}
