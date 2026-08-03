import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/pages/download/list/widget/download_reorder_widgets.dart';
import 'package:jhentai/src/pages/download/widget/download_page_more_menu.dart';

void main() {
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

  testWidgets('sorting starts from the more menu and switches to save',
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
                  DownloadPageMoreMenu(
                    inEditMode: inEditMode,
                    switchViewIcon: Icons.grid_view,
                    switchViewLabel: '切换到网格模式',
                    onSwitchView: () {},
                    onToggleSorting: () => setState(
                      () => inEditMode = !inEditMode,
                    ),
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

    expect(find.byIcon(Icons.sort), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('调整下载顺序'), findsOneWidget);

    await tester.tap(find.text('调整下载顺序'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.save), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });
}
