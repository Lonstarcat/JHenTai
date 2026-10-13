import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/pages/download/list/widget/download_reorder_view.dart';

void main() {
  for (final count in [200, 500]) {
    testWidgets('$count rows use viewport-lazy construction', (tester) async {
      final built = <String>{};
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final items = [for (int i = 0; i < count; i++) 'A$i'];
      await tester.pumpWidget(_host(controller, {'A': items}, built: built));
      await tester.pump();
      expect(built.length, lessThan(20));
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ReorderableListView), findsNothing);
      debugPrint('SLIVER PROBE: built ${built.length}/$count');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('$platform group collapse retains original pointer', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final results = <(int, int)>[];
      await tester.pumpWidget(_host(
          controller,
          {
            'A': ['A1', 'A2'],
            'B': ['B1', 'B2']
          },
          onGroups: (groups, from, to) => results.add((from, to))));
      final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator).first),
          kind: platform == TargetPlatform.macOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch);
      // Move before the replacement sliver is laid out: pointer must not be lost.
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      expect(find.byKey(const ValueKey('row:A1')), findsNothing);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('B')) - const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(results, [(0, 1)]);
      expect(find.byKey(const ValueKey('row:A1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('quick group tap and pointer cancel leave no stale drag', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, {
      'A': ['A1'],
      'B': ['B1']
    }));
    final gesture = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator).first));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row:A1')), findsOneWidget);
    final cancelled = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator).first));
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row:A1')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Android cards require long press before reorder', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final results = <(String, int, int)>[];
    await tester.pumpWidget(_host(
        controller,
        {
          'A': ['A1', 'A2', 'A3'],
          'B': ['B1']
        },
        onItems: (group, items, from, to) => results.add((group, from, to))));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('row:A1'))));
    await tester.pump(kLongPressTimeout - const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('row:A1')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2));
    await gesture.moveBy(const Offset(0, 90));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(results, [('A', 0, 2)]);
    expect(find.byKey(const ValueKey('row:B1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop drop into another group cancels instead of moving groups', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    int saves = 0;
    await tester.pumpWidget(_host(
        controller,
        {
          'A': ['A1', 'A2'],
          'B': ['B1', 'B2']
        },
        onItems: (_, __, ___, ____) => saves++));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('row:A1'))),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('row:B1'))));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.byKey(const ValueKey('row:A1')), findsOneWidget);
    expect(find.byKey(const ValueKey('row:B1')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('long group auto-scroll uses the shared controller', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller, {
      'A': [for (int i = 0; i < 200; i++) 'A$i']
    }));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('row:A0'))),
        kind: PointerDeviceKind.mouse);
    await gesture.moveTo(const Offset(400, 590));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.offset, greaterThan(0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _host(
  ScrollController controller,
  Map<String, List<String>> items, {
  Set<String>? built,
  void Function(List<String>, int, int)? onGroups,
  void Function(String, List<String>, int, int)? onItems,
}) =>
    MaterialApp(
        home: Scaffold(
            body: DownloadReorderView<String>(
      controller: controller,
      groups: items.keys.toList(),
      items: items,
      expandedGroups: items.keys.toSet(),
      itemExtent: 50,
      itemKey: (item) => ValueKey('drag:$item'),
      onToggleGroup: (_) {},
      onReorderGroups: onGroups ?? (_, __, ___) {},
      onReorderItems: onItems ?? (_, __, ___, ____) {},
      itemBuilder: (_, item) {
        built?.add(item);
        return SizedBox(key: ValueKey('row:$item'), height: 50, child: Text(item));
      },
    )));
