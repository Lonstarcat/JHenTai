import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/enum/config_enum.dart';
import 'package:jhentai/src/extension/get_logic_extension.dart';
import 'package:jhentai/src/pages/download/mixin/gallery/gallery_download_page_logic_mixin.dart';
import 'package:jhentai/src/setting/performance_setting.dart';
import 'package:jhentai/src/utils/toast_util.dart';

import '../../../../database/database.dart';
import '../../../../database/dao/gallery_group_dao.dart';
import '../../../../mixin/scroll_to_top_logic_mixin.dart';
import '../../../../mixin/scroll_to_top_state_mixin.dart';
import '../../../../mixin/update_global_gallery_status_logic_mixin.dart';
import '../../../../service/local_config_service.dart';
import '../../../../widget/eh_alert_dialog.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_logic_mixin.dart';
import '../../mixin/basic/multi_select/multi_select_download_page_state_mixin.dart';
import '../../download_reorder_mode.dart';
import '../widget/download_reorder_widgets.dart';
import 'gallery_list_download_page_state.dart';

class GalleryListDownloadPageLogic extends GetxController
    with
        Scroll2TopLogicMixin,
        MultiSelectDownloadPageLogicMixin<GalleryDownloadedData>,
        GalleryDownloadPageLogicMixin,
        UpdateGlobalGalleryStatusLogicMixin
    implements DownloadReorderModeParticipant {
  GalleryListDownloadPageState state = GalleryListDownloadPageState();

  @override
  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState => state;

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  late Worker maxGalleryNum4AnimationListener;

  @override
  Future<void> onInit() async {
    super.onInit();

    String? displayGroupsString = await localConfigService.read(
        configKey: ConfigEnum.displayGalleryGroups);
    if (displayGroupsString == null) {
      state.displayGroups = {'default'.tr};
    } else {
      state.displayGroups = Set.from(jsonDecode(displayGroupsString));
    }
    state.displayGroupsCompleter.complete();

    maxGalleryNum4AnimationListener = ever(
        performanceSetting.maxGalleryNum4Animation,
        (_) => updateSafely([bodyId]));
  }

  @override
  void onClose() {
    unregisterDownloadReorderMode(this);
    super.onClose();

    maxGalleryNum4AnimationListener.dispose();
  }

  List<GalleryDownloadedData> get sortedGallerys {
    List<GalleryDownloadedData> sorted = [...downloadService.gallerys];

    Map<String, int> groupOrder = {};
    for (int i = 0; i < downloadService.allGroups.length; i++) {
      groupOrder[downloadService.allGroups[i]] = i;
    }

    sorted.sort((a, b) {
      String aGroup = downloadService.galleryDownloadInfos[a.gid]!.group;
      String bGroup = downloadService.galleryDownloadInfos[b.gid]!.group;

      int groupCmp =
          (groupOrder[aGroup] ?? 9999).compareTo(groupOrder[bGroup] ?? 9999);
      if (groupCmp != 0) {
        return groupCmp;
      }

      switch (state.sortBy) {
        case SortBy.manual:
          return compareDownloadManualOrder(
            firstOrder: downloadService.galleryDownloadInfos[a.gid]!.sortOrder,
            secondOrder: downloadService.galleryDownloadInfos[b.gid]!.sortOrder,
            fallbackComparison: b.insertTime.compareTo(a.insertTime),
          );
        case SortBy.title:
          return a.title.compareTo(b.title);
        case SortBy.publishTime:
          return b.publishTime.compareTo(a.publishTime);
        case SortBy.insertTime:
          return b.insertTime.compareTo(a.insertTime);
      }
    });

    return sorted;
  }

  List<DownloadReorderEntry<GalleryDownloadedData>> get reorderEntries {
    final List<GalleryDownloadedData> displayedGallerys = sortedGallerys;
    return buildDownloadReorderEntries(
      groups: downloadService.allGroups,
      isGroupOpen: state.displayGroups.contains,
      itemsForGroup: (group) => displayedGallerys.where((gallery) =>
          downloadService.galleryDownloadInfos[gallery.gid]!.group == group),
    );
  }

  void toggleEditMode() {
    if (state.inEditMode) {
      exitEditMode();
      return;
    }
    final double? scrollOffset = state.scrollController.hasClients
        ? state.scrollController.offset
        : null;
    exitSelectMode();
    toast('sortGroupsHint'.tr);
    state.inEditMode = true;
    registerDownloadReorderMode(this);
    updateSafely([bodyId]);
    restoreDownloadListScrollOffset(state.scrollController, scrollOffset);
  }

  @override
  void exitEditMode() {
    if (!state.inEditMode) {
      return;
    }
    final double? scrollOffset = state.scrollController.hasClients
        ? state.scrollController.offset
        : null;
    state.inEditMode = false;
    unregisterDownloadReorderMode(this);
    updateSafely([bodyId]);
    restoreDownloadListScrollOffset(state.scrollController, scrollOffset);
  }

  Future<void> saveOrderAfterReordered(
    List<DownloadReorderEntry<GalleryDownloadedData>> entries,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex == newIndex) {
      return;
    }

    final DownloadReorderEntry<GalleryDownloadedData> moved = entries[oldIndex];
    final List<DownloadReorderEntry<GalleryDownloadedData>> reordered =
        reorderDownloadEntries(entries, oldIndex, newIndex);

    if (moved.isGroup) {
      final List<String> groups = reordered
          .where((entry) => entry.isGroup)
          .map((entry) => entry.groupName)
          .toList();
      downloadService.allGroups
        ..clear()
        ..addAll(groups);
      updateSafely([bodyId]);
      for (int i = 0; i < groups.length; i++) {
        await GalleryGroupDao.updateGalleryGroupOrder(groups[i], i);
      }
    } else {
      final List<GalleryDownloadedData> gallerys = reordered
          .where(
              (entry) => !entry.isGroup && entry.groupName == moved.groupName)
          .map((entry) => entry.item!)
          .toList();
      for (int i = 0; i < gallerys.length; i++) {
        downloadService.galleryDownloadInfos[gallerys[i].gid]!.sortOrder = i;
      }
      state.sortBy = SortBy.manual;
      updateSafely([bodyId]);
      await downloadService.updateGalleryOrder(gallerys);
    }
  }

  Future<void> toggleDisplayGroups(String groupName) async {
    await state.displayGroupsCompleter.future;

    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    await localConfigService.write(
        configKey: ConfigEnum.displayGalleryGroups,
        value: jsonEncode(state.displayGroups.toList()));
    if (state.inEditMode) {
      updateSafely([bodyId]);
    } else {
      state.groupedListController.toggleGroup(groupName);
    }
  }

  @override
  Future<void> doRenameGroup(String oldGroup, String newGroup) async {
    await state.displayGroupsCompleter.future;

    state.displayGroups.remove(oldGroup);
    return super.doRenameGroup(oldGroup, newGroup);
  }

  @override
  void handleRemoveItem(GalleryDownloadedData gallery, bool deleteImages,
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

    state.groupedListController.removeElement(gallery).then((_) {
      state.selectedGids.remove(gallery.gid);
      downloadService.deleteGallery(gallery, deleteImages: deleteImages);
      updateGlobalGalleryStatus();
    });
  }

  @override
  Future<void> selectAllItem() async {
    await state.displayGroupsCompleter.future;

    List<GalleryDownloadedData> gallerys = [];
    for (String group in state.displayGroups) {
      gallerys.addAll(downloadService.gallerysWithGroup(group));
    }

    multiSelectDownloadPageState.selectedGids
        .addAll(gallerys.map((gallery) => gallery.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids
        .map((gid) => '$itemCardId::$gid')
        .toList());
  }
}
