import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../config/ui_config.dart';

List<T> reorderDownloadList<T>(
  List<T> entries,
  int oldIndex,
  int newIndex,
) {
  final List<T> reordered = List.of(entries);
  reordered.insert(newIndex, reordered.removeAt(oldIndex));
  return reordered;
}

class DownloadReorderExpansionSession {
  Set<String>? _expandedGroupsBeforeReorder;

  void start(Set<String> expandedGroups) {
    _expandedGroupsBeforeReorder ??= Set.of(expandedGroups);
  }

  void collapseAll(Set<String> expandedGroups) {
    if (_expandedGroupsBeforeReorder != null) {
      expandedGroups.clear();
    }
  }

  void restore(Set<String> expandedGroups) {
    final Set<String>? originalGroups = _expandedGroupsBeforeReorder;
    if (originalGroups == null) {
      return;
    }
    expandedGroups
      ..clear()
      ..addAll(originalGroups);
    _expandedGroupsBeforeReorder = null;
  }
}

int compareDownloadManualOrder({
  required int firstOrder,
  required int secondOrder,
  required int fallbackComparison,
}) {
  final int orderComparison = firstOrder.compareTo(secondOrder);
  return orderComparison != 0 ? orderComparison : fallbackComparison;
}

void restoreDownloadListScrollOffset(
  ScrollController controller,
  double? offset,
) {
  if (offset == null) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!controller.hasClients) {
      return;
    }
    final ScrollPosition position = controller.position;
    controller.jumpTo(offset.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    ));
  });
}

class _GroupReorderHandle extends StatelessWidget {
  const _GroupReorderHandle({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(index: index, child: child);
  }
}

class DownloadReorderHint extends StatelessWidget {
  const DownloadReorderHint({super.key});

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 20, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'sortGroupsHint'.tr,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadReorderGroupTile extends StatelessWidget {
  const DownloadReorderGroupTile({
    super.key,
    required this.index,
    required this.groupName,
    required this.itemCount,
    required this.isOpen,
    required this.onTap,
  });

  final int index;
  final String groupName;
  final int itemCount;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: UIConfig.groupListColor(context),
        elevation: Get.isDarkMode ? 0 : 1,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: UIConfig.groupListHeight,
            child: Row(
              children: [
                SizedBox(
                  width: UIConfig.downloadPageGroupHeaderWidth,
                  child: Center(
                    child: Icon(
                      isOpen ? Icons.folder_open : Icons.folder_outlined,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    groupName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'downloadItemCount'.trParams({'count': itemCount.toString()}),
                  maxLines: 1,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                _GroupReorderHandle(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: 'drag2sort'.tr,
                      child: SizedBox(
                        width: 48,
                        height: UIConfig.groupListHeight,
                        child: Icon(Icons.drag_indicator,
                            color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DownloadReorderGroupSection<T> extends StatelessWidget {
  const DownloadReorderGroupSection({
    super.key,
    required this.groupIndex,
    required this.groupName,
    required this.isOpen,
    required this.items,
    required this.itemKey,
    required this.onToggle,
    required this.onReorderItems,
    required this.itemBuilder,
  });

  final int groupIndex;
  final String groupName;
  final bool isOpen;
  final List<T> items;
  final Key Function(T item) itemKey;
  final VoidCallback onToggle;
  final void Function(int oldIndex, int newIndex) onReorderItems;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DownloadReorderGroupTile(
          index: groupIndex,
          groupName: groupName,
          itemCount: items.length,
          isOpen: isOpen,
          onTap: onToggle,
        ),
        if (isOpen && items.isNotEmpty)
          DownloadReorderItemList<T>(
            items: items,
            itemKey: itemKey,
            onReorderItems: onReorderItems,
            itemBuilder: itemBuilder,
          ),
      ],
    );
  }
}

class DownloadReorderItemList<T> extends StatefulWidget {
  const DownloadReorderItemList({
    super.key,
    required this.items,
    required this.itemKey,
    required this.onReorderItems,
    required this.itemBuilder,
  });

  final List<T> items;
  final Key Function(T item) itemKey;
  final void Function(int oldIndex, int newIndex) onReorderItems;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<DownloadReorderItemList<T>> createState() =>
      _DownloadReorderItemListState<T>();
}

class _DownloadReorderItemListState<T>
    extends State<DownloadReorderItemList<T>> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _pointerOutsideGroup = false;

  void _handlePointerMove(PointerMoveEvent event) {
    final BuildContext? boundaryContext = _boundaryKey.currentContext;
    final RenderBox? renderBox =
        boundaryContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return;
    }
    final Rect groupBounds =
        renderBox.localToGlobal(Offset.zero) & renderBox.size;
    _pointerOutsideGroup = !groupBounds.contains(event.position);
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (!_pointerOutsideGroup) {
      widget.onReorderItems(oldIndex, newIndex);
    }
  }

  void _resetPointerBoundaryAfterDrag(int _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pointerOutsideGroup = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _pointerOutsideGroup = false,
      onPointerMove: _handlePointerMove,
      child: KeyedSubtree(
        key: _boundaryKey,
        child: ReorderableListView.builder(
          shrinkWrap: true,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          itemCount: widget.items.length,
          onReorderItem: _handleReorder,
          onReorderEnd: _resetPointerBoundaryAfterDrag,
          itemBuilder: (context, index) {
            final T item = widget.items[index];
            return DownloadReorderItem(
              key: widget.itemKey(item),
              index: index,
              child: widget.itemBuilder(context, item),
            );
          },
        ),
      ),
    );
  }
}

class DownloadReorderBackTile extends StatelessWidget {
  const DownloadReorderBackTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Material(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.arrow_back,
                    size: 20, color: colorScheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'backToGroups'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(Icons.folder_outlined,
                    size: 20, color: colorScheme.onSecondaryContainer),
                const SizedBox(width: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DownloadReorderItem extends StatelessWidget {
  const DownloadReorderItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  static const Duration dragDelay = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    final Widget draggableChild = MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: child,
    );

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _DownloadReorderDragStartListener(
        index: index,
        delay: dragDelay,
        child: draggableChild,
      );
    }

    return ReorderableDragStartListener(
      index: index,
      child: draggableChild,
    );
  }
}

class _DownloadReorderDragStartListener extends ReorderableDragStartListener {
  const _DownloadReorderDragStartListener({
    required super.index,
    required super.child,
    required this.delay,
  });

  final Duration delay;

  @override
  MultiDragGestureRecognizer createRecognizer() {
    return DelayedMultiDragGestureRecognizer(
      delay: delay,
      debugOwner: this,
    );
  }
}
