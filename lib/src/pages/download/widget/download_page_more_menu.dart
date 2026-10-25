import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../model/download_page_actions.dart';
import '../../../setting/style_setting.dart';

IconData downloadPageActionIcon(DownloadPageAction action) => switch (action) {
      DownloadPageAction.switchView => Icons.grid_view,
      DownloadPageAction.multiSelect => Icons.done_all,
      DownloadPageAction.resumeAll => Icons.play_arrow,
      DownloadPageAction.pauseAll => Icons.pause,
      DownloadPageAction.search => Icons.search,
      DownloadPageAction.reorder => Icons.sort,
      DownloadPageAction.batchUpdateTask => Icons.update,
    };

class DownloadPageMoreMenu extends StatelessWidget {
  const DownloadPageMoreMenu({
    super.key,
    required this.switchViewIcon,
    required this.switchViewLabel,
    required this.onSwitchView,
    required this.onMultiSelect,
    required this.onResumeAll,
    required this.onPauseAll,
    required this.onSearch,
    this.hasBatchUpdateTask,
    this.onBatchUpdateTask,
    this.batchUpdateTaskChanges,
    this.inReorderMode = false,
    this.onToggleReorder,
    this.settings,
  });

  final IconData switchViewIcon;
  final String switchViewLabel;
  final VoidCallback onSwitchView;
  final VoidCallback onMultiSelect;
  final VoidCallback onResumeAll;
  final VoidCallback onPauseAll;
  final VoidCallback onSearch;
  final bool Function()? hasBatchUpdateTask;
  final VoidCallback? onBatchUpdateTask;
  final Listenable? batchUpdateTaskChanges;
  final bool inReorderMode;
  final VoidCallback? onToggleReorder;
  final StyleSetting? settings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: batchUpdateTaskChanges ?? const AlwaysStoppedAnimation(0),
        builder: (context, _) => Obx(() {
          final config = (settings ?? styleSetting).downloadPageActions.value;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (inReorderMode)
              DownloadReorderModeButton(
                  inReorderMode: true, onPressed: onToggleReorder ?? () {})
            else if (config.showExternal)
              IconButton(
                key: const ValueKey('download-page-external-action'),
                tooltip: _label(config.externalAction!),
                icon: Icon(_icon(config.externalAction!)),
                onPressed: _enabled(config.externalAction!)
                    ? () => _select(config.externalAction!)
                    : null,
              ),
            _buildMenu(context, config),
          ]);
        }),
      );

  bool _enabled(DownloadPageAction action) => switch (action) {
        DownloadPageAction.batchUpdateTask =>
          onBatchUpdateTask != null && hasBatchUpdateTask?.call() == true,
        DownloadPageAction.reorder => onToggleReorder != null,
        _ => true,
      };
  String _label(DownloadPageAction action) =>
      action == DownloadPageAction.switchView
          ? switchViewLabel
          : action.labelKey.tr;
  IconData _icon(DownloadPageAction action) =>
      action == DownloadPageAction.switchView
          ? switchViewIcon
          : downloadPageActionIcon(action);
  void _select(DownloadPageAction action) {
    switch (action) {
      case DownloadPageAction.batchUpdateTask:
        onBatchUpdateTask?.call();
      case DownloadPageAction.reorder:
        onToggleReorder?.call();
      case DownloadPageAction.switchView:
        onSwitchView();
      case DownloadPageAction.multiSelect:
        onMultiSelect();
      case DownloadPageAction.resumeAll:
        onResumeAll();
      case DownloadPageAction.pauseAll:
        onPauseAll();
      case DownloadPageAction.search:
        onSearch();
    }
  }

  Widget _buildMenu(BuildContext context, DownloadPageActionsConfig config) {
    return PopupMenuButton<DownloadPageAction>(
      enabled: config.menuActions.isNotEmpty,
      // Optional background tasks must not change the existing menu width.
      constraints: BoxConstraints.tightFor(
          width: downloadPageMenuWidth(context, switchViewLabel)),
      itemBuilder: (context) => [
        for (final action in config.menuActions)
          if (action == DownloadPageAction.batchUpdateTask)
            _UpdateTaskMenuEntry(
              changes: batchUpdateTaskChanges,
              builder: () => downloadPageMenuItem(
                action: DownloadPageAction.batchUpdateTask,
                icon: Icons.update,
                label: 'batchUpdateTask'.tr,
                enabled: onBatchUpdateTask != null &&
                    hasBatchUpdateTask?.call() == true,
              ),
            )
          else
            downloadPageMenuItem(
                action: action,
                icon: _icon(action),
                label: _label(action),
                enabled: _enabled(action)),
      ],
      onSelected: _select,
    );
  }
}

// Shared presentation only. Settings previews must not use the live dispatcher.
double downloadPageMenuWidth(BuildContext context, String switchViewLabel) {
  final theme = Theme.of(context);
  final popupTheme = PopupMenuTheme.of(context);
  final style = theme.useMaterial3
      ? popupTheme.labelTextStyle?.resolve({}) ?? theme.textTheme.labelLarge!
      : popupTheme.textStyle ?? theme.textTheme.titleMedium!;
  double textWidth = 0;
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  for (final label in [
    switchViewLabel,
    'multiSelect'.tr,
    'resumeAllTasks'.tr,
    'pauseAllTasks'.tr,
    'search'.tr,
    'downloadPageReorder'.tr,
  ]) {
    painter.text = TextSpan(text: label, style: style);
    painter.layout();
    if (painter.width > textWidth) {
      textWidth = painter.width;
    }
  }
  painter.dispose();
  // Match Material's 56px intrinsic width steps and default item padding.
  final padding = theme.useMaterial3 ? 24 : 32;
  final iconWidth = IconTheme.of(context).size ?? 24;
  return (((textWidth + iconWidth + 12 + padding) / 56).ceil() * 56.0)
      .clamp(112.0, 280.0);
}

PopupMenuItem<DownloadPageAction> downloadPageMenuItem({
  required DownloadPageAction action,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  return PopupMenuItem<DownloadPageAction>(
    value: action,
    enabled: enabled,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// A retained popup route needs its own listener while the page remains intact.
class _UpdateTaskMenuEntry extends PopupMenuEntry<DownloadPageAction> {
  const _UpdateTaskMenuEntry({required this.changes, required this.builder});

  final Listenable? changes;
  final PopupMenuItem<DownloadPageAction> Function() builder;

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(DownloadPageAction? value) =>
      value == DownloadPageAction.batchUpdateTask;

  @override
  State<_UpdateTaskMenuEntry> createState() => _UpdateTaskMenuEntryState();
}

class _UpdateTaskMenuEntryState extends State<_UpdateTaskMenuEntry> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.changes ?? const AlwaysStoppedAnimation(0),
        builder: (_, __) => widget.builder(),
      );
}

class DownloadReorderModeButton extends StatelessWidget {
  const DownloadReorderModeButton({
    super.key,
    required this.inReorderMode,
    required this.onPressed,
  });

  final bool inReorderMode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(inReorderMode ? Icons.close : Icons.sort),
      onPressed: onPressed,
      tooltip: (inReorderMode ? 'exitReorderMode' : 'enterReorderMode').tr,
    );
  }
}

class LocalDownloadPageActions extends StatelessWidget {
  const LocalDownloadPageActions({
    super.key,
    required this.switchViewIcon,
    required this.switchViewLabel,
    required this.onRefresh,
    required this.onSwitchView,
  });

  final IconData switchViewIcon;
  final String switchViewLabel;
  final VoidCallback onRefresh;
  final VoidCallback onSwitchView;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'refresh'.tr,
          onPressed: onRefresh,
        ),
        IconButton(
          icon: Icon(switchViewIcon),
          tooltip: switchViewLabel,
          onPressed: onSwitchView,
        ),
      ],
    );
  }
}
