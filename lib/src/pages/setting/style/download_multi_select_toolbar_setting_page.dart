import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../model/download_multi_select_toolbar.dart';
import '../../../service/log.dart';
import '../../../setting/style_setting.dart';
import '../../../utils/notifier_util.dart';
import '../../../widget/download_multi_select_toolbar.dart';
import '../../../widget/notification_overlay.dart';

class DownloadMultiSelectToolbarSettingPage extends StatefulWidget {
  final StyleSetting? settings;

  const DownloadMultiSelectToolbarSettingPage({super.key, this.settings});

  @override
  State<DownloadMultiSelectToolbarSettingPage> createState() =>
      _DownloadMultiSelectToolbarSettingPageState();
}

class _DownloadMultiSelectToolbarSettingPageState
    extends State<DownloadMultiSelectToolbarSettingPage> {
  DownloadToolbarKind _kind = DownloadToolbarKind.gallery;
  StyleSetting get settings => widget.settings ?? styleSetting;

  void _reset() {
    final kind = _kind;
    _save((_) => DownloadToolbarConfig.defaults(kind));
  }

  Future<void> _save(
      DownloadToolbarConfig Function(DownloadToolbarConfig) edit) async {
    try {
      // Capture scope before awaiting: changing tabs must never redirect a save.
      await settings.updateToolbar(_kind, edit);
    } catch (error, stack) {
      log.error('Save download multi-select toolbar failed', error, stack);
      showNotifier('saveFailed'.tr, NotificationLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            centerTitle: true,
            title: Text('downloadMultiSelectToolbar'.tr),
            actions: [
              Obx(() => IconButton(
                    tooltip: 'toolbarResetCurrent'.tr,
                    icon: const Icon(Icons.restore),
                    onPressed: settings.savingToolbar.value ? null : _reset,
                  )),
            ],
            bottom: TabBar(
              onTap: (index) =>
                  setState(() => _kind = DownloadToolbarKind.values[index]),
              tabs: [Tab(text: 'download'.tr), Tab(text: 'archive'.tr)],
            ),
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('downloadMultiSelectToolbarHint'.tr),
            ),
            Expanded(
              child: Obx(() {
                final config = settings.toolbarConfig(_kind).value;
                final saving = settings.savingToolbar.value;
                return ReorderableListView.builder(
                  key: ValueKey(_kind),
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: config.order.length,
                  onReorderItem: (oldIndex, newIndex) {
                    if (!saving) {
                      _save((current) => current.reorder(oldIndex, newIndex));
                    }
                  },
                  itemBuilder: (context, index) {
                    final action = config.order[index];
                    return ListTile(
                      key: ValueKey(action.name),
                      leading: Icon(downloadToolbarIcon(action)),
                      title: Text(action.labelKey.tr),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Switch(
                          key: ValueKey('toggle-${action.name}'),
                          value: config.enabled.contains(action),
                          onChanged: saving
                              ? null
                              : (value) => _save(
                                  (current) => current.toggle(action, value)),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          enabled: !saving,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(Icons.drag_handle,
                                semanticLabel: 'toolbarDragToReorder'.tr),
                          ),
                        ),
                      ]),
                    );
                  },
                );
              }),
            ),
          ]),
          bottomNavigationBar: NotificationBottomBar(
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('toolbarPreviewHint'.tr, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: Obx(() => DownloadMultiSelectToolbar(
                            key: ValueKey('preview-${_kind.name}'),
                            config: settings.toolbarConfig(_kind).value,
                            preview: true,
                          )),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
