import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../model/download_multi_select_toolbar.dart';

IconData downloadToolbarIcon(DownloadToolbarAction action) => switch (action) {
      DownloadToolbarAction.selectAll => Icons.done_all,
      DownloadToolbarAction.resume => Icons.play_arrow,
      DownloadToolbarAction.pause => Icons.pause,
      DownloadToolbarAction.batchUpdate => Icons.update,
      DownloadToolbarAction.favorite => Icons.favorite_outline,
      DownloadToolbarAction.changeGroup => Icons.bookmark,
      DownloadToolbarAction.delete => Icons.delete,
      DownloadToolbarAction.changeParseSource => Icons.smart_toy_outlined,
    };

/// Same layout for production and preview; preview only has harmless callbacks,
/// rather than absorbing scrolling gestures or executing business actions.
class DownloadMultiSelectToolbar extends StatelessWidget {
  final DownloadToolbarConfig config;
  final bool hasSelection;
  final bool preview;
  final Map<DownloadToolbarAction, VoidCallback> callbacks;
  final VoidCallback? onClose;

  const DownloadMultiSelectToolbar({
    super.key,
    required this.config,
    this.hasSelection = true,
    this.preview = false,
    this.callbacks = const {},
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final action in config.visible)
                IconButton(
                  key: ValueKey('toolbar-${action.name}'),
                  tooltip: action.labelKey.tr,
                  icon: Icon(downloadToolbarIcon(action)),
                  onPressed: preview
                      ? () {}
                      : action.requiresSelection && !hasSelection
                          ? null
                          : callbacks[action],
                ),
            ]),
          ),
        ),
        IconButton(
          key: const ValueKey('toolbar-close'),
          tooltip: 'toolbarExitSelection'.tr,
          icon: const Icon(Icons.close),
          onPressed: preview ? () {} : onClose,
        ),
      ]);
}
