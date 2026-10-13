import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
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
  late final VoidCallback _frameListener = _scheduleBottomBarMeasurement;
  int? _capacity;
  double _bottomBarInset = 0;
  bool _measurementScheduled = false;

  @override
  void initState() {
    super.initState();
    _BottomBarGeometry.addListener(_frameListener);
  }

  void _scheduleBottomBarMeasurement() {
    if (!mounted || _measurementScheduled || _manager.entries.value.isEmpty || _manager.suppressed.value) {
      return;
    }
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) {
        return;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        return;
      }
      final inset = _BottomBarGeometry.insetFor(renderObject, MediaQuery.paddingOf(context));
      if ((_bottomBarInset - inset).abs() > .1) {
        setState(() => _bottomBarInset = inset);
      }
    });
  }

  @override
  void dispose() {
    _BottomBarGeometry.removeListener(_frameListener);
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
      final safePadding = MediaQuery.paddingOf(context);
      final bottomInset = math.max(_bottomBarInset, math.max(keyboard, safePadding.bottom));
      final extraBottomInset = math.max(0.0, bottomInset - safePadding.bottom);
      final maxHeight = math.max(0.0, bounds.maxHeight - safePadding.top - bottomInset - 24);
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
                alignment: Alignment.bottomRight,
                child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + extraBottomInset),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: math.min(500.0, math.max(0.0, bounds.maxWidth - 24)), maxHeight: maxHeight),
                      child: SingleChildScrollView(
                          reverse: true,
                          child: ValueListenableBuilder<List<NotificationEntry>>(
                            valueListenable: _manager.entries,
                            builder: (context, entries, _) => Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final entry in entries)
                                  NotificationCard(key: ValueKey(entry.id), entry: entry, manager: _manager)
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

/// Marks actual bottom controls without changing their size, paint or hit tests.
/// Nested bars are measured in the overlay's coordinates, not added blindly.
class NotificationBottomBar extends SingleChildRenderObjectWidget {
  const NotificationBottomBar({super.key, required Widget child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderNotificationBottomBar();
}

class _RenderNotificationBottomBar extends RenderProxyBox {
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _BottomBarGeometry.bars.add(this);
  }

  @override
  void detach() {
    _BottomBarGeometry.bars.remove(this);
    super.detach();
  }
}

class _BottomBarGeometry {
  static final Set<_RenderNotificationBottomBar> bars = {};
  static final Set<VoidCallback> _listeners = {};
  static bool _observingFrames = false;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (_observingFrames) {
      return;
    }
    _observingFrames = true;
    // Observe frames already requested by layout/animation. No polling timer or
    // continuous frame requests; disposed overlays remove their listeners.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      for (final listener in _listeners.toList()) {
        listener();
      }
    });
  }

  static void removeListener(VoidCallback listener) => _listeners.remove(listener);

  static bool _visibleUnder(RenderObject child, RenderObject root) {
    while (!identical(child, root)) {
      final parent = child.parent;
      if (parent == null || !parent.paintsChild(child)) {
        return false;
      }
      bool visible = false;
      // Offstage, hidden routes and zero-opacity controls exclude children here.
      // Checking each ancestor also avoids bars from a different Flutter view.
      parent.visitChildrenForSemantics((candidate) {
        if (identical(candidate, child)) {
          visible = true;
        }
      });
      if (!visible) {
        return false;
      }
      child = parent;
    }
    return true;
  }

  static double insetFor(RenderBox root, EdgeInsets safePadding) {
    final bounds = Offset.zero & root.size;
    final columnWidth = math.min(500.0, math.max(0.0, root.size.width - safePadding.horizontal - 24));
    final right = math.max(0.0, root.size.width - safePadding.right - 12);
    final column = Rect.fromLTRB(math.max(0.0, right - columnWidth), 0, right, root.size.height);
    double inset = 0;
    for (final bar in bars) {
      if (!bar.attached || !bar.hasSize || bar.size.isEmpty || !_visibleUnder(bar, root)) {
        continue;
      }
      final rect = Rect.fromPoints(bar.localToGlobal(Offset.zero, ancestor: root),
              bar.localToGlobal(bar.size.bottomRight(Offset.zero), ancestor: root))
          .intersect(bounds);
      if (!rect.isEmpty && rect.overlaps(column)) {
        inset = math.max(inset, root.size.height - rect.top);
      }
    }
    return inset;
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
