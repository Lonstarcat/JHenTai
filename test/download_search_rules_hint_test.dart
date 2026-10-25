import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/l18n/locale_text.dart';
import 'package:jhentai/src/pages/download_search/download_search_logic.dart';
import 'package:jhentai/src/pages/download_search/download_search_page.dart';
import 'package:jhentai/src/pages/download_search/download_search_state.dart';
import 'package:jhentai/src/pages/download_search/widget/download_search_rules_hint.dart';

// Only replace configuration I/O, keeping the production input/scheduler/clear
// lifecycle. Tests clear before debounce; no library or account is accessed.
class _SearchLogic extends DownloadSearchLogic {
  _SearchLogic(
      {this.initialMode = DownloadSearchConfigTypeEnum.simple, this.gate});
  final DownloadSearchConfigTypeEnum initialMode;
  final Completer<void>? gate;

  @override
  // Deliberately skip the production configuration/database initialization.
  // ignore: must_call_super
  Future<void> onInit() async {
    textEditingController = TextEditingController();
    searchFocusNode = FocusNode();
    scrollController = ScrollController();
    if (gate != null) {
      await gate!.future;
    }
    state.searchType = initialMode;
    state.searchTypeCompleter.complete();
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  testWidgets(
      'production page shows help, hides before debounce, restores on clear',
      (tester) async {
    final logic = Get.put<DownloadSearchLogic>(_SearchLogic());
    await tester.pumpWidget(GetMaterialApp(
      translations: LocaleText(),
      locale: const Locale('zh', 'CN'),
      home: DownloadSearchPage(),
    ));
    await tester.pump();
    expect(find.byType(DownloadSearchRulesHint), findsOneWidget);
    expect(find.text('+A +B|C -D'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump(); // No 300 ms delay: help must already be gone.
    expect(find.byType(DownloadSearchRulesHint), findsNothing);
    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();
    expect(logic.textEditingController.text, isEmpty);
    expect(find.byType(DownloadSearchRulesHint), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DownloadSearchRulesHint), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'B');
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(DownloadSearchRulesHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.byType(DownloadSearchRulesHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored regex mode refreshes empty help after async config',
      (tester) async {
    final gate = Completer<void>();
    Get.put<DownloadSearchLogic>(_SearchLogic(
        initialMode: DownloadSearchConfigTypeEnum.regex, gate: gate));
    await tester.pumpWidget(GetMaterialApp(
      translations: LocaleText(),
      locale: const Locale('en', 'US'),
      home: DownloadSearchPage(),
    ));
    expect(find.text('+tomboy +stocking'), findsOneWidget);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('+tomboy +stocking'), findsNothing);
    expect(find.text(r'(?=.*A)(?=.*B)'), findsOneWidget);
    expect(find.text('Aa → aa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
    Locale('ko', 'KR'),
    Locale('pt', 'BR'),
    Locale('ru', 'RU')
  ]) {
    for (final dark in [false, true]) {
      testWidgets('help wraps at 320px/2x text, $locale dark=$dark',
          (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final regexMode in [false, true]) {
          await tester.pumpWidget(GetMaterialApp(
            translations: LocaleText(),
            locale: locale,
            theme: dark ? ThemeData.dark() : ThemeData.light(),
            home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(320, 640), textScaler: TextScaler.linear(2)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: DownloadSearchRulesHint(regexMode: regexMode))),
            ),
          ));
          await tester.pump();
          expect(find.text('downloadSearchRules'), findsNothing);
          expect(find.text('downloadSearchCaseHint'), findsNothing);
          expect(find.text('Aa → aa'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.drag(
              find.byType(SingleChildScrollView).first, const Offset(0, -800));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
