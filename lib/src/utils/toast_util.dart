import 'package:flutter/widgets.dart';
import 'notifier_util.dart';
export 'notifier_util.dart';

/// Compatibility only. NotificationOverlay now owns context and lifecycle.
void initToast(BuildContext context) {}

/// Legacy flags remain accepted; notification level determines the duration.
void toast(String msg, {bool isCenter = true, bool isShort = true, NotificationLevel level = NotificationLevel.info}) {
  showNotifier(msg, level);
}
