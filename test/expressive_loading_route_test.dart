import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/pages/details/details_page.dart';
import 'package:jhentai/src/pages/details/details_page_logic.dart';
import 'package:jhentai/src/widget/expressive_loading_indicator.dart';
import 'package:jhentai/src/widget/loading_state_indicator.dart';

class _DetailsLogic extends DetailsPageLogic {
  _DetailsLogic() : super.preview() {
    state.galleryUrl = GalleryUrl.parse('https://e-hentai.org/g/1/0123456789/');
  }

  @override
  void onReady() {} // Never request a gallery from the network.
}

Widget _detailHeader() {
  final logic = _DetailsLogic();
  final page = DetailsPage.preview()
    ..logic = logic
    ..state = logic.state;
  return Scaffold(
    body: Builder(
      builder: (context) =>
          CustomScrollView(slivers: [page.buildDetail(context)]),
    ),
  );
}

Future<Uint8List> _pixels(WidgetTester tester, {int index = -1}) async {
  final indicators = find.byType(ExpressiveLoadingIndicator);
  final boundary = tester.renderObject<RenderRepaintBoundary>(find
      .descendant(
        of: index < 0 ? indicators.last : indicators.at(index),
        matching: find.byType(RepaintBoundary),
      )
      .last);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return Uint8List.fromList(bytes!.buffer.asUint8List());
  }))!;
}

Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _expectMoving(WidgetTester tester) async {
  final before = await _pixels(tester);
  await _frames(tester, 5);
  expect(await _pixels(tester), isNot(orderedEquals(before)));
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  testWidgets('actual details cover animates after push, cover and return',
      (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(GetMaterialApp(
      navigatorKey: nav,
      theme: ThemeData(platform: TargetPlatform.android),
      home: const Scaffold(),
    ));
    for (int i = 0; i < 3; i++) {
      nav.currentState!
          .push(MaterialPageRoute<void>(builder: (_) => _detailHeader()));
      await _frames(tester);
      await _expectMoving(tester);
      nav.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('covered'))));
      await _frames(tester);
      nav.currentState!.pop();
      await _frames(tester);
      await _expectMoving(tester);
      nav.currentState!.pop();
      await _frames(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('constant shared loader resumes after initially muted route',
      (tester) async {
    final active = ValueNotifier<bool>(false);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: active,
        child: const Center(child: Builder(builder: UIConfig.loadingAnimation)),
        builder: (_, value, child) => TickerMode(enabled: value, child: child!),
      ),
    ));
    await _frames(tester);
    expect(tester.binding.transientCallbackCount, 0);
    for (int i = 0; i < 3; i++) {
      active.value = true;
      await _frames(tester, 2);
      await _expectMoving(tester);
      active.value = false;
      await _frames(tester, 2);
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('visible inactive Android detail and shared loaders keep moving',
      (tester) async {
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    // Android can be visible but inactive while temporarily lacking window
    // focus. New details mounted in this state must not freeze on frame zero.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpWidget(GetMaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: _detailHeader(),
    ));
    await _frames(tester, 2);
    await _expectMoving(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester, 2);
    await _expectMoving(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _frames(tester, 2);
    await _expectMoving(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'shared page, compact and dialog loaders respect visible lifecycle',
      (tester) async {
    addTearDown(() => tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          LoadingStateIndicator(loadingState: LoadingState.loading),
          ExpressiveLoadingIndicator(size: 16),
          ExpressiveLoadingIndicator(size: 18),
          ExpressiveLoadingIndicator(size: 20),
        ]),
      ),
    ));
    for (final lifecycle in [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(lifecycle);
      await _frames(tester, 2);
      final before = <Uint8List>[];
      for (int index = 0; index < 4; index++) {
        before.add(await _pixels(tester, index: index));
      }
      await _frames(tester, 5);
      final visible = lifecycle == AppLifecycleState.resumed ||
          lifecycle == AppLifecycleState.inactive;
      for (int index = 0; index < 4; index++) {
        expect(
            await _pixels(tester, index: index),
            visible
                ? isNot(orderedEquals(before[index]))
                : orderedEquals(before[index]),
            reason: '$lifecycle loader $index');
      }
      expect(tester.binding.transientCallbackCount, visible ? 4 : 0);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });
}
