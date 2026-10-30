import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages/base/base_page.dart';
import 'package:jhentai/src/pages/download_search/download_search_logic.dart';
import 'package:jhentai/src/pages/download_search/download_search_page.dart';
import 'package:jhentai/src/pages/search/desktop/desktop_search_page_tab_logic.dart';
import 'package:jhentai/src/pages/search/mixin/new_search_argument.dart';
import 'package:jhentai/src/pages/search/mixin/search_page_logic_mixin.dart';
import 'package:jhentai/src/pages/search/mixin/search_page_mixin.dart';
import 'package:jhentai/src/pages/search/mixin/search_page_state_mixin.dart';
import 'package:jhentai/src/pages/search/mobile_v2/search_page_mobile_v2_logic.dart';
import 'package:jhentai/src/pages/search/mobile_v2/search_page_mobile_v2_state.dart';
import 'package:jhentai/src/pages/search/desktop/desktop_search_page_tab_state.dart';
import 'package:jhentai/src/setting/preference_setting.dart';

// Exercise the production search field and entry-intent flags without accessing
// a real account, database, library or network. Business callbacks are spies.
class _MobileLogic extends SearchPageMobileV2Logic {
  _MobileLogic({this.configReady});

  final Completer<void>? configReady;

  // Skip live configuration I/O; production focus ownership is unchanged.
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    await configReady?.future;
    state.searchConfigInitCompleter.complete();
  }

  @override
  Future<void> onReady() async {}

  @override
  Future<void> handleClearAndRefresh() async {
    state.searchFieldFocusNode.unfocus();
    state.hasSearched = true;
  }

  @override
  Future<void> onInputChanged(String value) async {
    state.searchConfig.keyword = value;
  }
}

class _DesktopLogic extends DesktopSearchPageTabLogic {
  _DesktopLogic(bool loadImmediately)
      : super(
          const NewSearchArgument(keyword: '', keywordSearchBehaviour: SearchBehaviour.none),
          loadImmediately,
        );

  // Skip live configuration I/O in this field-only fixture.
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    state.searchConfigInitCompleter.complete();
  }

  @override
  Future<void> onReady() async {}
}

class _FieldPage<L extends SearchPageLogicMixin, S extends SearchPageStateMixin> extends BasePage<L, S> with SearchPageMixin<L, S> {
  const _FieldPage({required this.logic, required this.state});

  @override
  final L logic;
  @override
  final S state;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          buildSearchField(),
          const TextField(key: ValueKey('other-field')),
        ]),
      );
}

class _DownloadLogic extends DownloadSearchLogic {
  // Skip live configuration I/O in this field-only fixture.
  @override
  // ignore: must_call_super
  Future<void> onInit() async {
    textEditingController = TextEditingController();
    searchFocusNode = FocusNode();
    scrollController = ScrollController();
    state.searchTypeCompleter.complete();
  }
}

Future<void> _settleInput(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  testWidgets('normal search focuses once, opens input and preserves selection', (tester) async {
    final logic = _MobileLogic()..onStart();
    addTearDown(logic.onDelete);
    await tester.pumpWidget(GetMaterialApp(
      home: _FieldPage<_MobileLogic, SearchPageMobileV2State>(logic: logic, state: logic.state),
    ));
    await _settleInput(tester);
    expect(logic.state.searchFieldFocusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'sample');
    tester.testTextInput.updateEditingValue(const TextEditingValue(text: 'sample', selection: TextSelection.collapsed(offset: 2)));
    logic.update([logic.suggestionBodyId]);
    await tester.pump();
    expect(tester.widget<TextField>(search).controller!.selection.baseOffset, 2);

    await tester.tap(find.byKey(const ValueKey('other-field')));
    logic.update([logic.searchFieldId]);
    await _settleInput(tester);
    expect(logic.state.searchFieldFocusNode.hasFocus, isFalse);
    expect(tester.widget<TextField>(search).controller!.text, 'sample');

    await tester.tap(search);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await _settleInput(tester);
    expect(logic.state.hasSearched, isTrue);
    expect(logic.state.searchFieldFocusNode.hasFocus, isFalse);

    final context = tester.element(search);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('detail'))));
    await tester.pumpAndSettle();
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    expect(logic.state.searchFieldFocusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tag-result entry does not request the mobile keyboard', (tester) async {
    late _MobileLogic logic;
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    Get.to<void>(() {
      logic = _MobileLogic()..onStart();
      return _FieldPage<_MobileLogic, SearchPageMobileV2State>(logic: logic, state: logic.state);
    }, arguments: const NewSearchArgument(keyword: 'tag', keywordSearchBehaviour: SearchBehaviour.none));
    await tester.pumpAndSettle();
    addTearDown(logic.onDelete);
    expect(logic.autofocusSearchField, isFalse);
    expect(logic.state.searchFieldFocusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late search configuration does not re-open the keyboard', (tester) async {
    final ready = Completer<void>();
    final logic = _MobileLogic(configReady: ready)..onStart();
    addTearDown(logic.onDelete);
    await tester.pumpWidget(GetMaterialApp(
      home: _FieldPage<_MobileLogic, SearchPageMobileV2State>(logic: logic, state: logic.state),
    ));
    await _settleInput(tester);
    expect(logic.state.searchFieldFocusNode.hasFocus, isTrue);
    await tester.tap(find.byKey(const ValueKey('other-field')));
    ready.complete();
    await _settleInput(tester);
    expect(logic.state.searchFieldFocusNode.hasFocus, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final loadImmediately in [false, true]) {
    testWidgets('desktop input entry, loadImmediately=$loadImmediately', (tester) async {
      final logic = _DesktopLogic(loadImmediately)..onStart();
      addTearDown(logic.onDelete);
      await tester.pumpWidget(GetMaterialApp(
        home: _FieldPage<_DesktopLogic, DesktopSearchPageTabState>(logic: logic, state: logic.state),
      ));
      await _settleInput(tester);
      expect(logic.state.searchFieldFocusNode.hasFocus, !loadImmediately);
      expect(tester.testTextInput.isVisible, !loadImmediately);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('download search opens input, mode rebuild does not steal focus', (tester) async {
    final logic = Get.put<DownloadSearchLogic>(_DownloadLogic());
    await tester.pumpWidget(GetMaterialApp(home: DownloadSearchPage()));
    await _settleInput(tester);
    expect(logic.searchFocusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // No query is scheduled: only the production focus/clear/rebuild path runs.
    await tester.tap(find.byIcon(Icons.cancel));
    logic.searchFocusNode.unfocus();
    logic.state.caseSensitive = false;
    logic.update([logic.searchFieldId]);
    await _settleInput(tester);
    expect(logic.searchFocusNode.hasFocus, isFalse);
    expect(logic.textEditingController.text, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('download search quick close and fresh re-entry are safe', (tester) async {
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));
    for (final closeImmediately in [true, false, false]) {
      final logic = Get.put<DownloadSearchLogic>(_DownloadLogic());
      Get.to<void>(DownloadSearchPage.new);
      await tester.pump();
      if (!closeImmediately) {
        await _settleInput(tester);
        expect(logic.searchFocusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      }
      Get.back<void>();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await Get.delete<DownloadSearchLogic>(force: true);
      expect(tester.takeException(), isNull);
    }
  });
}
