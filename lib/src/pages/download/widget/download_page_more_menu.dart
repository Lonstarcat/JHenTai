import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum _DownloadPageMenuAction {
  switchView,
  multiSelect,
  resumeAll,
  pauseAll,
  search,
}

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
  });

  final IconData switchViewIcon;
  final String switchViewLabel;
  final VoidCallback onSwitchView;
  final VoidCallback onMultiSelect;
  final VoidCallback onResumeAll;
  final VoidCallback onPauseAll;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_DownloadPageMenuAction>(
      itemBuilder: (context) => [
        _item(
          action: _DownloadPageMenuAction.switchView,
          icon: switchViewIcon,
          label: switchViewLabel,
        ),
        _item(
          action: _DownloadPageMenuAction.multiSelect,
          icon: Icons.done_all,
          label: 'multiSelect'.tr,
        ),
        _item(
          action: _DownloadPageMenuAction.resumeAll,
          icon: Icons.play_arrow,
          label: 'resumeAllTasks'.tr,
        ),
        _item(
          action: _DownloadPageMenuAction.pauseAll,
          icon: Icons.pause,
          label: 'pauseAllTasks'.tr,
        ),
        _item(
          action: _DownloadPageMenuAction.search,
          icon: Icons.search,
          label: 'search'.tr,
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _DownloadPageMenuAction.switchView:
            onSwitchView();
            break;
          case _DownloadPageMenuAction.multiSelect:
            onMultiSelect();
            break;
          case _DownloadPageMenuAction.resumeAll:
            onResumeAll();
            break;
          case _DownloadPageMenuAction.pauseAll:
            onPauseAll();
            break;
          case _DownloadPageMenuAction.search:
            onSearch();
            break;
        }
      },
    );
  }

  PopupMenuItem<_DownloadPageMenuAction> _item({
    required _DownloadPageMenuAction action,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<_DownloadPageMenuAction>(
      value: action,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
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
