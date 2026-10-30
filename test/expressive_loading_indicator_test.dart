import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/widget/expressive_loading_geometry.dart';
import 'package:jhentai/src/widget/expressive_loading_indicator.dart';
import 'package:jhentai/src/widget/loading_state_indicator.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

Widget host(Widget child,
        {bool tickers = true,
        bool reducedMotion = false,
        Brightness brightness = Brightness.light,
        double textScale = 1}) =>
    MaterialApp(
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepOrange, brightness: brightness)),
      home: MediaQuery(
          data: MediaQueryData(
              disableAnimations: reducedMotion,
              textScaler: TextScaler.linear(textScale)),
          child: TickerMode(enabled: tickers, child: Center(child: child))),
    );

Future<Uint8List> pixels(WidgetTester tester) async {
  final finder = find.descendant(
      of: find.byType(ExpressiveLoadingIndicator),
      matching: find.byType(RepaintBoundary));
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return Uint8List.fromList(data!.buffer.asUint8List());
  }))!;
}

bool containsColor(Uint8List data, Color color) {
  final argb = color.toARGB32();
  for (int i = 0; i < data.length; i += 4) {
    if (data[i] == ((argb >> 16) & 255) &&
        data[i + 1] == ((argb >> 8) & 255) &&
        data[i + 2] == (argb & 255) &&
        data[i + 3] == 255) {
      return true;
    }
  }
  return false;
}

double cross(Offset a, Offset b, Offset c) =>
    (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);

bool intersects(Offset a, Offset b, Offset c, Offset d) =>
    cross(a, b, c) * cross(a, b, d) < -1e-12 &&
    cross(c, d, a) * cross(c, d, b) < -1e-12;

void main() {
  test('exact seven reference shapes and an explicit closing morph', () {
    expect(ExpressiveLoadingGeometry.shapes, [
      MaterialShapes.softBurst,
      MaterialShapes.cookie9Sided,
      MaterialShapes.pentagon,
      MaterialShapes.pill,
      MaterialShapes.sunny,
      MaterialShapes.cookie4Sided,
      MaterialShapes.oval
    ]);
    for (int i = 0; i < 14; i++) {
      expect(
          ExpressiveLoadingGeometry.frame(Duration(milliseconds: i * 650))
              .index,
          i % 7);
    }
    expect(
        ExpressiveLoadingGeometry.frame(const Duration(milliseconds: 100))
            .progress,
        isNot(closeTo(100 / 650, .01)));
  });

  test('all seven morphs stay closed, finite and non-self-intersecting', () {
    for (int shape = 0; shape < 7; shape++) {
      for (int sample = 0; sample <= 20; sample++) {
        final time = Duration(
            microseconds: shape * 650000 + (sample * 649999 / 20).round());
        final path = ExpressiveLoadingGeometry.path(time);
        final metrics = path.computeMetrics().toList();
        expect(metrics.length, 1);
        final metric = metrics.single;
        expect(metric.isClosed, isTrue);
        expect(metric.length.isFinite, isTrue);
        expect(metric.length, greaterThan(1));
        final bounds = path.getBounds();
        expect(
            [bounds.left, bounds.top, bounds.right, bounds.bottom]
                .every((v) => v.isFinite),
            isTrue);
        final points = List.generate(
            96,
            (i) =>
                metric.getTangentForOffset(metric.length * i / 96)!.position);
        for (int a = 0; a < 96; a++) {
          for (int b = a + 2; b < 96; b++) {
            if (a == 0 && b == 95) {
              continue;
            }
            expect(
                intersects(points[a], points[(a + 1) % 96], points[b],
                    points[(b + 1) % 96]),
                isFalse,
                reason: 'shape $shape sample $sample edges $a/$b');
          }
        }
      }
    }
  });

  test(
      'every boundary including Oval to Soft Burst preserves contour and rotation',
      () {
    for (int index = 1; index <= 14; index++) {
      final before = Duration(microseconds: index * 650000 - 1);
      final after = Duration(microseconds: index * 650000);
      final a = ExpressiveLoadingGeometry.path(before);
      final b = ExpressiveLoadingGeometry.path(after);
      // Morphs cut cubic segments to match different feature counts. Their
      // control hulls can differ without changing the actual filled contour.
      // Check filled geometry, not Path.getBounds's loose control-point box.
      int mismatches = 0;
      for (int y = 0; y < 128; y++) {
        for (int x = 0; x < 128; x++) {
          final point = Offset((x + .5) / 128, (y + .5) / 128);
          if (a.contains(point) != b.contains(point)) {
            mismatches++;
          }
        }
      }
      expect(mismatches, 0, reason: 'contour seam $index');
      expect(
          (ExpressiveLoadingGeometry.center(before) -
                  ExpressiveLoadingGeometry.center(after))
              .distance,
          lessThan(.000001));
      final difference = ExpressiveLoadingGeometry.frame(after).rotation -
          ExpressiveLoadingGeometry.frame(before).rotation;
      expect(math.atan2(math.sin(difference), math.cos(difference)).abs(),
          lessThan(.01));
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness uses theme primary; explicit color works',
        (tester) async {
      await tester.pumpWidget(host(
          const ExpressiveLoadingIndicator(running: false),
          brightness: brightness));
      final context = tester.element(find.byType(ExpressiveLoadingIndicator));
      expect(
          containsColor(
              await pixels(tester), Theme.of(context).colorScheme.primary),
          isTrue);
      await tester.pumpWidget(host(
          const ExpressiveLoadingIndicator(running: false, color: Colors.green),
          brightness: brightness));
      expect(containsColor(await pixels(tester), Colors.green), isTrue);
    });
  }

  testWidgets('running pause freezes the exact frame; resume moves again',
      (tester) async {
    await tester.pumpWidget(host(const ExpressiveLoadingIndicator()));
    await tester.pump(const Duration(milliseconds: 120));
    await tester
        .pumpWidget(host(const ExpressiveLoadingIndicator(running: false)));
    final paused = await pixels(tester);
    await tester.pump(const Duration(seconds: 5));
    expect(await pixels(tester), orderedEquals(paused));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(host(const ExpressiveLoadingIndicator()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(await pixels(tester), isNot(orderedEquals(paused)));
  });

  testWidgets('ticks change painted pixels without rebuilding the widget',
      (tester) async {
    await tester.pumpWidget(host(const ExpressiveLoadingIndicator()));
    await tester.pump(const Duration(milliseconds: 100));
    final before = await pixels(tester);
    await tester.pump(const Duration(milliseconds: 280));
    expect(await pixels(tester), isNot(orderedEquals(before)));
  });

  testWidgets('accessible navigation alone does not disable loading animation',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            accessibleNavigation: true, disableAnimations: false),
        child: Center(child: ExpressiveLoadingIndicator()),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final before = await pixels(tester);
    await tester.pump(const Duration(milliseconds: 280));
    expect(await pixels(tester), isNot(orderedEquals(before)));
  });

  testWidgets(
      'hidden, muted, reduced-motion, background and disposal stop ticking',
      (tester) async {
    for (final child in [
      host(const ExpressiveLoadingIndicator(visible: false)),
      host(const ExpressiveLoadingIndicator(), tickers: false),
      host(const ExpressiveLoadingIndicator(), reducedMotion: true),
      host(const ExpressiveLoadingIndicator(reducedMotion: true))
    ]) {
      await tester.pumpWidget(child);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.binding.transientCallbackCount, 0);
    }
    await tester.pumpWidget(host(const ExpressiveLoadingIndicator()));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('Offstage tab stops and resumes without jumping elapsed time',
      (tester) async {
    Widget tab(bool active) => host(Offstage(
        offstage: !active,
        child: TickerMode(
            enabled: active, child: const ExpressiveLoadingIndicator())));
    await tester.pumpWidget(tab(true));
    await tester.pump(const Duration(milliseconds: 150));
    final before = await pixels(tester);
    await tester.pumpWidget(tab(false));
    await tester.pump(const Duration(seconds: 20));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(tab(true));
    expect(await pixels(tester), orderedEquals(before));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await pixels(tester), isNot(orderedEquals(before)));
  });

  testWidgets('rapid state changes do not create extra tickers',
      (tester) async {
    for (int i = 0; i < 30; i++) {
      await tester.pumpWidget(host(
          ExpressiveLoadingIndicator(running: i.isEven, visible: i % 3 != 0)));
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.binding.transientCallbackCount, lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('size and text scaling do not change the reserved footprint',
      (tester) async {
    for (final side in [16.0, 24.0, 32.0, 48.0, 72.0]) {
      for (final scale in [1.0, 2.0]) {
        await tester.pumpWidget(host(
            ExpressiveLoadingIndicator(size: side, running: false),
            textScale: scale));
        expect(tester.getSize(find.byType(ExpressiveLoadingIndicator)),
            Size.square(side));
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('tick repaint does not rebuild the surrounding page',
      (tester) async {
    int builds = 0;
    await tester.pumpWidget(host(Builder(builder: (_) {
      builds++;
      return const ExpressiveLoadingIndicator();
    })));
    final initialBuilds = builds;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, initialBuilds);
  });

  testWidgets(
      'shared loading visual changes but deterministic progress remains native',
      (tester) async {
    await tester.pumpWidget(
        host(const Column(mainAxisSize: MainAxisSize.min, children: [
      LoadingStateIndicator(loadingState: LoadingState.loading),
      CircularProgressIndicator(value: .6),
      LinearProgressIndicator(value: .4),
      Builder(builder: UIConfig.loadingAnimation),
    ])));
    expect(find.byType(ExpressiveLoadingIndicator), findsNWidgets(2));
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        .6);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        .4);
  });

  test('optional vector contact sheet for visual inspection', () async {
    const destination = String.fromEnvironment('EXPRESSIVE_PREVIEW_PATH');
    if (destination.isEmpty) {
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xfff6f0ff), BlendMode.src);
    const labels = [
      'Soft Burst',
      'Cookie 9',
      'Pentagon',
      'Pill',
      'Sunny',
      'Cookie 4',
      'Oval'
    ];
    for (int row = 0; row < 2; row++) {
      for (int shape = 0; shape < 7; shape++) {
        canvas.save();
        canvas.translate(shape * 128 + 16, row * 150 + 12);
        ExpressiveLoadingGeometry.paint(
            canvas,
            const Size.square(96),
            Duration(milliseconds: shape * 650 + (row == 0 ? 0 : 150)),
            const Color(0xff6750a4));
        canvas.restore();
        final painter = TextPainter(
            text: TextSpan(
                text: row == 0 ? labels[shape] : 'morph ${shape + 1}',
                style: const TextStyle(color: Colors.black, fontSize: 12)),
            textDirection: TextDirection.ltr)
          ..layout();
        painter.paint(canvas, Offset(shape * 128 + 12, row * 150 + 115));
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(896, 300);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(destination).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  });
}
