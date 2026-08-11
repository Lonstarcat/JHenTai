import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../config/ui_config.dart';

class DownloadReorderEntry<T> {
  const DownloadReorderEntry.group(this.groupName) : item = null;

  const DownloadReorderEntry.item(this.groupName, this.item);

  final String groupName;
  final T? item;

  bool get isGroup => item == null;
}

List<DownloadReorderEntry<T>> buildDownloadReorderEntries<T>({
  required Iterable<String> groups,
  required bool Function(String group) isGroupOpen,
  required Iterable<T> Function(String group) itemsForGroup,
}) {
  return [
    for (final String group in groups) ...[
      DownloadReorderEntry<T>.group(group),
      if (isGroupOpen(group))
        for (final T item in itemsForGroup(group))
          DownloadReorderEntry<T>.item(group, item),
    ],
  ];
}

List<DownloadReorderEntry<T>> reorderDownloadEntries<T>(
  List<DownloadReorderEntry<T>> entries,
  int oldIndex,
  int newIndex,
) {
  final List<DownloadReorderEntry<T>> reordered = List.of(entries);
  reordered.insert(newIndex, reordered.removeAt(oldIndex));
  return reordered;
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

class _PlatformReorderHandle extends StatelessWidget {
  const _PlatformReorderHandle({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      return _DownloadReorderDragStartListener(
        index: index,
        delay: DownloadReorderItem.dragDelay,
        child: child,
      );
    }
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
                _PlatformReorderHandle(
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

  static const Duration dragDelay = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    return _DownloadReorderDragStartListener(
      index: index,
      delay: dragDelay,
      child: MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: child,
      ),
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
