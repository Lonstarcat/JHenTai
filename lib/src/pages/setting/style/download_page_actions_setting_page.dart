import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../model/download_page_actions.dart';
import '../../../pages/download/widget/download_page_more_menu.dart';
import '../../../service/log.dart';
import '../../../setting/style_setting.dart';
import '../../../utils/notifier_util.dart';
import 'widget/download_page_actions_preview.dart';

class DownloadPageActionsSettingPage extends StatelessWidget {
  final StyleSetting? settings;
  const DownloadPageActionsSettingPage({super.key, this.settings});

  StyleSetting get _settings => settings ?? styleSetting;

  Future<void> _save(
      DownloadPageActionsConfig Function(DownloadPageActionsConfig)
          edit) async {
    try {
      await _settings.updateDownloadPageActions(edit);
    } catch (error, stack) {
      log.error('Save download page actions failed', error, stack);
      showNotifier('saveFailed'.tr, NotificationLevel.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            centerTitle: true,
            title: Text('downloadPageActions'.tr),
            actions: [
              Obx(() => IconButton(
                  icon: const Icon(Icons.restore),
                  tooltip: 'toolbarResetCurrent'.tr,
                  onPressed: _settings.savingDownloadPageActions.value
                      ? null
                      : () =>
                          _save((_) => DownloadPageActionsConfig.defaults()))),
            ]),
        body: Obx(() {
          final config = _settings.downloadPageActions.value;
          final saving = _settings.savingDownloadPageActions.value;
          return LayoutBuilder(
              builder: (context, pageConstraints) => Column(children: [
                    // Long translations at large text scales must not push controls
                    // off-screen; keep the complete hint readable by scrolling it.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: pageConstraints.maxHeight * 0.3),
                      child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('downloadPageActionsHint'.tr)),
                      ),
                    ),
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final labels = [
                            'downloadPageNoExternalAction'.tr,
                            for (final action in config.order)
                              action.labelKey.tr,
                          ];
                          final style =
                              Theme.of(context).textTheme.titleMedium!;
                          final painter = TextPainter(
                            textDirection: Directionality.of(context),
                            textScaler: MediaQuery.textScalerOf(context),
                            maxLines: 1,
                          );
                          double textWidth = 0;
                          for (final label in labels) {
                            painter.text = TextSpan(text: label, style: style);
                            painter.layout();
                            textWidth = math.max(textWidth, painter.width);
                          }
                          painter.dispose();
                          // Reserve two standard 48px touch targets at the right edge.
                          final width = math.min(textWidth + 56,
                              math.max(0.0, constraints.maxWidth - 108));
                          return Row(children: [
                            SizedBox(
                                key: const ValueKey(
                                    'download-page-external-selector'),
                                width: width,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey(
                                      'outside-${config.externalAction?.name}'),
                                  initialValue:
                                      config.externalAction?.name ?? 'none',
                                  style: style,
                                  isExpanded: true,
                                  selectedItemBuilder: (_) => [
                                    for (final label in labels)
                                      Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                  ],
                                  decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                      labelText:
                                          'downloadPageExternalAction'.tr),
                                  items: [
                                    DropdownMenuItem(
                                        value: 'none',
                                        alignment: Alignment.center,
                                        child: Text(labels.first,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center)),
                                    for (final action in config.order)
                                      DropdownMenuItem(
                                          value: action.name,
                                          alignment: Alignment.center,
                                          child: Text(action.labelKey.tr,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center)),
                                  ],
                                  onChanged: saving
                                      ? null
                                      : (id) => _save((current) =>
                                          current.withExternal(id == 'none'
                                              ? null
                                              : DownloadPageAction.values
                                                  .firstWhere((action) =>
                                                      action.name == id))),
                                )),
                            const Spacer(),
                            SizedBox(
                              key: const ValueKey(
                                  'download-page-actions-preview'),
                              width: 96,
                              child: Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child:
                                    DownloadPageActionsPreview(config: config),
                              ),
                            ),
                          ]);
                        })),
                    const SizedBox(height: 8),
                    Expanded(
                        child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: config.order.length,
                      onReorderItem: (oldIndex, newIndex) {
                        if (!saving) {
                          _save(
                              (current) => current.reorder(oldIndex, newIndex));
                        }
                      },
                      itemBuilder: (context, index) {
                        final action = config.order[index];
                        return ListTile(
                          key: ValueKey(action.name),
                          leading: Icon(downloadPageActionIcon(action)),
                          title: Text(action.labelKey.tr),
                          subtitle: action == config.externalAction
                              ? Text('downloadPageExternalAction'.tr)
                              : null,
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            Switch(
                                key: ValueKey(
                                    'page-action-toggle-${action.name}'),
                                value: config.enabled.contains(action),
                                onChanged: saving
                                    ? null
                                    : (value) => _save((current) =>
                                        current.toggle(action, value))),
                            ReorderableDragStartListener(
                                index: index,
                                enabled: !saving,
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Icon(Icons.drag_handle,
                                        semanticLabel:
                                            'toolbarDragToReorder'.tr))),
                          ]),
                        );
                      },
                    )),
                  ]));
        }),
      );
}
