import 'package:flutter/foundation.dart';
import 'notifier_util.dart';
export 'notifier_util.dart';

/// Most legacy snacks are failures; informational callers explicitly opt in.
void snack(String title, String message,
    {bool isShort = true, VoidCallback? onPressed, NotificationLevel level = NotificationLevel.error}) {
  showNotifier(message, level, title: title, action: onPressed, actionLabel: '→');
}
