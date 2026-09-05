import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/mixin/scroll_to_top_logic_mixin.dart';
import 'package:jhentai/src/mixin/update_global_gallery_status_logic_mixin.dart';
import 'package:jhentai/src/model/gallery_url.dart';
import 'package:jhentai/src/pages/details/details_page_logic.dart';
import 'package:jhentai/src/pages/download/mixin/archive/archive_download_page_state_mixin.dart';
import 'package:jhentai/src/service/archive_download_service.dart';
import 'package:jhentai/src/setting/style_setting.dart';

import '../../../../database/database.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../routes/routes.dart';
import '../../../../utils/route_util.dart';
import '../../../../utils/download_task_locator_util.dart';
import '../../../../utils/toast_util.dart';
import '../../mixin/archive/archive_download_page_logic_mixin.dart';
import '../../download_reorder_mode.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import '../mixin/grid_download_page_logic_mixin.dart';
import '../mixin/grid_download_page_service_mixin.dart';
import '../mixin/grid_download_page_state_mixin.dart';
import 'archive_grid_download_page_state.dart';

class ArchiveGridDownloadPageLogic extends GetxController
    with
        Scroll2TopLogicMixin,
        MultiSelectDownloadPageLogicMixin<ArchiveDownloadedData>,
        ArchiveDownloadPageLogicMixin,
        GridBasePageLogic,
        UpdateGlobalGalleryStatusLogicMixin {
  final ArchiveGridDownloadPageState state = ArchiveGridDownloadPageState();

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  @override
  GridBasePageState get gridBasePageState => state;

  @override
  ArchiveDownloadPageStateMixin get archiveDownloadPageState => state;

  @override
  GridBasePageServiceMixin get galleryService => archiveDownloadService;

  void handleTapTitle(ArchiveDownloadedData archive) {
    if (multiSelectDownloadPageState.inMultiSelectMode) {
      toggleSelectItem(archive.gid);
    } else {
      goToDetailPage(archive);
    }
  }

  @override
  Future<void> handleRemoveItem(ArchiveDownloadedData archive) async {
    bool confirmed = await confirmDestructiveAction(title: 'delete'.tr + '?');
    if (!confirmed) {
      return;
    }
    await archiveDownloadService
        .deleteArchive(archive.gid)
        .then((_) => super.handleRemoveItem(archive));
    updateGlobalGalleryStatus();
  }

  void goToDetailPage(ArchiveDownloadedData archive) {
    toRoute(
      Routes.details,
      arguments:
          DetailsPageArgument(galleryUrl: GalleryUrl.parse(archive.galleryUrl)),
    );
  }

  @override
  Future<bool> locateDownloadTask(int gid, BuildContext context) async {
    ArchiveDownloadedData? target;
    for (final ArchiveDownloadedData archive
        in archiveDownloadService.archives) {
      if (archive.gid == gid) {
        target = archive;
        break;
      }
    }
    if (target == null) {
      return false;
    }
    exitEditMode();
    final GlobalKey itemKey = GlobalKey(debugLabel: 'archive-$gid');
    state.navigationItemKeys[gid] = itemKey;
    final String group =
        archiveDownloadService.archiveDownloadInfos[gid]!.group;
    if (state.currentGroup != group) {
      enterGroup(group);
    } else {
      update([bodyId]);
    }
    try {
      await WidgetsBinding.instance.endOfFrame;

      final List<ArchiveDownloadedData> items =
          state.currentGalleryObjects.cast<ArchiveDownloadedData>();
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
    if (!gridBasePageState.inEditMode) {
      exitSelectMode();
      toast('drag2sort'.tr);
    }
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
    List<ArchiveDownloadedData> archives = state.currentGalleryObjects.cast();

    /// default order is 0, we must assign current order to the archive first
    for (int i = 0; i < archives.length; i++) {
      ArchiveDownloadedData archive = archives[i];
      ArchiveDownloadInfo archiveDownloadInfo =
          archiveDownloadService.archiveDownloadInfos[archive.gid]!;
      archiveDownloadInfo.sortOrder = i;
    }

    int head = min(beforeIndex, afterIndex);
    int tail = max(beforeIndex, afterIndex);

    for (int index = head; index <= tail; index++) {
      ArchiveDownloadInfo archiveDownloadInfo =
          archiveDownloadService.archiveDownloadInfos[archives[index].gid]!;

      if (index == beforeIndex) {
        archiveDownloadInfo.sortOrder = afterIndex;
      } else if (beforeIndex < afterIndex) {
        archiveDownloadInfo.sortOrder = index - 1;
      } else {
        archiveDownloadInfo.sortOrder = index + 1;
      }
    }

    await archiveDownloadService.batchUpdateArchiveInDatabase(archives);
  }

  @override
  Future<void> saveGroupOrderAfterDrag(int beforeIndex, int afterIndex) {
    return archiveDownloadService.updateGroupOrder(beforeIndex, afterIndex);
  }

  @override
  Future<void> changeParseSource(
      int gid, ArchiveParseSource parseSource) async {
    await super.changeParseSource(gid, parseSource);
    updateSafely(['${super.galleryId}::$gid']);
  }
}
