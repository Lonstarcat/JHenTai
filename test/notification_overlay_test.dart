import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/service/notification_manager.dart';
import 'package:jhentai/src/utils/toast_util.dart';
import 'package:jhentai/src/utils/snack_util.dart';
import 'package:jhentai/src/widget/notification_card.dart';
import 'package:jhentai/src/widget/notification_overlay.dart';

Widget host(NotificationManager manager,
        {Brightness brightness = Brightness.light, TargetPlatform platform = TargetPlatform.macOS, Widget? body}) =>
    MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple, brightness: brightness), platform: platform),
        builder: (context, child) => NotificationOverlay(manager: manager, child: child!),
        home: Scaffold(body: body ?? const SizedBox.expand()));

void main() {
  late NotificationManager manager;
  setUp(() => manager = NotificationManager());
  tearDown(() => manager.dispose());

  testWidgets('top-right, exact entrance/exit, fixed bounds and background taps pass through', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int taps = 0;
    await tester.pumpWidget(host(manager, body: Center(child: TextButton(onPressed: () => taps++, child: const Text('page button')))));
    manager.show('Saved', NotificationLevel.success);
    await tester.pump();
    final card = find.byType(NotificationCard);
    final opacity = find.descendant(of: card, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(opacity).opacity, 0);
    final transforms = tester.widgetList<Transform>(find.descendant(of: card, matching: find.byType(Transform))).toList();
    expect(transforms[0].transform.storage[13], -16);
    expect(transforms[1].transform.storage[0], closeTo(.94, .001));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<Opacity>(opacity).opacity, 1);
    final rect = tester.getRect(card);
    expect(rect.right, closeTo(1188, 1));
    expect(rect.top, closeTo(12, 1));
    expect(rect.width, lessThanOrEqualTo(500));
    expect(rect.height, greaterThanOrEqualTo(52));
    await tester.tap(find.text('page button'));
    expect(taps, 1);
    manager.dismiss(manager.entries.value.single.id);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<Opacity>(opacity).opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(card, findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  for (final direction in [-1, 1]) {
    testWidgets('swipe $direction dismisses without losing other cards', (tester) async {
      await tester.pumpWidget(host(manager));
      manager.show('swipe me', NotificationLevel.info);
      manager.show('keep me', NotificationLevel.warning);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      final card = find.ancestor(of: find.text('swipe me'), matching: find.byType(NotificationCard));
      await tester.drag(card, Offset(direction * 500.0, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('swipe me'), findsNothing);
      expect(find.text('keep me'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile max2, dark/light, long text and keyboard/short viewport do not overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(host(manager, brightness: brightness, platform: TargetPlatform.android));
      for (int i = 0; i < 4; i++) {
        manager.show('Long message $i ${'text ' * 60}', NotificationLevel.error, title: 'Title', action: () {});
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byType(NotificationCard), findsNWidgets(2));
      expect(manager.pending.length, 2);
      final text = tester.widget<Text>(find.text('Title').first);
      expect(text.style?.color, Theme.of(tester.element(find.text('Title').first)).colorScheme.onSurface);
      expect(tester.takeException(), isNull);
      manager.clear();
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('root route change keeps messages, lock and dialogs hide them, unlock resumes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [NotificationPrivacyObserver(manager: manager, lockRoute: '/lock')],
        builder: (context, child) => NotificationOverlay(manager: manager, child: child!),
        home: const Scaffold(body: Text('home'))));
    manager.show('private title', NotificationLevel.info);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    nav.currentState!.push(
        MaterialPageRoute<void>(settings: const RouteSettings(name: '/details'), builder: (_) => const Scaffold(body: Text('details'))));
    await tester.pumpAndSettle();
    expect(find.text('private title'), findsOneWidget);
    nav.currentState!
        .push(MaterialPageRoute<void>(settings: const RouteSettings(name: '/lock'), builder: (_) => const Scaffold(body: Text('locked'))));
    await tester.pumpAndSettle();
    expect(find.text('private title'), findsNothing);
    expect(manager.suppressed.value, isTrue);
    showDialog<void>(context: nav.currentContext!, builder: (_) => const AlertDialog(content: Text('lock dialog')));
    await tester.pumpAndSettle();
    expect(find.text('private title'), findsNothing);
    nav.currentState!.pop();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('private title'), findsOneWidget);
    expect(manager.suppressed.value, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy wrappers work without page context; action/card click is once-only', (tester) async {
    int actions = 0;
    notificationManager.clear();
    await tester.pumpWidget(host(notificationManager));
    toast('global success', level: NotificationLevel.success);
    snack('Info title', 'global action', level: NotificationLevel.info, onPressed: () => actions++);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(notificationManager.entries.value.any((e) => e.level == NotificationLevel.success), isTrue);
    await tester.tap(find.text('global action'));
    expect(actions, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('global action'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(notificationManager.entries.value, isEmpty);
  });

  testWidgets('notification queued during page build does not mark parent dirty', (tester) async {
    await tester.pumpWidget(host(manager, body: Builder(builder: (_) {
      manager.show('from build', NotificationLevel.info);
      return const Text('page');
    })));
    await tester.pump();
    expect(find.text('from build'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
