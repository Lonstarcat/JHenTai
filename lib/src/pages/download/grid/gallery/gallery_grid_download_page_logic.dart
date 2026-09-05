import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/mixin/scroll_to_top_logic_mixin.dart';
import 'package:jhentai/src/mixin/scroll_to_top_state_mixin.dart';
import 'package:jhentai/src/mixin/update_global_gallery_status_logic_mixin.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/pages/details/details_page_logic.dart';
import 'package:jhentai/src/pages/download/mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import 'package:jhentai/src/setting/style_setting.dart';

import '../../../../routes/routes.dart';
import '../../../../service/gallery_download/gallery_download_service.dart';
import '../../../../utils/route_util.dart';
import '../../../../utils/download_task_locator_util.dart';
import '../../../../utils/toast_util.dart';
import '../../../../widget/eh_alert_dialog.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_state_mixin.dart';
import '../../download_reorder_mode.dart';
import '../../mixin/gallery/gallery_download_page_logic_mixin.dart';
import '../mixin/grid_download_page_logic_mixin.dart';
import '../mixin/grid_download_page_service_mixin.dart';
import '../mixin/grid_download_page_state_mixin.dart';
import 'gallery_grid_download_page_state.dart';

class GalleryGridDownloadPageLogic extends GetxController
    with
        Scroll2TopLogicMixin,
        MultiSelectDownloadPageLogicMixin<GalleryDownloadInfo>,
        GalleryDownloadPageLogicMixin,
        GridBasePageLogic,
        UpdateGlobalGalleryStatusLogicMixin {
  GalleryGridDownloadPageState state = GalleryGridDownloadPageState();

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  @override
  GridBasePageState get gridBasePageState => state;

  @override
  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState => state;

  @override
  GridBasePageServiceMixin get galleryService => downloadService;

  void handleTapTitle(GalleryDownloadInfo gallery) {
    if (multiSelectDownloadPageState.inMultiSelectMode) {
      toggleSelectItem(gallery.gid);
    } else {
      goToDetailPage(gallery);
    }
  }

  @override
  void handleRemoveItem(GalleryDownloadInfo gallery, bool deleteImages,
      BuildContext context) async {
    bool confirmed = await confirmDestructiveAction(
        title: deleteImages
            ? 'deleteTaskAndImages'.tr + '?'
            : 'deleteTask'.tr + '?');
    if (!confirmed) {
      return;
    }

    bool isUpdatingDependent = downloadService.isUpdatingDependent(gallery.gid);

    if (isUpdatingDependent) {
      bool? result = await showDialog(
        context: context,
        builder: (_) => EHDialog(
          title: 'delete'.tr + '?',
          content: 'deleteUpdatingDependentHint'.tr,
        ),
      );
      if (result == null || !result) {
        return;
      }
    }

    downloadService
        .deleteGallery(gallery, deleteImages: deleteImages)
        .then((_) => super.handleRemoveItem(gallery, deleteImages, context));
  }

  void goToDetailPage(GalleryDownloadInfo gallery) {
    toRoute(
      Routes.details,
      arguments:
          DetailsPageArgument(galleryUrl: GalleryUrl.parse(gallery.galleryUrl)),
    );
  }

  @override
  Future<bool> locateDownloadTask(int gid, BuildContext context) async {
    final GalleryDownloadInfo? target =
        downloadService.galleryDownloadInfos[gid];
    if (target == null) {
      return false;
    }
    exitEditMode();
    final GlobalKey itemKey = GlobalKey(debugLabel: 'download-$gid');
    state.navigationItemKeys[gid] = itemKey;
    if (state.currentGroup != target.group) {
      enterGroup(target.group);
    } else {
      update([bodyId]);
    }
    try {
      await WidgetsBinding.instance.endOfFrame;

      final List<GalleryDownloadInfo> items =
          state.currentGalleryObjects.cast<GalleryDownloadInfo>();
      final int targetIndex = items.indexWhere((item) => item.gid == gid);
      if (targetIndex < 0 || !state.galleryScrollController.hasClients) {
        return false;
      }
      const double horizontalPadding = 12 + 16;
      final double availableWidth = max(
        1,
        (context.size?.width ?? MediaQuery.sizeOf(context).width) -
            horizontalPadding,
      );
      final int crossAxisCount = downloadGridCrossAxisCount(
        availableWidth: availableWidth,
        configuredCount:
            styleSetting.crossAxisCountInGridDownloadPageForGallery.value,
        maxCrossAxisExtent: UIConfig.downloadPageGridViewCardWidth,
        crossAxisSpacing: 12,
      );
      final double offset = downloadGridTaskOffset(
        itemIndex: targetIndex + 1,
        crossAxisCount: crossAxisCount,
        availableWidth: availableWidth,
        crossAxisSpacing: 12,
        mainAxisSpacing: 24,
        childAspectRatio: UIConfig.downloadPageGridViewCardAspectRatio,
      );
      return await revealDownloadTask(
        controller: state.galleryScrollController,
        itemKey: itemKey,
        estimatedOffset: offset,
      );
    } finally {
      state.navigationItemKeys.remove(gid);
      update([bodyId]);
    }
  }

  @override
  void toggleEditMode() {
    if (gridBasePageState.inEditMode) {
      exitEditMode();
      return;
    }
    exitSelectMode();
    toast('drag2sort'.tr);
    gridBasePageState.inEditMode = true;
    registerDownloadReorderMode(this);
    update([bodyId, editButtonId]);
  }

  @override
  void selectAllItem() {
    multiSelectDownloadPageState.selectedGids.clear();
    multiSelectDownloadPageState.selectedGids
        .addAll(state.currentGalleryObjects.map((archive) => archive.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids
        .map((gid) => '$itemCardId::$gid')
        .toList());
  }

  @override
  Future<void> saveGalleryOrderAfterDrag(
      int beforeIndex, int afterIndex) async {
    List<GalleryDownloadInfo> galleries = state.currentGalleryObjects.cast();

    /// default order is 0, we must assign current order to the archive first
    for (int i = 0; i < galleries.length; i++) {
      galleries[i].sortOrder = i;
    }

    int head = min(beforeIndex, afterIndex);
    int tail = max(beforeIndex, afterIndex);

    for (int index = head; index <= tail; index++) {
      GalleryDownloadInfo galleryDownloadInfo = galleries[index];

      if (index == beforeIndex) {
        galleryDownloadInfo.sortOrder = afterIndex;
      } else if (beforeIndex < afterIndex) {
        galleryDownloadInfo.sortOrder = index - 1;
      } else {
        galleryDownloadInfo.sortOrder = index + 1;
      }
    }

    await downloadService.updateGalleryOrder(galleries);
  }

  @override
  Future<void> saveGroupOrderAfterDrag(int beforeIndex, int afterIndex) async {
    return downloadService.updateGroupOrder(beforeIndex, afterIndex);
  }
}
