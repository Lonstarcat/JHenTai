import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../model/notification_entry.dart';
import 'log.dart';

typedef NotificationTimerFactory = Timer Function(Duration duration, void Function() callback);

final notificationManager = NotificationManager(
  onActionError: (error, stack) => log.error('Notification action failed', error, stack),
);

/// Timers start only when a host displays an item, never while queued/locked.
/// Exiting cards occupy their slot until the 300ms transition has finished.
class NotificationManager {
  static const exitDuration = Duration(milliseconds: 300);
  static const maxPending = 100;
  final ValueNotifier<List<NotificationEntry>> entries = ValueNotifier(const []);
  final ValueNotifier<bool> suppressed = ValueNotifier(false);
  final Queue<NotificationEntry> _pending = Queue();
  final List<NotificationEntry> _active = [];
  final Map<int, Timer> _timers = {};
  final Map<int, Timer> _exitTimers = {};
  final Map<int, DateTime> _deadlines = {};
  final Map<int, Duration> _remaining = {};
  final Set<int> _dragging = {};
  final Set<String> _suppressionReasons = {};
  final NotificationTimerFactory _timerFactory;
  final DateTime Function() _now;
  final void Function(Object, StackTrace)? onActionError;
  bool _attached = false, _disposed = false, _publishScheduled = false;
  int _nextId = 0, _capacity = 4;

  NotificationManager({NotificationTimerFactory? timerFactory, DateTime Function()? now, this.onActionError})
      : _timerFactory = timerFactory ?? Timer.new,
        _now = now ?? DateTime.now;

  List<NotificationEntry> get pending => List.unmodifiable(_pending);
  int get capacity => _capacity;
  bool get _paused => _suppressionReasons.isNotEmpty;

  void attach({required int capacity}) {
    if (_disposed) {
      return;
    }
    _attached = true;
    setCapacity(capacity);
    _drain();
  }

  void detach() {
    _attached = false;
    clear();
  }

  void setCapacity(int value) {
    if (_disposed) {
      return;
    }
    _capacity = value.clamp(1, 4);
    while (_active.where((e) => !e.exiting).length > _capacity) {
      final victim = _victim(includeErrors: true);
      if (victim == null) {
        break;
      }
      dismiss(victim.id);
    }
    _drain();
  }

  void show(String message, NotificationLevel level, {String? title, VoidCallback? action, String? actionLabel}) {
    if (_disposed || (message.trim().isEmpty && (title?.trim().isEmpty ?? true))) {
      return;
    }
    final item =
        NotificationEntry(id: ++_nextId, message: message.trim(), title: title, level: level, action: action, actionLabel: actionLabel);
    final index = _active.indexWhere((entry) => entry.matches(item));
    if (index >= 0) {
      final merged = _active[index].merge(item);
      _active[index] = merged;
      _exitTimers.remove(merged.id)?.cancel();
      _remaining.remove(merged.id);
      _startTimer(merged);
      _publish();
      return;
    }
    final queued = _pending.toList();
    final pendingIndex = queued.indexWhere((entry) => entry.matches(item));
    if (pendingIndex >= 0) {
      queued[pendingIndex] = queued[pendingIndex].merge(item);
      _pending
        ..clear()
        ..addAll(queued);
      return;
    }
    _pending.add(item);
    while (_pending.length > maxPending) {
      _pending.remove(_pending.firstWhere((e) => e.level != NotificationLevel.error, orElse: () => _pending.first));
    }
    _drain();
  }

  NotificationEntry? _victim({bool includeErrors = false}) {
    final candidates =
        _active.where((e) => !e.exiting && !_dragging.contains(e.id) && (includeErrors || e.level != NotificationLevel.error)).toList();
    candidates.sort((a, b) => a.level.index != b.level.index ? a.level.index.compareTo(b.level.index) : a.id.compareTo(b.id));
    return candidates.isEmpty ? null : candidates.first;
  }

  void _drain() {
    if (_disposed || !_attached || _paused) {
      return;
    }
    while (_pending.isNotEmpty && _active.length < _capacity) {
      final next = _pending.firstWhere((e) => e.level == NotificationLevel.error, orElse: () => _pending.first);
      _pending.remove(next);
      _active.insert(0, next);
      _startTimer(next);
    }
    if (_pending.any((e) => e.level == NotificationLevel.error) && !_active.any((e) => e.exiting)) {
      final victim = _victim();
      if (victim != null) {
        dismiss(victim.id);
      }
    }
    _publish();
  }

  void _startTimer(NotificationEntry item) {
    _timers.remove(item.id)?.cancel();
    if (_paused || !_attached || _dragging.contains(item.id) || item.exiting) {
      return;
    }
    final duration = _remaining.remove(item.id) ?? item.level.duration;
    _deadlines[item.id] = _now().add(duration);
    _timers[item.id] = _timerFactory(duration, () => dismiss(item.id));
  }

  void _pauseTimer(int id) {
    _timers.remove(id)?.cancel();
    final deadline = _deadlines.remove(id);
    if (deadline != null) {
      final left = deadline.difference(_now());
      _remaining[id] = left.isNegative ? Duration.zero : left;
    }
  }

  void setDragging(int id, bool dragging) {
    if (_disposed) {
      return;
    }
    if (dragging) {
      _dragging.add(id);
      _pauseTimer(id);
    } else {
      _dragging.remove(id);
      for (final item in _active.where((e) => e.id == id)) {
        _startTimer(item);
      }
      _drain();
    }
  }

  /// Independent reasons prevent a foreground event from exposing a lock page.
  void setSuppressed(String reason, bool value) {
    if (_disposed) {
      return;
    }
    final wasPaused = _paused;
    value ? _suppressionReasons.add(reason) : _suppressionReasons.remove(reason);
    if (!wasPaused && _paused) {
      for (final item in _active) {
        _pauseTimer(item.id);
      }
    } else if (wasPaused && !_paused) {
      for (final item in _active) {
        _startTimer(item);
      }
      _drain();
    }
    _publish();
  }

  void dismiss(int id) {
    if (_disposed) {
      return;
    }
    final index = _active.indexWhere((e) => e.id == id && !e.exiting);
    if (index < 0) {
      _pending.removeWhere((e) => e.id == id);
      return;
    }
    _pauseTimer(id);
    _dragging.remove(id);
    _active[index] = _active[index].leave();
    _exitTimers[id] = _timerFactory(exitDuration, () {
      _exitTimers.remove(id);
      _remaining.remove(id);
      _active.removeWhere((e) => e.id == id);
      _drain();
      _publish();
    });
    _publish();
  }

  void invokeAction(int id) {
    if (_disposed || _paused) {
      return;
    }
    final matches = _active.where((e) => e.id == id && !e.exiting && e.action != null);
    if (matches.isEmpty) {
      return;
    }
    final action = matches.first.action!;
    dismiss(id); // Mark first so repeated taps cannot execute twice.
    try {
      action();
    } catch (error, stack) {
      onActionError?.call(error, stack);
    }
  }

  void _publish() {
    if (_disposed) {
      return;
    }
    void emit() {
      if (_disposed) {
        return;
      }
      entries.value = List.unmodifiable(_active);
      suppressed.value = _paused;
    }

    // Notifications can originate in initState/build of a nested page.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      if (_publishScheduled) {
        return;
      }
      _publishScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _publishScheduled = false;
        emit();
      });
    } else {
      emit();
    }
  }

  void clear() {
    for (final timer in [..._timers.values, ..._exitTimers.values]) {
      timer.cancel();
    }
    _timers.clear();
    _exitTimers.clear();
    _deadlines.clear();
    _remaining.clear();
    _dragging.clear();
    _active.clear();
    _pending.clear();
    _publish();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    clear();
    _disposed = true;
    entries.dispose();
    suppressed.dispose();
  }
}
