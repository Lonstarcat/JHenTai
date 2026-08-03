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
import 'gallery_list_download_page_state.dart';

class GalleryListDownloadPageLogic extends GetxController
    with Scroll2TopLogicMixin, MultiSelectDownloadPageLogicMixin<GalleryDownloadedData>, GalleryDownloadPageLogicMixin, UpdateGlobalGalleryStatusLogicMixin {
  GalleryListDownloadPageState state = GalleryListDownloadPageState();

  @override
  MultiSelectDownloadPageStateMixin get multiSelectDownloadPageState => state;

  @override
  Scroll2TopStateMixin get scroll2TopState => state;

  late Worker maxGalleryNum4AnimationListener;

  @override
  Future<void> onInit() async {
    super.onInit();

    String? displayGroupsString = await localConfigService.read(configKey: ConfigEnum.displayGalleryGroups);
    if (displayGroupsString == null) {
      state.displayGroups = {'default'.tr};
    } else {
      state.displayGroups = Set.from(jsonDecode(displayGroupsString));
    }
    state.displayGroupsCompleter.complete();

    maxGalleryNum4AnimationListener = ever(performanceSetting.maxGalleryNum4Animation, (_) => updateSafely([bodyId]));
  }

  @override
  void onClose() {
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

      int groupCmp = (groupOrder[aGroup] ?? 9999).compareTo(groupOrder[bGroup] ?? 9999);
      if (groupCmp != 0) return groupCmp;

      switch (state.sortBy) {
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

  void toggleEditMode() {
    if (!state.inEditMode) {
      exitSelectMode();
      state.currentGroup = null;
      toast('sortGroupsHint'.tr);
    } else {
      state.currentGroup = null;
    }
    state.inEditMode = !state.inEditMode;
    updateSafely([bodyId]);
  }

  void enterGroup(String group) {
    state.currentGroup = group;
    updateSafely([bodyId]);
  }

  void backGroup() {
    state.currentGroup = null;
    updateSafely([bodyId]);
  }

  Future<void> saveGalleryOrderAfterReordered(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    // Flutter adds 1 to newIndex when dragging downward
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    List<GalleryDownloadedData> gallerys;
    if (state.currentGroup != null) {
      gallerys = List.from(downloadService.gallerysWithGroup(state.currentGroup!));
    } else {
      gallerys = List.from(downloadService.gallerys);
    }

    GalleryDownloadedData moved = gallerys.removeAt(oldIndex);
    gallerys.insert(newIndex, moved);

    for (int i = 0; i < gallerys.length; i++) {
      downloadService.galleryDownloadInfos[gallerys[i].gid]!.sortOrder = i;
    }

    await downloadService.updateGalleryOrder(gallerys);
    updateSafely([bodyId]);
  }

  Future<void> saveGroupOrderAfterReordered(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    downloadService.allGroups.insert(newIndex, downloadService.allGroups.removeAt(oldIndex));

    for (int i = 0; i < downloadService.allGroups.length; i++) {
      await GalleryGroupDao.updateGalleryGroupOrder(downloadService.allGroups[i], i);
    }
    updateSafely([bodyId]);
  }

  Future<void> toggleDisplayGroups(String groupName) async {
    await state.displayGroupsCompleter.future;

    if (state.displayGroups.contains(groupName)) {
      state.displayGroups.remove(groupName);
    } else {
      state.displayGroups.add(groupName);
    }

    await localConfigService.write(configKey: ConfigEnum.displayGalleryGroups, value: jsonEncode(state.displayGroups.toList()));
    state.groupedListController.toggleGroup(groupName);
  }

  @override
  Future<void> doRenameGroup(String oldGroup, String newGroup) async {
    await state.displayGroupsCompleter.future;

    state.displayGroups.remove(oldGroup);
    return super.doRenameGroup(oldGroup, newGroup);
  }

  @override
  void handleRemoveItem(GalleryDownloadedData gallery, bool deleteImages, BuildContext context) async {
    bool confirmed = await confirmDestructiveAction(title: deleteImages ? 'deleteTaskAndImages'.tr + '?' : 'deleteTask'.tr + '?');
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

    multiSelectDownloadPageState.selectedGids.addAll(gallerys.map((gallery) => gallery.gid));
    updateSafely(multiSelectDownloadPageState.selectedGids.map((gid) => '$itemCardId::$gid').toList());
  }
}
