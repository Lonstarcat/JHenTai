import 'dart:async';
import 'package:get/get.dart';
import '../model/download_batch_update.dart';
import '../model/download_multi_select_toolbar.dart';
import '../service/download_batch_update_backend.dart';
import '../service/download_batch_update_service.dart';
import '../setting/user_setting.dart';
import '../widget/download_batch_update_dialog.dart';
import '../widget/eh_alert_dialog.dart';
import 'notifier_util.dart';

class BatchUpdateFlow {
  bool _dialogOpen = false;
  final DownloadBatchUpdateService service;

  BatchUpdateFlow({DownloadBatchUpdateService? service})
      : service = service ?? downloadBatchUpdateService;

  bool hasSessionFor(DownloadToolbarKind kind) => service.hasSessionFor(kind);

  /// Viewing a retained session never starts checks, purchases or new tasks.
  Future<void> openExisting(DownloadToolbarKind kind) async {
    if (!hasSessionFor(kind)) {
      return;
    }
    await _showCurrentSession();
  }

  Future<void> open(
      List<BatchUpdateSource> sources, DownloadToolbarKind kind) async {
    if (_dialogOpen) {
      return;
    }
    if (!service.active) {
      if (!userSetting.hasLoggedIn()) {
        showNotifier('needLoginToOperate'.tr, NotificationLevel.warning);
        return;
      }
      _dialogOpen = true;
      try {
        final confirm = await Get.dialog<bool>(EHDialog(
            title: 'batchUpdate'.tr, content: 'batchUpdateConfirm'.tr));
        if (confirm != true) {
          return;
        }
        if (!service.active) {
          unawaited(service.check(sources).then((_) {
            if (!_dialogOpen && service.phase == BatchUpdatePhase.review) {
              showNotifier('batchUpdateReady'.tr, NotificationLevel.info);
            }
          }));
        }
      } finally {
        _dialogOpen = false;
      }
    }
    await _showCurrentSession();
  }

  Future<void> _showCurrentSession() async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    try {
      await Get.dialog<void>(
          DownloadBatchUpdateDialog(
              service: service,
              onSubmit: () {
                unawaited(service.submit().then((_) {
                  showNotifier(
                      batchUpdateSummary(service),
                      service.count(BatchUpdateItemStatus.failed) > 0 ||
                              service.stoppedCount > 0
                          ? NotificationLevel.warning
                          : NotificationLevel.success);
                }, onError: (Object error, StackTrace stack) {
                  showNotifier(
                      'batchUpdateSubmitFailed'.tr, NotificationLevel.error);
                }));
              }),
          barrierDismissible: false);
    } finally {
      _dialogOpen = false;
    }
  }
}

final batchUpdateFlow = BatchUpdateFlow();
