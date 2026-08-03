import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../config/ui_config.dart';

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
    required this.onTap,
  });

  final int index;
  final String groupName;
  final int itemCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: UIConfig.groupListColor(context),
        elevation: Get.isDarkMode ? 0 : 1,
        borderRadius: BorderRadius.circular(15),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.folder_outlined,
                      color: colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'downloadItemCount'
                            .trParams({'count': itemCount.toString()}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: colorScheme.onSurfaceVariant),
                ReorderableDragStartListener(
                  index: index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Tooltip(
                      message: 'drag2sort'.tr,
                      child: SizedBox(
                        width: 48,
                        height: 68,
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

class DownloadReorderItemHandle extends StatelessWidget {
  const DownloadReorderItemHandle({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ReorderableDragStartListener(
        index: index,
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Tooltip(
            message: 'drag2sort'.tr,
            child: Container(
              width: 36,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.drag_indicator,
                  color: colorScheme.onSecondaryContainer),
            ),
          ),
        ),
      ),
    );
  }
}
