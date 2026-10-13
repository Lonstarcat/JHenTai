import 'package:flutter/foundation.dart';

import '../model/notification_entry.dart';
import '../service/notification_manager.dart';

export '../model/notification_entry.dart' show NotificationLevel;

void showNotifier(String message, NotificationLevel level, {String? title, VoidCallback? action, String? actionLabel}) {
  notificationManager.show(message, level, title: title, action: action, actionLabel: actionLabel);
}
