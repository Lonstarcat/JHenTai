import 'package:get/get.dart';

import '../model/background_task_info.dart';
import '../service/background_task_service.dart';
import '../service/log.dart';
import '../setting/favorite_setting.dart';
import '../setting/user_setting.dart';
import '../widget/eh_favorite_dialog.dart';
import 'toast_util.dart';

Future<bool> chooseAndStartBatchFavorite(
    List<BackgroundFavoriteItem> items) async {
  if (items.isEmpty) {
    return false;
  }
  if (!userSetting.hasLoggedIn()) {
    toast('needLoginToOperate'.tr);
    return false;
  }
  if (backgroundTaskService.isFavoriteTaskActive) {
    toast('batchFavoriteAlreadyRunning'.tr);
    return false;
  }

  try {
    if (!favoriteSetting.inited) {
      await favoriteSetting.fetchDataFromEH();
    }
  } catch (e, stack) {
    log.error('Load favorite folders for batch favorite failed', e, stack);
  }
  if (!favoriteSetting.inited) {
    toast('favoriteFolderLoadFailed'.tr, isShort: false);
    return false;
  }

  final ({bool isDelete, int favIndex, String note, bool remember})? operation =
      await Get.dialog(const EHFavoriteDialog());
  if (operation == null) {
    return false;
  }
  if (operation.remember) {
    await userSetting.saveDefaultFavoriteIndex(operation.favIndex);
  }

  final bool started = backgroundTaskService.startBatchFavorite(
    items: items,
    favoriteTagIndex: operation.favIndex,
    favoriteTagName: favoriteSetting.favoriteTagNames[operation.favIndex],
    note: operation.note,
  );
  if (!started) {
    toast('batchFavoriteAlreadyRunning'.tr);
    return false;
  }
  toast('batchFavoriteStartedInBackground'.tr, isShort: false);
  return true;
}
