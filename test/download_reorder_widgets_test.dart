import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

  test('group drag collapse is temporary and exit restores expanded groups',
      () {
    final DownloadReorderExpansionSession session =
        DownloadReorderExpansionSession();
    final Set<String> expandedGroups = {'A', 'B'};

    session.start(expandedGroups);
    expandedGroups.add('temporarily-opened');
    session.collapseAll(expandedGroups);
    expect(expandedGroups, isEmpty);

    session.restore(expandedGroups);
    expect(expandedGroups, {'A', 'B'});
  });

  test('reordering a group-local list does not mutate other groups', () {
    const List<String> firstGroup = ['A', 'B', 'C'];
    const List<String> secondGroup = ['D', 'E'];

    final List<String> reordered = reorderDownloadList(firstGroup, 0, 2);

    expect(reordered, ['B', 'C', 'A']);
    expect(firstGroup, ['A', 'B', 'C']);
    expect(secondGroup, ['D', 'E']);
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

  testWidgets('whole item starts dragging after 2 seconds on Android',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
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
    await tester.pump(const Duration(milliseconds: 1999));
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

  for (final TargetPlatform platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets('whole item starts dragging immediately on $platform',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      bool dragStarted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: 2,
              onReorderItem: (_, __) {},
              onReorderStart: (_) => dragStarted = true,
              itemBuilder: (_, index) => DownloadReorderItem(
                key: ValueKey('desktop_item_$index'),
                index: index,
                child: const SizedBox(height: 100, width: 200),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('desktop_item_0'))),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump();
      expect(dragStarted, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
      'dragging an item outside its group keeps every other group fixed and cancels the drop',
      (tester) async {
    int reorderCount = 0;
    final List<String> firstGroup = ['A1', 'A2'];
    final List<String> secondGroup = ['B1', 'B2'];

    Widget buildGroup(String name, List<String> items) {
      return DownloadReorderGroupSection<String>(
        groupIndex: name == 'A' ? 0 : 1,
        groupName: name,
        isOpen: true,
        items: items,
        itemKey: (item) => ValueKey('drag_$item'),
        onToggle: () {},
        onReorderItems: (_, __) => reorderCount += 1,
        itemBuilder: (_, item) => SizedBox(
          key: ValueKey('card_$item'),
          height: 70,
          child: Text(item),
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                buildGroup('A', firstGroup),
                buildGroup('B', secondGroup),
              ],
            ),
          ),
        ),
      ),
    );

    final Offset originalB1 =
        tester.getCenter(find.byKey(const ValueKey('card_B1')));
    final Offset originalB2 =
        tester.getCenter(find.byKey(const ValueKey('card_B2')));
    final Offset originalA1 =
        tester.getCenter(find.byKey(const ValueKey('card_A1')));
    final Offset originalGroupA = tester.getCenter(find.text('A'));
    final Offset originalGroupB = tester.getCenter(find.text('B'));
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('card_A1'))),
    );
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveTo(originalB2);
    await tester.pump();

    expect(
      tester.getCenter(find.byKey(const ValueKey('card_A1'))).dy,
      greaterThan(originalGroupB.dy),
    );
    expect(tester.getCenter(find.byKey(const ValueKey('card_B1'))), originalB1);
    expect(tester.getCenter(find.byKey(const ValueKey('card_B2'))), originalB2);
    expect(tester.getCenter(find.text('A')), originalGroupA);
    expect(tester.getCenter(find.text('B')), originalGroupB);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(reorderCount, 0);
    expect(
      tester.getCenter(find.byKey(const ValueKey('card_A1'))),
      originalA1,
    );
    expect(firstGroup, ['A1', 'A2']);
    expect(secondGroup, ['B1', 'B2']);
  });

  testWidgets('dragging inside one group reorders only that group',
      (tester) async {
    int? reorderedFrom;
    int? reorderedTo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadReorderItemList<String>(
            items: const ['A', 'B', 'C'],
            itemKey: (item) => ValueKey('drag_$item'),
            onReorderItems: (from, to) {
              reorderedFrom = from;
              reorderedTo = to;
            },
            itemBuilder: (_, item) => SizedBox(
              key: ValueKey('card_$item'),
              height: 70,
              child: Text(item),
            ),
          ),
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('card_A'))),
    );
    await tester.pump(const Duration(seconds: 2));
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('card_C'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(reorderedFrom, 0);
    expect(reorderedTo, 1);
  });

  testWidgets('an item can reorder inside the outer group reorder list',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    int groupReorderCount = 0;
    int? itemReorderedFrom;
    int? itemReorderedTo;
    const List<String> groups = ['A', 'B'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: groups.length,
            onReorderItem: (_, __) => groupReorderCount += 1,
            itemBuilder: (_, groupIndex) {
              final String group = groups[groupIndex];
              return DownloadReorderGroupSection<String>(
                key: ValueKey('group_$group'),
                groupIndex: groupIndex,
                groupName: group,
                isOpen: true,
                items: ['$group-1', '$group-2', '$group-3'],
                itemKey: (item) => ValueKey('drag_$item'),
                onToggle: () {},
                onReorderItems: (from, to) {
                  itemReorderedFrom = from;
                  itemReorderedTo = to;
                },
                itemBuilder: (_, item) => AbsorbPointer(
                  child: SizedBox(
                    key: ValueKey('card_$item'),
                    height: 70,
                    child: Text(item),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('card_A-1'))),
    );
    await tester.pump();
    await gesture.moveTo(
      tester.getCenter(find.byKey(const ValueKey('card_A-3'))),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(groupReorderCount, 0);
    expect(itemReorderedFrom, 0);
    expect(itemReorderedTo, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('group drag collapses all groups and exit restores the snapshot',
      (tester) async {
    final DownloadReorderExpansionSession session =
        DownloadReorderExpansionSession();
    final Set<String> expandedGroups = {'A', 'B'};
    session.start(expandedGroups);
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, updateState) {
            setState = updateState;
            final List<String> groups = ['A', 'B'];
            return Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: groups.length,
                      onReorderStart: (_) => setState(
                        () => session.collapseAll(expandedGroups),
                      ),
                      onReorderItem: (_, __) {},
                      itemBuilder: (_, index) {
                        final String group = groups[index];
                        return DownloadReorderGroupSection<String>(
                          key: ValueKey('group_$group'),
                          groupIndex: index,
                          groupName: group,
                          isOpen: expandedGroups.contains(group),
                          items: ['$group-item'],
                          itemKey: ValueKey<String>.new,
                          onToggle: () {},
                          onReorderItems: (_, __) {},
                          itemBuilder: (_, item) =>
                              SizedBox(height: 60, child: Text(item)),
                        );
                      },
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('exit_reorder'),
                    onPressed: () => setState(
                      () => session.restore(expandedGroups),
                    ),
                    child: const Text('Exit'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 80),
    );
    await tester.pumpAndSettle();
    expect(expandedGroups, isEmpty);

    await tester.tap(find.byKey(const ValueKey('exit_reorder')));
    await tester.pump();
    expect(expandedGroups, {'A', 'B'});
  });

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

  testWidgets('Android group displays one immediate drag handle',
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

  testWidgets('Chinese reorder hint omits the long-press duration',
      (tester) async {
    addTearDown(Get.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: LocaleText(),
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(body: DownloadReorderHint()),
      ),
    );

    expect(
      find.text('拖动分组右侧手柄调整分组顺序，长按漫画以调整漫画顺序'),
      findsOneWidget,
    );
  });

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
