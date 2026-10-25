import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/model/download_page_actions.dart';
import 'package:jhentai/src/pages/download/widget/download_page_more_menu.dart';
import 'package:jhentai/src/pages/setting/style/download_page_actions_setting_page.dart';
import 'package:jhentai/src/setting/style_setting.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'every external action dispatches only its callback; retained task updates live',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    final retained = ValueNotifier(false);
    addTearDown(retained.dispose);
    final calls = <DownloadPageAction>[];
    for (final action in DownloadPageAction.values) {
      settings.downloadPageActions.value =
          DownloadPageActionsConfig.defaults().withExternal(action);
      await tester.pumpWidget(GetMaterialApp(
          locale: const Locale('en', 'US'),
          translations: LocaleText(),
          home: Scaffold(
              body: DownloadPageMoreMenu(
            settings: settings,
            switchViewIcon: Icons.view_list,
            switchViewLabel: 'List',
            onToggleReorder: () => calls.add(DownloadPageAction.reorder),
            onSearch: () => calls.add(DownloadPageAction.search),
            onSwitchView: () => calls.add(DownloadPageAction.switchView),
            onMultiSelect: () => calls.add(DownloadPageAction.multiSelect),
            onResumeAll: () => calls.add(DownloadPageAction.resumeAll),
            onPauseAll: () => calls.add(DownloadPageAction.pauseAll),
            onBatchUpdateTask: () =>
                calls.add(DownloadPageAction.batchUpdateTask),
            hasBatchUpdateTask: () => retained.value,
            batchUpdateTaskChanges: retained,
          ))));
      final external =
          find.byKey(const ValueKey('download-page-external-action'));
      if (action == DownloadPageAction.batchUpdateTask) {
        expect(tester.widget<IconButton>(external).onPressed, isNull);
        retained.value = true;
        await tester.pump();
        expect(tester.widget<IconButton>(external).onPressed, isNotNull);
      }
      calls.clear();
      await tester.tap(external);
      await tester.pump();
      expect(calls, [action]);
    }
  });

  test(
      'defaults search outside, every menu switch enabled; old configs migrate',
      () {
    final config = DownloadPageActionsConfig.defaults();
    expect(config.externalAction, DownloadPageAction.search);
    expect(config.enabled.length, DownloadPageAction.values.length);
    expect(config.menuActions, [
      DownloadPageAction.batchUpdateTask,
      DownloadPageAction.switchView,
      DownloadPageAction.multiSelect,
      DownloadPageAction.resumeAll,
      DownloadPageAction.pauseAll,
      DownloadPageAction.reorder
    ]);
    final settings = StyleSetting();
    final old = jsonDecode(settings.toConfigString()) as Map;
    old.remove('downloadPageActions');
    settings.applyBeanConfig(jsonEncode(old));
    expect(settings.downloadPageActions.value.toJson(), config.toJson());
    for (final invalid in [null, 1, [], 'bad']) {
      expect(DownloadPageActionsConfig.fromJson(invalid).toJson(),
          config.toJson());
    }
    final malformed = DownloadPageActionsConfig.fromJson({
      'order': ['pauseAll', 'pauseAll', 'unknown'],
      'enabled': [],
      'externalAction': 'unknown',
    });
    expect(malformed.order.length, 7);
    expect(malformed.order.first, DownloadPageAction.pauseAll);
    expect(malformed.enabled.contains(DownloadPageAction.pauseAll), isFalse);
    expect(malformed.externalAction, DownloadPageAction.search);
  });

  test('switch external, toggle, reorder and all-off survive round trip', () {
    var config = DownloadPageActionsConfig.defaults()
        .reorder(5, 0)
        .withExternal(DownloadPageAction.reorder);
    expect(config.menuActions, contains(DownloadPageAction.search));
    expect(config.menuActions, isNot(contains(DownloadPageAction.reorder)));
    for (final action in DownloadPageAction.values) {
      config = config.toggle(action, false);
    }
    final restored = DownloadPageActionsConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())));
    expect(restored.menuActions, isEmpty);
    expect(restored.showExternal, isFalse);
    expect(restored.order.first, DownloadPageAction.reorder);
    expect(restored.withExternal(null).externalAction, isNull);
    expect(
        DownloadPageActionsConfig.fromJson(restored.withExternal(null).toJson())
            .externalAction,
        isNull);
  });

  test(
      'serialized menu saves roll back before next edit and retain unrelated style',
      () async {
    final gate = Completer<void>();
    final seen = <Map>[];
    final settings = StyleSetting(configWriter: (text) async {
      seen.add(jsonDecode(text) as Map);
      if (seen.length == 1) {
        await gate.future;
        return 0;
      }
      return 1;
    });
    final first = settings.updateDownloadPageActions(
        (c) => c.toggle(DownloadPageAction.search, false));
    final failure = expectLater(first, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    final second = settings.updateDownloadPageActions(
        (c) => c.withExternal(DownloadPageAction.reorder));
    final general = settings.saveBeanConfig();
    gate.complete();
    await failure;
    await second;
    await general;
    expect(settings.downloadPageActions.value.enabled,
        contains(DownloadPageAction.search));
    expect(settings.downloadPageActions.value.externalAction,
        DownloadPageAction.reorder);
    expect(settings.savingDownloadPageActions.value, isFalse);
    final reloaded = StyleSetting()..applyBeanConfig(settings.toConfigString());
    expect(reloaded.downloadPageActions.value.toJson(),
        settings.downloadPageActions.value.toJson());
    expect(reloaded.galleryToolbar.value.toJson(),
        settings.galleryToolbar.value.toJson());
  });

  test('four production views bind reorder state and existing callbacks once',
      () {
    for (final layout in ['grid', 'list']) {
      for (final kind in ['gallery', 'archive']) {
        final source = File(
                'lib/src/pages/download/$layout/$kind/${kind}_${layout}_download_page.dart')
            .readAsStringSync();
        expect(source, contains('inReorderMode: state.inEditMode'));
        expect(source, contains('onToggleReorder: logic.toggleEditMode'));
        expect('DownloadPageMoreMenu('.allMatches(source).length, 1);
        expect(source, isNot(contains('DownloadReorderModeButton(')));
      }
    }
  });

  testWidgets(
      'search outside, reorder in menu; forced exit survives all-off and restores search',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    bool editing = false;
    int searched = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('zh', 'CN'),
      translations: LocaleText(),
      home: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return Scaffold(
            appBar: AppBar(actions: [
          DownloadPageMoreMenu(
            settings: settings,
            switchViewIcon: Icons.view_list,
            switchViewLabel: 'List',
            inReorderMode: editing,
            onToggleReorder: () => setState(() => editing = !editing),
            onSwitchView: () {},
            onMultiSelect: () {},
            onResumeAll: () {},
            onPauseAll: () {},
            onSearch: () => searched++,
          )
        ]));
      }),
    ));
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsNothing);
    await tester.tap(find.byIcon(Icons.search));
    expect(searched, 1);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('搜索'), findsNothing);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();
    expect(editing, isTrue);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
    final original = settings.downloadPageActions.value;
    var hidden = original;
    for (final action in hidden.order) {
      hidden = hidden.toggle(action, false);
    }
    settings.downloadPageActions.value = hidden.withExternal(null);
    await tester.pump();
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(editing, isFalse);
    expect(find.byKey(const ValueKey('download-page-external-action')),
        findsNothing);
    expect(settings.downloadPageActions.value.enabled, isEmpty);
    settings.downloadPageActions.value = original;
    rebuild(() {});
    await tester.pump();
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'custom external action is unique, hidden rows excluded, order honored',
      (tester) async {
    final settings = StyleSetting(configWriter: (_) async => 1);
    settings.downloadPageActions.value = settings.downloadPageActions.value
        .withExternal(DownloadPageAction.pauseAll)
        .toggle(DownloadPageAction.resumeAll, false)
        .reorder(6, 0);
    int paused = 0;
    await tester.pumpWidget(GetMaterialApp(
      locale: const Locale('en', 'US'),
      translations: LocaleText(),
      home: Scaffold(
          body: DownloadPageMoreMenu(
        settings: settings,
        switchViewIcon: Icons.view_list,
        switchViewLabel: 'List',
        onToggleReorder: () {},
        onSwitchView: () {},
        onMultiSelect: () {},
        onResumeAll: () {},
        onPauseAll: () => paused++,
        onSearch: () {},
      )),
    ));
    await tester.tap(find.byIcon(Icons.pause));
    expect(paused, 1);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final entries = tester
        .widgetList<PopupMenuItem<DownloadPageAction>>(
            find.byType(PopupMenuItem<DownloadPageAction>))
        .toList();
    expect(entries.first.value, DownloadPageAction.search);
    expect(entries.map((e) => e.value),
        isNot(contains(DownloadPageAction.pauseAll)));
    expect(entries.map((e) => e.value),
        isNot(contains(DownloadPageAction.resumeAll)));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'style editor defaults, toggle, external selection, reorder and reset persist',
      (tester) async {
    Get.testMode = true;
    addTearDown(Get.reset);
    final saved = <Map>[];
    final settings = StyleSetting(configWriter: (text) async {
      saved.add(jsonDecode(text) as Map);
      return 1;
    });
    await tester.pumpWidget(GetMaterialApp(
        locale: const Locale('zh', 'CN'),
        translations: LocaleText(),
        home: DownloadPageActionsSettingPage(settings: settings)));
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.every((widget) => widget.value), isTrue);
    await tester
        .tap(find.byKey(const ValueKey('page-action-toggle-batchUpdateTask')));
    await tester.pumpAndSettle();
    expect(settings.downloadPageActions.value.enabled,
        isNot(contains(DownloadPageAction.batchUpdateTask)));
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    dropdown.onChanged!('reorder');
    await tester.pumpAndSettle();
    expect(settings.downloadPageActions.value.externalAction,
        DownloadPageAction.reorder);
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(5, 0);
    await tester.pumpAndSettle();
    expect(settings.downloadPageActions.value.order.first,
        DownloadPageAction.reorder);
    expect(saved, isNotEmpty);
    await tester.tap(find.byIcon(Icons.restore));
    await tester.pumpAndSettle();
    expect(settings.downloadPageActions.value.toJson(),
        DownloadPageActionsConfig.defaults().toJson());
    expect(tester.takeException(), isNull);
  });
}
