import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../config/ui_config.dart';
import 'download_reorder_widgets.dart';

/// One viewport for all groups: even a large expanded group remains lazy.
/// Group headers switch to a single header-only sliver during a group drag.
class DownloadReorderView<T> extends StatefulWidget {
  const DownloadReorderView(
      {super.key,
      required this.controller,
      required this.groups,
      required this.items,
      required this.expandedGroups,
      required this.itemKey,
      required this.itemBuilder,
      required this.onToggleGroup,
      required this.onReorderGroups,
      required this.onReorderItems,
      this.itemExtent = UIConfig.downloadPageCardHeight + 10});

  final ScrollController controller;
  final List<String> groups;
  final Map<String, List<T>> items;
  final Set<String> expandedGroups;
  final Key Function(T) itemKey;
  final Widget Function(BuildContext, T) itemBuilder;
  final void Function(String) onToggleGroup;
  final void Function(List<String>, int, int) onReorderGroups;
  final void Function(String, List<T>, int, int) onReorderItems;
  final double itemExtent;

  @override
  State<DownloadReorderView<T>> createState() => _DownloadReorderViewState<T>();
}

class _DownloadReorderViewState<T> extends State<DownloadReorderView<T>> {
  static const double _headerExtent = UIConfig.groupListHeight + 10;
  final GlobalKey _viewportKey = GlobalKey();
  final GlobalKey<SliverReorderableListState> _groupListKey = GlobalKey();
  final Map<String, GlobalKey<SliverReorderableListState>> _itemListKeys = {};
  final Map<String, double> _itemStarts = {};
  bool _groupMode = false;
  bool _dragStarted = false;
  int? _pointer;
  String? _pointerGroup;
  Offset? _pointerPosition;
  bool _dropInsideGroup = true;
  List<String>? _dragGroups;
  Map<String, List<T>>? _dragItems;
  Set<String>? _dragExpanded;
  double? _beforeGroupScroll;
  _LayoutReadyDragRecognizer? _groupRecognizer;
  bool _recognizerTransferred = false;
  bool _proxyActive = false;
  bool _finishScheduled = false;
  int _dragGeneration = 0;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    if (!_recognizerTransferred) {
      _groupRecognizer?.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadReorderView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Download status updates may rebuild the parent; retain the drag snapshot.
    // Membership changes must cancel instead of committing stale indices.
    if (_pointer != null &&
        _dragItems != null &&
        (!listEquals(widget.groups, _dragGroups) ||
            widget.groups.any((group) => !listEquals((widget.items[group] ?? []).map(widget.itemKey).toList(),
                (_dragItems![group] ?? []).map(widget.itemKey).toList())))) {
      for (final key in _itemListKeys.values) {
        key.currentState?.cancelReorder();
      }
      _groupListKey.currentState?.cancelReorder();
      _clearDrag();
    }
  }

  void _snapshot() {
    _dragGroups = List.of(widget.groups);
    _dragItems = {for (final group in widget.groups) group: List.of(widget.items[group] ?? [])};
    _dragExpanded = Set.of(widget.expandedGroups);
  }

  void _trackItem(String group, PointerDownEvent event) {
    if (_pointer != null || _dragStarted || _finishScheduled) {
      return;
    }
    _pointer = event.pointer;
    _dragGeneration++;
    _pointerGroup = group;
    _pointerPosition = event.position;
    _dropInsideGroup = true;
  }

  bool _insideGroup(Offset position) {
    final RenderObject? render = _viewportKey.currentContext?.findRenderObject();
    final String? group = _pointerGroup;
    if (render is! RenderBox || group == null || !widget.controller.hasClients) {
      return false;
    }
    final Offset local = render.globalToLocal(position);
    final double y = local.dy + widget.controller.offset;
    final double start = _itemStarts[group] ?? double.infinity;
    final int count = (_dragItems ?? widget.items)[group]?.length ?? 0;
    return local.dx >= 0 && local.dx <= render.size.width && y >= start && y <= start + count * widget.itemExtent;
  }

  void _handlePointer(PointerEvent event) {
    if (event.pointer != _pointer) {
      return;
    }
    _pointerPosition = event.position;
    if (event is PointerUpEvent) {
      if (!_groupMode) {
        _dropInsideGroup = _insideGroup(event.position);
      }
      _pointer = null;
      if (!_dragStarted) {
        _finishAfterFrame();
      }
    } else if (event is PointerCancelEvent) {
      _pointer = null;
      _dropInsideGroup = false;
      _finishAfterFrame();
    }
  }

  void _prepareGroupDrag(String group, BuildContext tileContext, PointerDownEvent event) {
    if (_pointer != null || _dragStarted || _finishScheduled || event.buttons != kPrimaryButton) {
      return;
    }
    final int index = widget.groups.indexOf(group);
    if (index < 0) {
      return;
    }
    final RenderObject? viewport = _viewportKey.currentContext?.findRenderObject();
    final RenderObject? tile = tileContext.findRenderObject();
    final double top =
        viewport is RenderBox && tile is RenderBox ? tile.localToGlobal(Offset.zero, ancestor: viewport).dy : 0;
    _pointer = event.pointer;
    _dragGeneration++;
    _snapshot();
    _beforeGroupScroll = widget.controller.hasClients ? widget.controller.offset : null;
    final recognizer = _LayoutReadyDragRecognizer(debugOwner: this)
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
      ..addPointer(event);
    // Register now, before rebuilding: do not replay a synthetic down event.
    _groupRecognizer = recognizer;
    _recognizerTransferred = false;
    setState(() => _groupMode = true);
    if (widget.controller.hasClients) {
      final double maxOffset =
          math.max(0, widget.groups.length * _headerExtent - widget.controller.position.viewportDimension);
      widget.controller.jumpTo((index * _headerExtent - top).clamp(0.0, maxOffset));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pointer != event.pointer || !_groupMode) {
        if (!_recognizerTransferred) {
          recognizer.dispose();
        }
        return;
      }
      final list = _groupListKey.currentState;
      if (list == null) {
        _finishAfterFrame();
        return;
      }
      _recognizerTransferred = true;
      list.startItemDragReorder(index: index, event: event, recognizer: recognizer);
      recognizer.layoutReady();
    });
  }

  void _clearDrag() {
    _dragGeneration++;
    if (!_recognizerTransferred) {
      _groupRecognizer?.dispose();
    }
    _groupRecognizer = null;
    _recognizerTransferred = false;
    _groupMode = false;
    _dragStarted = false;
    _pointer = null;
    _pointerGroup = null;
    _pointerPosition = null;
    _dragGroups = null;
    _dragItems = null;
    _dragExpanded = null;
    _proxyActive = false;
    _dropInsideGroup = true;
  }

  void _finishAfterFrame([int? generation]) {
    final expectedGeneration = generation ?? _dragGeneration;
    if (_finishScheduled || expectedGeneration != _dragGeneration) {
      return;
    }
    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _finishScheduled = false;
      if (!mounted || expectedGeneration != _dragGeneration) {
        return;
      }
      final double? offset = _groupMode ? _beforeGroupScroll : null;
      setState(_clearDrag);
      restoreDownloadListScrollOffset(widget.controller, offset);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _proxy(Widget child, int index, Animation<double> animation) {
    _proxyActive = true;
    final generation = _dragGeneration;
    return _ReorderProxy(animation: animation, onFinished: () => _finishAfterFrame(generation), child: child);
  }

  void _dragEnd(int index) {
    // If released before the proxy's first build, its zero-length drop has no
    // proxy disposal callback. Flutter completes that drop synchronously.
    if (!_proxyActive) {
      _finishAfterFrame();
    }
  }

  Widget _header(BuildContext context, String group, int index) => DownloadReorderGroupTile(
        index: index,
        groupName: group,
        itemCount: (widget.items[group] ?? []).length,
        isOpen: !_groupMode && widget.expandedGroups.contains(group),
        onTap: () {
          if (!_dragStarted && !_groupMode) {
            widget.onToggleGroup(group);
          }
        },
        onHandlePointerEvent: (event) => _prepareGroupDrag(group, context, event),
      );

  @override
  Widget build(BuildContext context) {
    final groups = _dragGroups ?? widget.groups;
    final items = _dragItems ?? widget.items;
    final expanded = _dragExpanded ?? widget.expandedGroups;
    _itemStarts.clear();
    double offset = 0;
    for (final group in groups) {
      offset += _headerExtent;
      _itemStarts[group] = offset;
      if (!_groupMode && expanded.contains(group)) {
        offset += (items[group]?.length ?? 0) * widget.itemExtent;
      }
    }
    return CustomScrollView(
      key: _viewportKey,
      controller: widget.controller,
      slivers: _groupMode
          ? [
              SliverReorderableList(
                key: _groupListKey,
                itemExtent: _headerExtent,
                itemCount: groups.length,
                onReorderStart: (_) {
                  _dragStarted = true;
                },
                onReorderItem: (from, to) => widget.onReorderGroups(List.of(groups), from, to),
                onReorderEnd: _dragEnd,
                proxyDecorator: _proxy,
                itemBuilder: (context, index) => KeyedSubtree(
                    key: ValueKey('group_${groups[index]}'), child: _header(context, groups[index], index)),
              )
            ]
          : [
              for (int index = 0; index < groups.length; index++) ...[
                SliverToBoxAdapter(
                    key: ValueKey('header_${groups[index]}'),
                    child: Builder(builder: (context) => _header(context, groups[index], index))),
                if (expanded.contains(groups[index]) && (items[groups[index]]?.isNotEmpty ?? false))
                  SliverReorderableList(
                    key: _itemListKeys.putIfAbsent(groups[index], GlobalKey<SliverReorderableListState>.new),
                    itemExtent: widget.itemExtent,
                    itemCount: items[groups[index]]!.length,
                    proxyDecorator: _proxy,
                    onReorderStart: (_) {
                      setState(() {
                        _dragStarted = true;
                        _snapshot();
                      });
                    },
                    onReorderEnd: _dragEnd,
                    onReorderItem: (from, to) {
                      // Drop uses pointer-up coordinates with the latest scroll offset.
                      if (_dropInsideGroup && (_pointerPosition == null || _insideGroup(_pointerPosition!))) {
                        widget.onReorderItems(groups[index], List.of(items[groups[index]]!), from, to);
                      }
                    },
                    itemBuilder: (context, row) {
                      final item = items[groups[index]]![row];
                      return DownloadReorderItem(
                          key: widget.itemKey(item),
                          index: row,
                          enabled: !_dragStarted && !_finishScheduled,
                          child: Listener(
                              onPointerDown: (event) => _trackItem(groups[index], event),
                              child: widget.itemBuilder(context, item)));
                    },
                  ),
              ]
            ],
    );
  }
}

/// Participates in the real gesture arena immediately, but starts Flutter's
/// drag only once the replacement header sliver is laid out. Early up/cancel
/// disposes its state and cannot start a stale drag in the next frame.
class _LayoutReadyDragRecognizer extends MultiDragGestureRecognizer {
  _LayoutReadyDragRecognizer({required super.debugOwner});
  _LayoutReadyPointerState? _state;
  bool _registered = false;
  bool _disposed = false;
  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_registered || _disposed) {
      return;
    }
    _registered = true;
    super.addAllowedPointer(event);
  }

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _state = _LayoutReadyPointerState(event.position, event.kind, gestureSettings);
  void layoutReady() => _state?.layoutReady();
  @override
  String get debugDescription => 'layout-ready group reorder';
  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      super.dispose();
    }
  }
}

class _LayoutReadyPointerState extends MultiDragPointerState {
  _LayoutReadyPointerState(super.initialPosition, super.kind, super.gestureSettings);
  GestureMultiDragStartCallback? _starter;
  bool _ready = false;
  bool _disposed = false;
  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta != null && pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    _starter = starter;
    if (_ready && !_disposed) {
      starter(initialPosition);
    }
  }

  void layoutReady() {
    _ready = true;
    if (!_disposed) {
      _starter?.call(initialPosition);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _starter = null;
    super.dispose();
  }
}

class _ReorderProxy extends StatefulWidget {
  const _ReorderProxy({required this.animation, required this.onFinished, required this.child});
  final Animation<double> animation;
  final VoidCallback onFinished;
  final Widget child;
  @override
  State<_ReorderProxy> createState() => _ReorderProxyState();
}

class _ReorderProxyState extends State<_ReorderProxy> {
  @override
  void dispose() {
    // Flutter disposes its animation in its first status listener, so a second
    // status listener is not reliable. Proxy removal follows drop/cancel.
    widget.onFinished();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.animation,
      child: widget.child,
      builder: (_, child) => Material(elevation: 6 * Curves.easeInOut.transform(widget.animation.value), child: child));
}
