import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../model/notification_entry.dart';
import '../service/notification_manager.dart';
import 'notification_card.dart';

/// Root Stack is transparent outside the cards, including above nested routes.
class NotificationOverlay extends StatefulWidget {
  final Widget child;
  final NotificationManager? manager;
  const NotificationOverlay({super.key, required this.child, this.manager});
  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay> {
  late final NotificationManager _manager = widget.manager ?? notificationManager;
  int? _capacity;
  @override
  void dispose() {
    _manager.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, bounds) {
      final platform = Theme.of(context).platform;
      final mobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS || bounds.maxWidth < 600;
      final capacity = mobile ? 2 : 4;
      if (_capacity != capacity) {
        _capacity = capacity;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _manager.attach(capacity: capacity);
          }
        });
      }
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final maxHeight = math.max(0.0, bounds.maxHeight - MediaQuery.paddingOf(context).vertical - keyboard - 24);
      return Stack(fit: StackFit.expand, children: [
        widget.child,
        ValueListenableBuilder<bool>(
            valueListenable: _manager.suppressed,
            builder: (context, hidden, _) {
              if (hidden) {
                return const SizedBox.shrink();
              }
              return SafeArea(
                  child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: math.min(500.0, math.max(0.0, bounds.maxWidth - 24)), maxHeight: maxHeight),
                      child: SingleChildScrollView(
                          child: ValueListenableBuilder<List<NotificationEntry>>(
                        valueListenable: _manager.entries,
                        builder: (context, entries, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final entry in entries) NotificationCard(key: ValueKey(entry.id), entry: entry, manager: _manager)
                          ],
                        ),
                      )),
                    )),
              ));
            }),
      ]);
    });
  }
}

/// Root navigator only: dialogs on a lock page cannot reveal messages.
class NotificationPrivacyObserver extends NavigatorObserver {
  final NotificationManager manager;
  final String lockRoute;
  final List<Route<dynamic>> _routes = [];
  NotificationPrivacyObserver({required this.manager, required this.lockRoute});
  void _sync() {
    final pages = _routes.whereType<PageRoute<dynamic>>();
    manager.setSuppressed('lock', pages.isNotEmpty && pages.last.settings.name == lockRoute);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _sync();
  }
}
