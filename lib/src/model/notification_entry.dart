import 'package:flutter/foundation.dart';

enum NotificationLevel {
  info,
  success,
  warning,
  error;

  Duration get duration => switch (this) {
        info || success => const Duration(seconds: 3),
        warning => const Duration(seconds: 5),
        error => const Duration(seconds: 6),
      };
}

/// Immutable presentation state; no page context or navigation ownership.
class NotificationEntry {
  final int id;
  final String message;
  final String? title;
  final NotificationLevel level;
  final VoidCallback? action;
  final String? actionLabel;
  final int count;
  final bool exiting;

  const NotificationEntry(
      {required this.id,
      required this.message,
      required this.level,
      this.title,
      this.action,
      this.actionLabel,
      this.count = 1,
      this.exiting = false});

  bool matches(NotificationEntry other) => message == other.message && title == other.title && level == other.level;

  NotificationEntry merge(NotificationEntry other) => NotificationEntry(
      id: id, message: message, title: title, level: level, action: other.action, actionLabel: other.actionLabel, count: count + 1);

  NotificationEntry leave() => NotificationEntry(
      id: id, message: message, title: title, level: level, action: action, actionLabel: actionLabel, count: count, exiting: true);
}
