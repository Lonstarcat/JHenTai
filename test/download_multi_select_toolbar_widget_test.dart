import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_multi_select_toolbar.dart';
import 'package:jhentai/src/pages/setting/style/download_multi_select_toolbar_setting_page.dart';
import 'package:jhentai/src/setting/style_setting.dart';
import 'package:jhentai/src/widget/download_multi_select_toolbar.dart';

Widget host(Widget widget, {Brightness brightness = Brightness.light}) =>
    GetMaterialApp(
      translations: LocaleText(),
      locale: const Locale('en', 'US'),
      theme: ThemeData(brightness: brightness),
      home: widget,
    );

Finder button(String id) => find.byKey(ValueKey('toolbar-$id'));

void main() {
  testWidgets('select-all refresh enables selection-dependent actions',
      (tester) async {
    bool selected = false;
    await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: BottomAppBar(
      child: StatefulBuilder(
          builder: (context, setState) => DownloadMultiSelectToolbar(
                config:
                    DownloadToolbarConfig.defaults(DownloadToolbarKind.gallery),
                hasSelection: selected,
                callbacks: {
                  for (final action in DownloadToolbarAction.values)
                    action: () => setState(() => selected = true),
                },
              )),
    ))));
    expect(tester.widget<IconButton>(button('favorite')).onPressed, isNull);
    await tester.tap(button('selectAll'));
    await tester.pump();
    expect(tester.widget<IconButton>(button('favorite')).onPressed, isNotNull);
  });

  testWidgets(
      'empty selection disables actions, select-all and close still work',
      (tester) async {
    final called = <DownloadToolbarAction>[];
    int closed = 0;
    await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: BottomAppBar(
      child: DownloadMultiSelectToolbar(
        config: DownloadToolbarConfig.defaults(DownloadToolbarKind.archive),
        hasSelection: false,
        callbacks: {
          for (final action in DownloadToolbarAction.values)
            action: () => called.add(action)
        },
        onClose: () => closed++,
      ),
    ))));
    for (final action in DownloadToolbarAction.values) {
      expect(tester.widget<IconButton>(button(action.name)).onPressed != null,
          action == DownloadToolbarAction.selectAll);
    }
    await tester.tap(button('selectAll'));
    await tester.tap(button('close'));
    expect(called, [DownloadToolbarAction.selectAll]);
    expect(closed, 1);
  });

  testWidgets('custom order, hidden actions, horizontal scroll and fixed close',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(260, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final config = DownloadToolbarConfig.defaults(DownloadToolbarKind.archive)
        .reorder(7, 0)
        .toggle(DownloadToolbarAction.pause, false);
    final called = <DownloadToolbarAction>[];
    await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: BottomAppBar(
      child: DownloadMultiSelectToolbar(
          config: config,
          callbacks: {
            for (final action in DownloadToolbarAction.values)
              action: () => called.add(action)
          },
          onClose: () {}),
    ))));
    expect(button('pause'), findsNothing);
    expect(tester.getTopLeft(button('changeParseSource')).dx,
        lessThan(tester.getTopLeft(button('selectAll')).dx));
    final close = tester.getRect(button('close'));
    await tester.tap(button('changeParseSource'));
    expect(called, [DownloadToolbarAction.changeParseSource]);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(button('close')), close);
    expect(
        find.ancestor(
            of: button('close'), matching: find.byType(SingleChildScrollView)),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preview never runs supplied business callbacks, but remains scrollable',
      (tester) async {
    int calls = 0;
    await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: BottomAppBar(
      child: DownloadMultiSelectToolbar(
          config: DownloadToolbarConfig.defaults(DownloadToolbarKind.gallery),
          preview: true,
          callbacks: {
            for (final action in DownloadToolbarAction.values)
              action: () => calls++
          },
          onClose: () => calls++),
    ))));
    for (final id in ['selectAll', 'favorite', 'delete', 'close']) {
      await tester.tap(button(id));
    }
    expect(calls, 0);
    expect(button('changeParseSource'), findsNothing);
  });

  testWidgets(
      'settings tabs, live switches, reset only active profile, fixed preview and dark theme',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await tester.binding.setSurfaceSize(const Size(390, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(
        DownloadMultiSelectToolbarSettingPage(settings: settings),
        brightness: Brightness.dark));
    final initialPreview =
        tester.getRect(find.byKey(const ValueKey('preview-gallery')));
    await tester.tap(find.byKey(const ValueKey('toggle-favorite')));
    await tester.pumpAndSettle();
    expect(button('favorite'), findsNothing);
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(button('favorite'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('toggle-selectAll')));
    await tester.pumpAndSettle();
    expect(button('selectAll'), findsNothing);
    await tester.tap(find.byTooltip('Reset this tab'));
    await tester.pumpAndSettle();
    expect(button('selectAll'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(button('favorite'), findsNothing);
    await tester.drag(find.byType(ReorderableListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('preview-gallery'))),
        initialPreview);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'editor drag updates the live preview and persists normalized order',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await tester.pumpWidget(
        host(DownloadMultiSelectToolbarSettingPage(settings: settings)));
    final handle = find.descendant(
      of: find.byKey(const ValueKey('pause')),
      matching: find.byType(ReorderableDragStartListener),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -112));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
        settings.galleryToolbar.value.order.first, DownloadToolbarAction.pause);
    expect(tester.getTopLeft(button('pause')).dx,
        lessThan(tester.getTopLeft(button('selectAll')).dx));
    expect(settings.archiveToolbar.value.order.first,
        DownloadToolbarAction.selectAll);
  });

  testWidgets('reactive toolbar updates with style configuration',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    await tester.pumpWidget(host(Scaffold(
        bottomNavigationBar: BottomAppBar(
            child: Obx(() => DownloadMultiSelectToolbar(
                  config: settings.galleryToolbar.value,
                  onClose: () {},
                ))))));
    expect(button('delete'), findsOneWidget);
    await settings.updateToolbar(DownloadToolbarKind.gallery,
        (config) => config.toggle(DownloadToolbarAction.delete, false));
    await tester.pump();
    expect(button('delete'), findsNothing);
  });
}
