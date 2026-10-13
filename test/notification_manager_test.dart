import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jhentai/src/model/notification_entry.dart';
import 'package:jhentai/src/service/notification_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Clock clock;
  late NotificationManager manager;
  setUp(() {
    clock = _Clock();
    manager = NotificationManager(timerFactory: clock.timer, now: () => clock.now)..attach(capacity: 4);
  });
  tearDown(() => manager.dispose());

  test('fixed lifetimes: info/success 3s, warning 5s, error 6s', () {
    expect(NotificationLevel.values.map((e) => e.duration.inSeconds), [3, 3, 5, 6]);
    manager.show('info', NotificationLevel.info);
    clock.advance(const Duration(seconds: 3));
    expect(manager.entries.value.single.exiting, isTrue);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value, isEmpty);
  });
  test('desktop/mobile capacity and queued items start timing only on presentation', () {
    manager.setCapacity(2);
    for (int i = 0; i < 5; i++) {
      manager.show('$i', NotificationLevel.info);
    }
    expect(manager.entries.value.length, 2);
    expect(manager.pending.length, 3);
    manager.dismiss(manager.entries.value.first.id);
    expect(manager.entries.value.length, 2);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value.map((e) => e.message), contains('2'));
    expect(manager.pending.length, 2);
    manager.setCapacity(4);
    expect(manager.entries.value.length, 4);
  });
  test('visible duplicates merge counts and renew their lifetime without a new id', () {
    manager.show('saved', NotificationLevel.success);
    final id = manager.entries.value.single.id;
    clock.advance(const Duration(seconds: 2));
    manager.show('saved', NotificationLevel.success);
    expect(manager.entries.value.single.id, id);
    expect(manager.entries.value.single.count, 2);
    clock.advance(const Duration(seconds: 2));
    expect(manager.entries.value.single.exiting, isFalse);
    clock.advance(const Duration(seconds: 1));
    expect(manager.entries.value.single.exiting, isTrue);
  });
  test('pending duplicate replaces action, errors are FIFO ahead of normal messages', () {
    manager.detach();
    int value = 0;
    manager.show('normal', NotificationLevel.info);
    manager.show('error 1', NotificationLevel.error, action: () => value = 1);
    manager.show('error 1', NotificationLevel.error, action: () => value = 2);
    manager.show('error 2', NotificationLevel.error);
    expect(manager.pending.length, 3);
    expect(clock.active, 0);
    manager.attach(capacity: 1);
    expect(manager.entries.value.single.message, 'error 1');
    manager.invokeAction(manager.entries.value.single.id);
    expect(value, 2);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value.single.message, 'error 2');
  });
  test('error preempts lowest-priority oldest non-error after its exit, never exceeding capacity', () {
    manager.setCapacity(2);
    manager.show('warning', NotificationLevel.warning);
    manager.show('info', NotificationLevel.info);
    manager.show('error', NotificationLevel.error);
    expect(manager.entries.value.length, 2);
    expect(manager.entries.value.firstWhere((e) => e.message == 'info').exiting, isTrue);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value.map((e) => e.message), ['error', 'warning']);
  });
  test('all-error saturation preserves FIFO rather than evicting current errors', () {
    manager.setCapacity(1);
    manager.show('first', NotificationLevel.error);
    manager.show('second', NotificationLevel.error);
    expect(manager.entries.value.single.exiting, isFalse);
    expect(manager.pending.single.message, 'second');
  });
  test('suppression combines lock/background, preserves remaining lifetime and pending items', () {
    manager.show('secret title', NotificationLevel.success);
    clock.advance(const Duration(seconds: 1));
    manager.setSuppressed('lock', true);
    manager.setSuppressed('background', true);
    clock.advance(const Duration(minutes: 1));
    manager.show('waiting', NotificationLevel.info);
    manager.setSuppressed('background', false);
    expect(manager.suppressed.value, isTrue);
    expect(manager.pending.single.message, 'waiting');
    manager.setSuppressed('lock', false);
    expect(manager.suppressed.value, isFalse);
    clock.advance(const Duration(seconds: 1));
    expect(manager.entries.value.firstWhere((e) => e.message == 'secret title').exiting, isFalse);
    clock.advance(const Duration(seconds: 1));
    expect(manager.entries.value.firstWhere((e) => e.message == 'secret title').exiting, isTrue);
  });
  test('drag holds only its own lifetime, cancelling drag resumes and allows error preemption', () {
    manager.setCapacity(1);
    manager.show('normal', NotificationLevel.info);
    final id = manager.entries.value.single.id;
    manager.setDragging(id, true);
    manager.show('error', NotificationLevel.error);
    clock.advance(const Duration(seconds: 10));
    expect(manager.entries.value.single.exiting, isFalse);
    manager.setDragging(id, false);
    expect(manager.entries.value.single.exiting, isTrue);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value.single.message, 'error');
  });
  test('action executes once, callback failures do not corrupt queue', () {
    int calls = 0;
    manager.show('action', NotificationLevel.info, action: () => calls++);
    final id = manager.entries.value.single.id;
    manager.invokeAction(id);
    manager.invokeAction(id);
    expect(calls, 1);
    final failures = <Object>[];
    final failing = NotificationManager(onActionError: (error, _) => failures.add(error))..attach(capacity: 1);
    failing.show('throw', NotificationLevel.info, action: () => throw StateError('test'));
    failing.invokeAction(failing.entries.value.single.id);
    expect(failures.length, 1);
    expect(failing.entries.value.single.exiting, isTrue);
    failing.dispose();
  });
  test('capacity decrease exits excess items; clear/dispose cancels all callbacks', () {
    for (int i = 0; i < 4; i++) {
      manager.show('$i', NotificationLevel.info);
    }
    manager.setCapacity(2);
    expect(manager.entries.value.where((e) => e.exiting).length, 2);
    clock.advance(NotificationManager.exitDuration);
    expect(manager.entries.value.length, 2);
    manager.clear();
    expect(clock.active, 0);
    clock.advance(const Duration(minutes: 1));
    expect(manager.entries.value, isEmpty);
    manager.dispose();
    manager.show('ignored', NotificationLevel.info);
  });
  test('queue is bounded and preserves errors when trimming ordinary items', () {
    manager.detach();
    manager.show('important', NotificationLevel.error);
    for (int i = 0; i < 150; i++) {
      manager.show('$i', NotificationLevel.info);
    }
    expect(manager.pending.length, NotificationManager.maxPending);
    expect(manager.pending.any((e) => e.message == 'important'), isTrue);
    manager.attach(capacity: 4);
    expect(manager.entries.value.any((e) => e.message == 'important'), isTrue);
  });
}

class _Clock {
  DateTime now = DateTime.utc(2026, 1, 1);
  final List<_TestTimer> timers = [];
  int get active => timers.where((timer) => timer.isActive).length;
  Timer timer(Duration duration, void Function() callback) {
    final timer = _TestTimer(now.add(duration), callback);
    timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    final end = now.add(duration);
    while (true) {
      final due = timers.where((timer) => timer.isActive && !timer.at.isAfter(end)).toList()..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) {
        break;
      }
      final timer = due.first;
      now = timer.at;
      timer.fire();
    }
    now = end;
  }
}

class _TestTimer implements Timer {
  final DateTime at;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  _TestTimer(this.at, this.callback);
  void fire() {
    isActive = false;
    tick = 1;
    callback();
  }

  @override
  void cancel() {
    isActive = false;
  }
}
