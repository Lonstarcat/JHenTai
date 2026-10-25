import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../model/download_page_actions.dart';
import '../../../download/widget/download_page_more_menu.dart';

/// A read-only preview: no services, persistence or business callbacks.
class DownloadPageActionsPreview extends StatelessWidget {
  const DownloadPageActionsPreview({super.key, required this.config});

  final DownloadPageActionsConfig config;

  @override
  Widget build(BuildContext context) {
    final switchLabel = 'switch2GridMode'.tr;
    return Semantics(
      label: 'preview'.tr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (config.showExternal)
            IconButton(
              key: const ValueKey('download-page-preview-external'),
              tooltip:
                  '${'preview'.tr} · ${config.externalAction!.labelKey.tr}',
              icon: Icon(downloadPageActionIcon(config.externalAction!)),
              onPressed:
                  config.externalAction == DownloadPageAction.batchUpdateTask
                      ? null
                      : () {},
            ),
          PopupMenuButton<DownloadPageAction>(
            key: const ValueKey('download-page-preview-menu'),
            tooltip: '${'preview'.tr} · ${'downloadPageActions'.tr}',
            enabled: config.menuActions.isNotEmpty,
            constraints: BoxConstraints.tightFor(
                width: downloadPageMenuWidth(context, switchLabel)),
            itemBuilder: (_) => [
              for (final action in config.menuActions)
                downloadPageMenuItem(
                  action: action,
                  icon: downloadPageActionIcon(action),
                  label: action == DownloadPageAction.switchView
                      ? switchLabel
                      : action.labelKey.tr,
                  enabled: action != DownloadPageAction.batchUpdateTask,
                ),
            ],
            // No onSelected: choosing an item only dismisses the popup.
          ),
        ],
      ),
    );
  }
}
